#!/bin/bash
# ============================================================
# 故障自诊断（在宿主机 macOS 上运行）
#
# 逐条检测本项目实际踩过的坑，并给出可执行的修复建议。
# 用法: bash diagnose.sh [虚拟机名称]      # 默认 "Arch Linux"
# ============================================================

PRL="/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"
VM="${1:-Arch Linux}"
PORT_SERVE=8000
PORT_PROXY=8888
HOST_SHARED="10.211.55.2"
HOST_HOSTONLY="10.37.129.2"

if [ -t 1 ]; then
    G="\033[32m"; Y="\033[33m"; R="\033[31m"; B="\033[36m"; N="\033[0m"
else
    G=""; Y=""; R=""; B=""; N=""
fi
PASS=0; WARN=0; FAIL=0
pass() { printf '  %b[OK]%b   %s\n' "$G" "$N" "$1"; PASS=$((PASS + 1)); }

# 端口监听探测：优先 lsof（macOS 自带），缺失时回退 nc，
# 避免把「探测工具缺失」误判为「端口未监听」
port_listening() {
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
    elif command -v nc >/dev/null 2>&1; then
        nc -z -G 1 127.0.0.1 "$1" >/dev/null 2>&1
    else
        return 1
    fi
}
warn() { printf '  %b[WARN]%b %s\n' "$Y" "$N" "$1"; WARN=$((WARN + 1)); }
fail() { printf '  %b[FAIL]%b %s\n' "$R" "$N" "$1"; FAIL=$((FAIL + 1)); }
fix()  { printf '         修复: %s\n' "$1"; }
sec()  { printf '\n%b== %s ==%b\n' "$B" "$1" "$N"; }

echo "=============================================="
echo " 故障自诊断"
echo " 虚拟机: $VM"
echo " 时间:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ---------- 1. 宿主机工具 ----------
sec "宿主机工具"
if [ -x "$PRL" ]; then
    pass "prlctl 可用"
else
    fail "未找到 prlctl"
    fix "确认已安装 Parallels Desktop，路径: $PRL"
fi

# ---------- 2. 虚拟机存在性 ----------
sec "虚拟机"
if ! "$PRL" list -a 2>/dev/null | grep -qF "$VM"; then
    fail "虚拟机 '$VM' 不存在"
    fix "\"$PRL\" create \"$VM\" -d manjaro --dst \"\$HOME/Parallels\""
    echo ""
    echo "（虚拟机不存在，终止后续检查）"
    exit 1
fi
pass "虚拟机存在"
STATE=$("$PRL" list -i "$VM" 2>/dev/null | grep -m1 '^State:' | awk '{print $2}')
printf '         当前状态: %s\n' "${STATE:-未知}"

# ---------- 3. 网卡类型（本项目最大的坑） ----------
sec "网卡类型（关键）"
NETTYPE=$("$PRL" list -i "$VM" 2>/dev/null | grep -m1 'net0' | sed -n 's/.*type=\([a-z]*\).*/\1/p')
printf '         当前类型: %s\n' "${NETTYPE:-未知}"
if [ "$NETTYPE" = "shared" ]; then
    pass "网卡为 shared（可上外网）"
elif [ "$NETTYPE" = "host" ]; then
    fail "网卡为 host（Host-Only）—— 这类网络没有外网出口！"
    printf '         症状: 能访问宿主机服务，但所有镜像站都连不上\n'
    fix "\"$PRL\" set \"$VM\" --device-set net0 --type shared"
else
    fail "网卡类型异常: ${NETTYPE:-未知}"
    fix "\"$PRL\" set \"$VM\" --device-set net0 --type shared"
fi

# ---------- 4. 启动顺序 ----------
sec "启动顺序"
BOOTORDER=$("$PRL" list -i "$VM" 2>/dev/null | grep -m1 'Boot order' | sed 's/.*Boot order: *//')
printf '         当前顺序: %s\n' "${BOOTORDER:-未知}"
case "$BOOTORDER" in
    "hdd0 cdrom0 usb"*) pass "硬盘优先（已装完系统的正常状态）" ;;
    "cdrom0 hdd0 usb"*) warn "光盘优先（安装期状态；若系统已装完，重启会再次进入 live 环境）"
                        fix "\"$PRL\" set \"$VM\" --device-bootorder \"hdd0 cdrom0 usb\"" ;;
    *) warn "非标准启动顺序: ${BOOTORDER:-未知}" ;;
esac

# ---------- 5. 安装镜像 ----------
sec "安装镜像"
ISO_FOUND=$(ls -t "$HOME/Downloads"/archboot-*-aarch64-ARCH-aarch64.iso 2>/dev/null | head -1)
if [ -n "$ISO_FOUND" ]; then
    pass "ISO 存在: $(basename "$ISO_FOUND")"
    printf '         大小: %s\n' "$(ls -lh "$ISO_FOUND" | awk '{print $5}')"
    ACTUAL=$(shasum -a 256 "$ISO_FOUND" 2>/dev/null | awk '{print $1}')
    printf '         SHA256: %s\n' "$ACTUAL"
else
    warn "未在 ~/Downloads 找到 Archboot ISO"
    fix "curl -fL -o \"\$HOME/Downloads/archboot-<日期>-aarch64-ARCH-aarch64.iso\" https://release.archboot.com/aarch64/latest/iso/<文件名>"
fi

