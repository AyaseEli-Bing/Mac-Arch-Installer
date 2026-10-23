#!/usr/bin/env python3
"""临时服务：向 Archboot live 环境分发安装脚本，并接收其回传的安装日志。

默认只监听 Parallels 的两张虚拟网卡（Shared 10.211.55.2 / Host-Only 10.37.129.2），
不暴露到其他网络。可用环境变量覆盖：
    SERVE_HOSTS=127.0.0.1   # 逗号分隔的绑定地址（本地冒烟测试用）
    PORT=8765               # 端口冲突或本地测试时改端口
在非 Parallels 机器上给 SERVE_HOSTS 一个本机地址即可启动，便于离线验证分发链路。
"""
import http.server
import socketserver
import os
import re
import threading
import datetime

BASE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(BASE, "install.sh")
LOGFILE = os.path.join(BASE, "log.txt")
DEFAULT_HOSTS = "10.211.55.2,10.37.129.2"   # Parallels Shared / Host-Only 虚拟网卡


def _env_hosts():
    raw = os.environ.get("SERVE_HOSTS", DEFAULT_HOSTS)
    hosts = [h.strip() for h in raw.split(",") if h.strip()]
    if not hosts:
        raise SystemExit("SERVE_HOSTS 为空：请给出至少一个绑定地址，例如 SERVE_HOSTS=127.0.0.1")
    return hosts


def _env_port():
    raw = os.environ.get("PORT", "8000")
    try:
        port = int(raw)
    except ValueError:
        raise SystemExit("PORT 必须是整数（当前为 %r），例如 PORT=8765 python3 serve.py" % raw)
    if not 1 <= port <= 65535:
        raise SystemExit("PORT 超出 1-65535 范围（当前为 %d）" % port)
    return port


BIND_HOSTS = _env_hosts()
BIND_PORT = _env_port()
RESET_FILE = os.path.join(BASE, "reset-password.sh")
KEY_FILE = os.path.join(BASE, "sshkey.pub")
MAX_BODY = 1_048_576      # 1 MB：日志回传远小于此，超出即视为异常请求

RUN_RE = re.compile(rb"run=(\S+)")
# 保留宿主机自己的时间戳：虚拟机时钟可能不准（实测挂起恢复后会停在挂起那一刻），
# 宿主侧时间是独立于客户机的一路旁证。
_log_lock = threading.Lock()
_last_run = {"id": None}


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
            m = RUN_RE.search(body)
            run_id = m.group(1).decode("utf-8", "replace") if m else None
            try:
                with _log_lock:
                    chunks = []
                    # 换一次安装就插一条分隔行：重装不再覆盖上一次的记录，
                    # 两次尝试的日志能并存对比（此前重启服务即销毁证据）
                    if run_id and run_id != _last_run["id"]:
                        chunks.append(("\n---- run %s ----\n" % run_id).encode())
                        _last_run["id"] = run_id
                    chunks.append(("[%s] " % ts).encode() + body + b"\n")
                    with open(LOGFILE, "ab") as f:
                        f.write(b"".join(chunks))
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
    # 刻意不在启动时删除 log.txt：安装失败后重启服务是常见动作，
    # 原先这一步会把上一次尝试的记录一并抹掉，事后无从对比两次尝试。
    # 运行边界改由每个 run= 字段对应的分隔行标示。
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
        raise SystemExit("no listener could be started（检查 SERVE_HOSTS=%s 是否为本机拥有的地址）"
                         % ",".join(BIND_HOSTS))
    for t in threads:
        t.join()
