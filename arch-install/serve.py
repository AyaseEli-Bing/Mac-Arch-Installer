#!/usr/bin/env python3
"""临时服务：向 Archboot live 环境分发安装脚本，并接收其回传的安装日志。
仅绑定 Parallels Host-Only 网段地址 10.37.129.2（虚拟机所在网段），不暴露到其他网络。
"""
import http.server
import socketserver
import os
import threading
import datetime

BASE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(BASE, "install.sh")
LOGFILE = os.path.join(BASE, "log.txt")
# 同时监听 Parallels 的两张虚拟网卡：Shared(10.211.55.2) 与 Host-Only(10.37.129.2)
BIND_HOSTS = ["10.211.55.2", "10.37.129.2"]
BIND_PORT = 8000
RESET_FILE = os.path.join(BASE, "reset-password.sh")
KEY_FILE = os.path.join(BASE, "sshkey.pub")
MAX_BODY = 1_048_576      # 1 MB：日志回传远小于此，超出即视为异常请求


class Handler(http.server.BaseHTTPRequestHandler):
    def _acc(self, method):
        ts = datetime.datetime.now().strftime("%H:%M:%S")
        try:
            with open(os.path.join(BASE, "access.log"), "ab") as f:
                f.write(("[%s] %s %s from %s\n" % (ts, method, self.path, self.client_address[0])).encode())
        except OSError:
            pass

    def _send(self, code, body=b"", ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _file(self, path, notfound_msg):
        try:
            with open(path, "rb") as f:
                data = f.read()
            self._send(200, data)
        except OSError:
            self._send(404, notfound_msg)

    def do_GET(self):
        self._acc("GET")
        # 精确匹配路由（去掉查询串与尾部斜杠）：
        # 原用 startswith 前缀匹配，/key 会命中 /k、/index 会命中 /i，行为不可预期
        path = self.path.split("?")[0].rstrip("/") or "/"
        if path == "/k":
            # 分发宿主机 SSH 公钥（公钥本身非敏感信息）
            self._file(KEY_FILE, b"key not found")
        elif path == "/r":
            # 分发密码重置脚本（仅本地虚拟机网段可达）
            self._file(RESET_FILE, b"reset script not found")
        elif path in ("/i", "/install.sh"):
            self._file(SCRIPT, b"script not found")
        elif path == "/ping":
            self._send(200, b"ok")
        else:
            self._send(404, b"not found")

    def do_POST(self):
        self._acc("POST")
        raw = self.headers.get("Content-Length", 0) or 0
        try:
            length = int(raw)
        except (TypeError, ValueError):
            length = 0
        if length < 0 or length > MAX_BODY:
            # 不按声明的长度读取：超大 Content-Length 会导致阻塞等待或内存耗尽
            self._send(413, b"payload too large")
            return
        body = self.rfile.read(length) if length else b""
        if self.path.split("?")[0].rstrip("/") == "/log":
            ts = datetime.datetime.now().strftime("%H:%M:%S")
            try:
                with open(LOGFILE, "ab") as f:
                    f.write(("[%s] " % ts).encode() + body + b"\n")
            except OSError:
                pass
            self._send(200, b"ok")
        else:
            # 未知路径不再返回 200，便于客户端区分成功与路径错误
            self._send(404, b"not found")

    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    if os.path.exists(LOGFILE):
        os.remove(LOGFILE)
    threads = []
    for host in BIND_HOSTS:
        try:
            srv = Server((host, BIND_PORT), Handler)
        except OSError as exc:
            print("bind %s failed: %s" % (host, exc), flush=True)
            continue
        t = threading.Thread(target=srv.serve_forever, daemon=True)
        t.start()
        threads.append(t)
        print("listening on %s:%d" % (host, BIND_PORT), flush=True)
    if not threads:
        raise SystemExit("no listener could be started")
    for t in threads:
        t.join()
