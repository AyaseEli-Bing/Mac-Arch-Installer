#!/bin/bash
# ============================================================
# 环境自检脚本（宿主机侧）
# 用法: bash check.sh
# 兼容 macOS 自带 bash 3.2
# ============================================================

PRL="/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"
PY="/Users/bing1111/.workbuddy/binaries/python/versions/3.13.12/bin/python3"
VM="Arch Linux"
PORT=8000
ISO_NAME="archboot-2026.09.21-02.26-7.2.6-1-aarch64-ARCH-aarch64.iso"
ISO="$HOME/Downloads/$ISO_NAME"
EXPECT_SHA="00e54a62f5e367ce320b053b2715e6cd33d66d34c51091b06c74f189902fc181"

PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

check() { # $1=描述 $2=命令
    if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi
}

echo "=============================================="
echo " Arch Linux ARM 安装环境自检"
echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

echo ""
echo "[1/4] 宿主机工具"
check "prlctl 可用"            "[ -x \"$PRL\" ]"
check "Python 运行时存在"      "[ -x \"$PY\" ]"
check "curl 可用"              "command -v curl"

echo ""
echo "[2/4] 安装介质"
check "Archboot ISO 已下载"    "[ -f \"$ISO\" ]"
if [ -f "$ISO" ]; then
    echo "       大小: $(ls -lh "$ISO" | awk '{print $5}')"
    ACTUAL=$(shasum -a 256 "$ISO" 2>/dev/null | awk '{print $1}')
    if [ "$ACTUAL" = "$EXPECT_SHA" ]; then
        ok "ISO SHA256 校验通过"
    else
        bad "ISO SHA256 不匹配（当前 $ACTUAL）"
    fi
fi

echo ""
echo "[3/4] 虚拟机状态"
if "$PRL" list -a 2>/dev/null | grep -q "$VM"; then
    ok "虚拟机 '$VM' 存在"
    STATE=$("$PRL" list -i "$VM" 2>/dev/null | grep -m1 '^State:' | awk '{print $2}')
    echo "       当前状态: ${STATE:-未知}"
    if "$PRL" list -i "$VM" 2>/dev/null | grep -q 'net0.*type=shared'; then
        ok "网卡类型为 shared（可上外网）"
    else
        bad "网卡类型不是 shared —— 会导致无外网，执行: prlctl set \"$VM\" --device-set net0 --type shared"
    fi
else
    bad "虚拟机 '$VM' 不存在"
fi

echo ""
echo "[4/4] 分发服务"
BOUND=$(lsof -nP -iTCP:$PORT -sTCP:LISTEN 2>/dev/null | grep -c LISTEN)
if [ "$BOUND" -gt 0 ]; then
    ok "端口 $PORT 已监听（$BOUND 个地址）"
    for ip in 10.211.55.2 10.37.129.2; do
        R=$(curl -s -m 3 "http://$ip:$PORT/ping" 2>/dev/null)
        if [ "$R" = "ok" ]; then ok "http://$ip:$PORT 响应正常"; else bad "http://$ip:$PORT 无响应"; fi
    done
    CODE=$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://10.211.55.2:$PORT/i" 2>/dev/null)
    if [ "$CODE" = "200" ]; then ok "install.sh 可下载 (HTTP $CODE)"; else bad "install.sh 下载异常 (HTTP $CODE)"; fi
else
    bad "端口 $PORT 未监听 —— 执行: cd arch-install && python3 serve.py"
fi

echo ""
echo "=============================================="
echo " 结果: 通过 $PASS 项, 失败 $FAIL 项"
echo "=============================================="
[ "$FAIL" -eq 0 ] && echo " 环境就绪 ✓" || echo " 存在未通过项，请按上方提示处理"
exit $FAIL
