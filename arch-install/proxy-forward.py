#!/usr/bin/env python3
"""TCP 端口转发器：把 Parallels 虚拟网段上的端口转发到宿主机本地代理。

背景：宿主机的 /etc/hosts 将 github.com 等域名解析到 127.0.0.1（屏蔽），
宿主机自身通过本地 HTTP 代理（127.0.0.1:53551）访问外网；
而该代理只监听回环地址，虚拟机无法直接使用。

本转发器在 Parallels 网段上监听一个端口，把流量原样转发到宿主机的本地代理，
使虚拟机可以配置 `http_proxy=http://<宿主机虚拟网段IP>:8888` 复用同一通路。

仅绑定 Parallels 虚拟网段，不暴露到 WiFi / 局域网。
"""
import os
import socket
import threading
import sys
import time

# 参数均可用环境变量覆盖，便于测试与适配不同环境
LISTEN_HOST = os.environ.get("FORWARD_LISTEN_HOST", "10.211.55.2")
LISTEN_PORT = int(os.environ.get("FORWARD_LISTEN_PORT", "8888"))
TARGET_HOST = os.environ.get("FORWARD_TARGET_HOST", "127.0.0.1")
TARGET_PORT = int(os.environ.get("FORWARD_TARGET_PORT", "53551"))

BUF = 65536
CONNECT_TIMEOUT = 15      # 仅作用于「建立连接」阶段，连接后必须清除
MAX_CONNECTIONS = 128     # 并发上限，防止连接耗尽线程与文件描述符
SEM = threading.Semaphore(MAX_CONNECTIONS)


def pipe(src, dst):
    """单向转发。

    读到 EOF 时只对目标方向做「半关闭」（SHUT_WR），而非直接关闭两个 socket。
    原因：HTTP 隧道允许单向先行结束，此时反方向可能仍有数据在传；
    若在此处直接 close()，会截断尚未传完的响应。
    """
    try:
        while True:
            data = src.recv(BUF)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass
        try:
            src.close()
        except OSError:
            pass


def handle(client, peer):
    try:
        upstream = socket.create_connection((TARGET_HOST, TARGET_PORT), timeout=CONNECT_TIMEOUT)
        # 关键修复：create_connection 的 timeout 会保留在 socket 上。
        # 若不清除，后续 recv() 在空闲超过 CONNECT_TIMEOUT 后会抛 TimeoutError，
        # 而它是 OSError 的子类，会被 pipe() 的 except OSError 静默吞掉并断连——
        # 表现为「隧道空闲十几秒后莫名中断」。故连接建立后必须置回阻塞模式。
        upstream.settimeout(None)
    except OSError as exc:
        print("connect upstream failed from %s: %s" % (peer[0], exc), flush=True)
        try:
            client.close()
        except OSError:
            pass
        return
    t1 = threading.Thread(target=pipe, args=(client, upstream), daemon=True)
    t2 = threading.Thread(target=pipe, args=(upstream, client), daemon=True)
    t1.start()
    t2.start()
    # 必须等待双向转发都结束再返回，否则并发计数会在连接仍存活时被提前释放
    t1.join()
    t2.join()


def _serve_client(client, peer):
    """带并发上限的包装：无论处理过程如何结束，都必须释放信号量。"""
    try:
        handle(client, peer)
    finally:
        SEM.release()


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
        except InterruptedError:
            continue
        except OSError as exc:
            # 区分瞬时错误与致命错误：无条件 continue 会在 fd 失效时形成忙等循环（CPU 占满）
            print("accept failed: %s" % exc, flush=True)
            time.sleep(0.5)
            continue
        SEM.acquire()
        threading.Thread(target=_serve_client, args=(client, peer), daemon=True).start()


if __name__ == "__main__":
    main()