# ---------- 6. 分发服务 ----------
sec "分发服务（安装期需要）"
if port_listening "$PORT_SERVE"; then
    pass "端口 $PORT_SERVE 已监听"
    for ip in "$HOST_SHARED" "$HOST_HOSTONLY"; do
        if [ "$(curl -s -m 3 "http://$ip:$PORT_SERVE/ping" 2>/dev/null)" = "ok" ]; then
            pass "http://$ip:$PORT_SERVE 响应正常"
        else
            warn "http://$ip:$PORT_SERVE 无响应"
        fi
    done
else
    warn "端口 $PORT_SERVE 未监听（系统装完后不再需要，可忽略）"
    fix "cd arch-install && python3 serve.py"
fi

# ---------- 7. 代理转发（GitHub 访问） ----------
sec "代理转发（GitHub 加速）"
if port_listening "$PORT_PROXY"; then
    pass "端口 $PORT_PROXY 已监听"
    printf '         说明: 宿主机自身走独立代理，实际效果须在虚拟机内验证（见下）\n'
else
    warn "端口 $PORT_PROXY 未监听（虚拟机将无法访问被宿主机屏蔽的站点）"
    fix "cd arch-install && python3 proxy-forward.py"
fi

# ---------- 8. 虚拟机网络可达性 ----------
sec "虚拟机网络"
VMIP=""
for cand in $(arp -an 2>/dev/null | grep -oE '10\.(211\.55|37\.129)\.[0-9]+' | sort -u); do
    if nc -z -G 2 "$cand" 22 >/dev/null 2>&1; then VMIP="$cand"; break; fi
done
if [ -n "$VMIP" ]; then
    pass "SSH 可达: $VMIP"
else
    warn "未探测到开放的 SSH 端口（系统未装完或 sshd 未启用）"
    fix "在虚拟机内执行: sudo pacman -S openssh && sudo systemctl enable --now sshd"
fi

# ---------- 9. 虚拟机内部状态（若可 SSH） ----------
if [ -n "$VMIP" ]; then
    sec "虚拟机内部状态"
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           -o BatchMode=yes -o ConnectTimeout=8 "arch@$VMIP" true 2>/dev/null; then
        pass "SSH 公钥登录可用"
        INFO=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
               "arch@$VMIP" 'uname -m; df / | tail -1 | awk "{print \$5}"; systemctl is-active NetworkManager; systemctl is-active prltoolsd 2>/dev/null || echo inactive' 2>/dev/null)
        ARCH_VM=$(echo "$INFO" | sed -n 1p)
        USE_VM=$(echo "$INFO" | sed -n 2p)
        NM_VM=$(echo "$INFO" | sed -n 3p)
        PRL_VM=$(echo "$INFO" | sed -n 4p)
        [ "$ARCH_VM" = "aarch64" ] && pass "虚拟机架构正确" || warn "虚拟机架构异常: $ARCH_VM"
        printf '         根分区使用率: %s\n' "${USE_VM:-未知}"
        [ "$NM_VM" = "active" ] && pass "NetworkManager 运行中" || fail "NetworkManager 未运行"
        if [ "$PRL_VM" = "active" ]; then
            pass "Parallels Tools 运行中"
        else
            warn "Parallels Tools 未运行（剪贴板与共享文件夹不可用）"
        fi
        PSF_N=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
                 "arch@$VMIP" 'ls /mnt/psf 2>/dev/null | wc -l' 2>/dev/null | tr -d ' ')
        if [ "${PSF_N:-0}" -gt 0 ]; then
            pass "共享文件夹已挂载（$PSF_N 个）"
        else
            warn "共享文件夹为空（检查 Parallels 的 配置 → 共享 → 共享文件夹）"
            fix "在 Parallels 界面为 '$VM' 添加共享文件夹（CLI 仅支持总开关，具体目录需图形界面配置）"
        fi
        if port_listening "$PORT_PROXY"; then
            GH_CODE=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
                      "arch@$VMIP" "curl -s -m 12 -x http://$HOST_SHARED:$PORT_PROXY -o /dev/null -w '%{http_code}' https://github.com" 2>/dev/null | tr -d ' ')
            if [ "$GH_CODE" = "200" ]; then
                pass "虚拟机经代理访问 GitHub 正常"
            else
                warn "虚拟机经代理访问 GitHub 返回 ${GH_CODE:-无响应}"
                fix "确认宿主机加速工具在运行，且其根证书已导入虚拟机信任链"
            fi
        fi
        printf '         提示: 更完整的巡检请在虚拟机内运行 vm-check.sh\n'
    else
        warn "SSH 公钥登录不可用（密码可能已修改或公钥未安装）"
        fix "虚拟机内执行: mkdir -p ~/.ssh;chmod 700 ~/.ssh;curl -s http://$HOST_SHARED:$PORT_SERVE/k>>~/.ssh/authorized_keys;chmod 600 ~/.ssh/authorized_keys"
    fi
fi

# ---------- 汇总 ----------
echo ""
echo "=============================================="
printf ' 结果: %b%d 通过%b ｜ %b%d 警告%b ｜ %b%d 失败%b\n' \
    "$G" "$PASS" "$N" "$Y" "$WARN" "$N" "$R" "$FAIL" "$N"
echo "=============================================="
if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    echo " 一切正常"
elif [ "$FAIL" -eq 0 ]; then
    echo " 无致命问题，请留意上方警告项"
else
    echo " 存在失败项，请按上方修复建议处理"
fi
exit "$FAIL"
