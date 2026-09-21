#!/usr/bin/env python3
"""TCP 端口转发器：把 Parallels 虚拟网段上的端口转发到宿主机本地代理。

背景：宿主机的 /etc/hosts 将 github.com 等域名解析到 127.0.0.1（屏蔽），
宿主机自身通过本地 HTTP 代理（127.0.0.1:53551）访问外网；
而该代理只监听回环地址，虚拟机无法直接使用。

本转发器在 Parallels 网段上监听一个端口，把流量原样转发到宿主机的本地代理，
使虚拟机可以配置 `http_proxy=http://<宿主机虚拟网段IP>:8888` 复用同一通路。

仅绑定 Parallels 虚拟网段，不暴露到 WiFi / 局域网。
"""
import socket
import threading
import sys

LISTEN_HOST = "10.211.55.2"     # Parallels Shared 网段上宿主机的地址
LISTEN_PORT = 8888
TARGET_HOST = "127.0.0.1"        # 宿主机本地 HTTP 代理
TARGET_PORT = 53551

BUF = 65536


def pipe(src, dst):
    """单向转发，任一端关闭则同时关闭两端。"""
    try:
        while True:
            data = src.recv(BUF)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                s.close()
            except OSError:
                pass


def handle(client, peer):
    try:
        upstream = socket.create_connection((TARGET_HOST, TARGET_PORT), timeout=15)
    except OSError as exc:
        print("connect upstream failed: %s" % exc, flush=True)
        try:
            client.close()
        except OSError:
            pass
        return
    threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pipe, args=(upstream, client), daemon=True).start()


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind((LISTEN_HOST, LISTEN_PORT))
    except OSError as exc:
        print("bind %s:%d failed: %s" % (LISTEN_HOST, LISTEN_PORT, exc), flush=True)
        sys.exit(1)
    srv.listen(128)
    print("forwarding %s:%d  ->  %s:%d" % (LISTEN_HOST, LISTEN_PORT, TARGET_HOST, TARGET_PORT), flush=True)
    while True:
        try:
            client, peer = srv.accept()
        except OSError:
            continue
        threading.Thread(target=handle, args=(client, peer), daemon=True).start()


if __name__ == "__main__":
    main()
