#!/bin/bash
# ============================================================
# 环境自检脚本（宿主机侧，安装前运行）
#
# 用法:
#   bash check.sh                      # 使用默认配置
#   VM="我的虚拟机" bash check.sh       # 指定虚拟机名称
#   PORT=8000 bash check.sh            # 指定分发服务端口
#   EXPECT_SHA=<sha256> bash check.sh  # 启用 ISO 哈希校验
#
# 退出码 = 未通过项数量（0 表示环境就绪，可用于脚本集成）
# 兼容 macOS 自带 bash 3.2
# ============================================================

# ---------- 可覆盖配置 ----------
PRL="${PRL:-/Applications/Parallels Desktop.app/Contents/MacOS/prlctl}"
VM="${VM:-Arch Linux}"
PORT="${PORT:-8000}"
EXPECT_SHA="${EXPECT_SHA:-}"      # 留空 = 仅检查文件存在，不校验哈希

# ---------- Python 运行时自动探测 ----------
if [ -z "${PY:-}" ]; then
    PY=""
    for c in python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
        if command -v "$c" >/dev/null 2>&1; then
            PY="$(command -v "$c")"
            break
        fi
    done
fi

# ---------- Archboot ISO 自动探测（取最新的一个）----------
if [ -z "${ISO:-}" ]; then
    ISO="$(ls -t "$HOME"/Downloads/archboot-*-aarch64-ARCH-aarch64.iso 2>/dev/null | head -1)"
fi

PASS=0
FAIL=0
ok()  { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=============================================="
echo " Arch Linux ARM 安装环境自检"
echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ---------- 1. 宿主机工具 ----------
echo ""
echo "[1/4] 宿主机工具"
if [ -x "$PRL" ]; then
    ok "prlctl 可用"
else
    bad "prlctl 不可用（期望路径: $PRL）"
fi
if [ -n "$PY" ]; then
    ok "Python 运行时存在（$("$PY" --version 2>&1 | head -1)）"
else
    bad "未找到 python3"
fi
if command -v curl >/dev/null 2>&1; then
    ok "curl 可用"
else
    bad "curl 不可用"
fi

# ---------- 2. 安装介质 ----------
echo ""
echo "[2/4] 安装介质"
if [ -n "$ISO" ] && [ -f "$ISO" ]; then
    ok "Archboot ISO 已下载（$(basename "$ISO")）"
    echo "       大小: $(ls -lh "$ISO" | awk '{print $5}')"
    if [ -n "$EXPECT_SHA" ]; then
        ACTUAL=$(shasum -a 256 "$ISO" 2>/dev/null | awk '{print $1}')
        if [ "$ACTUAL" = "$EXPECT_SHA" ]; then
            ok "ISO SHA256 校验通过"
        else
            bad "ISO SHA256 不匹配（实际 $ACTUAL）"
        fi
    else
        echo "       （未提供 EXPECT_SHA，已跳过哈希校验）"
    fi
else
    bad "未找到 Archboot ISO"
    echo "       在 ~/Downloads 下未匹配到 archboot-*-aarch64-ARCH-aarch64.iso"
fi

# ---------- 3. 虚拟机状态 ----------
echo ""
echo "[3/4] 虚拟机状态"
if "$PRL" list -a 2>/dev/null | grep -qF "$VM"; then
    ok "虚拟机 '$VM' 存在"
    STATE=$("$PRL" list -i "$VM" 2>/dev/null | grep -m1 '^State:' | awk '{print $2}')
    echo "       当前状态: ${STATE:-未知}"
    if "$PRL" list -i "$VM" 2>/dev/null | grep -q 'net0.*type=shared'; then
        ok "网卡类型为 shared（可上外网）"
    else
        bad "网卡类型不是 shared —— 会导致虚拟机无外网，所有镜像站连不上"
        echo "       修复: \"$PRL\" set \"$VM\" --device-set net0 --type shared"
    fi
else
    bad "虚拟机 '$VM' 不存在"
    echo "       可用 VM=\"名称\" 指定其他虚拟机"
fi

# ---------- 4. 分发服务 ----------
echo ""
echo "[4/4] 分发服务"
# 优先用 lsof 判断（macOS 自带）；若环境未提供则回退到 nc 探测，
# 避免把「探测工具缺失」误判成「端口未监听」
if command -v lsof >/dev/null 2>&1; then
    BOUND=$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | grep -c LISTEN)
elif nc -z -G 1 127.0.0.1 "$PORT" >/dev/null 2>&1; then
    BOUND=1
else
    BOUND=0
fi
if [ "$BOUND" -gt 0 ]; then
    ok "端口 $PORT 已监听（$BOUND 个地址）"
    for ip in 10.211.55.2 10.37.129.2; do
        R=$(curl -s -m 3 "http://$ip:$PORT/ping" 2>/dev/null)
        if [ "$R" = "ok" ]; then
            ok "http://$ip:$PORT 响应正常"
        else
            bad "http://$ip:$PORT 无响应"
        fi
    done
    CODE=$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://10.211.55.2:$PORT/i" 2>/dev/null)
    if [ "$CODE" = "200" ]; then
        ok "install.sh 可下载（HTTP $CODE）"
    else
        bad "install.sh 下载异常（HTTP $CODE）"
    fi
else
    bad "端口 $PORT 未监听 —— 分发服务未启动"
    echo "       修复: cd arch-install && python3 serve.py"
fi

# ---------- 汇总 ----------
echo ""
echo "=============================================="
echo " 结果: 通过 $PASS 项, 未通过 $FAIL 项"
echo "=============================================="
if [ "$FAIL" -eq 0 ]; then
    echo " 环境就绪，可以开始安装"
else
    echo " 存在未通过项，请按上方提示处理"
fi
exit "$FAIL"
