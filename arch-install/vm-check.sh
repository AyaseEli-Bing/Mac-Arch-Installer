#!/bin/bash
# ============================================================
# 虚拟机健康巡检（在 Arch Linux ARM 虚拟机内运行）
#
# 用法: bash vm-check.sh
# 特点: 只读检查，不做任何修改；无需 sudo；退出码 = FAIL 项数量
# ============================================================

if [ -t 1 ]; then
    G="\033[32m"; Y="\033[33m"; R="\033[31m"; B="\033[36m"; N="\033[0m"
else
    G=""; Y=""; R=""; B=""; N=""
fi
PASS=0; WARN=0; FAIL=0
pass() { printf '  %b[OK]%b   %s\n' "$G" "$N" "$1"; PASS=$((PASS + 1)); }
warn() { printf '  %b[WARN]%b %s\n' "$Y" "$N" "$1"; WARN=$((WARN + 1)); }
fail() { printf '  %b[FAIL]%b %s\n' "$R" "$N" "$1"; FAIL=$((FAIL + 1)); }
sec()  { printf '\n%b== %s ==%b\n' "$B" "$1" "$N"; }
kv()   { printf '         %-20s %s\n' "$1" "$2"; }

echo "=============================================="
echo " 虚拟机健康巡检"
echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ---------- 系统 ----------
sec "系统"
kv "架构"     "$(uname -m)"
kv "内核"     "$(uname -r)"
kv "主机名"   "$(cat /etc/hostname 2>/dev/null)"
kv "运行时长" "$(uptime -p 2>/dev/null | sed 's/^up //')"
[ "$(uname -m)" = "aarch64" ] && pass "架构正确（aarch64）" || fail "架构不是 aarch64"

# ---------- 磁盘 ----------
sec "磁盘"
ROOT_USE=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
ROOT_AVAIL=$(df -h / 2>/dev/null | tail -1 | awk '{print $4}')
kv "根分区可用" "$ROOT_AVAIL（已用 ${ROOT_USE}%）"
if [ "${ROOT_USE:-100}" -lt 80 ]; then
    pass "根分区空间充足"
elif [ "${ROOT_USE:-100}" -lt 90 ]; then
    warn "根分区使用率偏高（${ROOT_USE}%）"
else
    fail "根分区空间紧张（${ROOT_USE}%），建议清理缓存"
fi
if df -h /boot >/dev/null 2>&1; then
    kv "EFI 分区可用" "$(df -h /boot 2>/dev/null | tail -1 | awk '{print $4}')"
fi

# ---------- 服务 ----------
sec "关键服务"
for s in NetworkManager sshd; do
    if systemctl is-active --quiet "$s" 2>/dev/null; then
        pass "$s 运行中"
    else
        fail "$s 未运行"
    fi
done
DM=""
for d in sddm gdm lightdm; do
    if systemctl is-active --quiet "$d" 2>/dev/null; then DM="$d"; break; fi
done
if [ -n "$DM" ]; then
    pass "显示管理器运行中（$DM）"
else
    warn "未检测到显示管理器（纯命令行安装属正常）"
fi
if systemctl is-active --quiet prltoolsd 2>/dev/null; then
    pass "Parallels Tools 运行中"
else
    warn "Parallels Tools 未运行（剪贴板共享与共享文件夹不可用）"
fi
FAILED_UNITS=$(systemctl --failed --no-legend 2>/dev/null | wc -l | tr -d ' ')
if [ "${FAILED_UNITS:-0}" -eq 0 ]; then
    pass "无失败的服务单元"
else
    warn "存在 $FAILED_UNITS 个失败的服务单元（查看: systemctl --failed）"
fi

# ---------- 网络 ----------
sec "网络"
IPADDR=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | head -1)
kv "本机地址" "${IPADDR:-未获取}"
[ -n "$IPADDR" ] && pass "已获取 IPv4 地址" || fail "未获取到 IPv4 地址"
if getent hosts archlinux.org >/dev/null 2>&1; then
    pass "DNS 解析正常"
else
    warn "DNS 解析失败（检查 /etc/resolv.conf）"
fi
if ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1; then
    pass "外网连通（ICMP）"
else
    warn "外网 ICMP 不通（可能被策略拦截，不代表一定故障）"
fi
if [ -n "$http_proxy" ]; then
    kv "HTTP 代理" "$http_proxy"
    pass "代理已配置"
else
    kv "HTTP 代理" "未设置"
fi

# ---------- 桌面与输入法 ----------
sec "桌面与输入法"
if pgrep -x plasmashell >/dev/null 2>&1; then
    pass "KDE Plasma 运行中"
elif pgrep -x gnome-shell >/dev/null 2>&1; then
    pass "GNOME 运行中"
elif pgrep -x xfce4-session >/dev/null 2>&1; then
    pass "XFCE 运行中"
else
    warn "未检测到桌面进程（可能尚未登录图形会话）"
fi
if pgrep -x fcitx5 >/dev/null 2>&1; then
    pass "fcitx5 输入法运行中"
else
    warn "fcitx5 未运行（纯命令行安装可忽略）"
fi
CJK_N=$(fc-list 2>/dev/null | grep -ci cjk)
if [ "${CJK_N:-0}" -gt 0 ]; then
    pass "中文字体已安装（$CJK_N 条）"
else
    warn "未检测到中文字体（中文会显示为方块）"
fi

# ---------- Parallels 集成 ----------
sec "Parallels 集成"
NPSF=$(ls /mnt/psf 2>/dev/null | wc -l | tr -d ' ')
if [ "${NPSF:-0}" -gt 0 ]; then
    pass "共享文件夹已挂载（$NPSF 个）"
    ls /mnt/psf 2>/dev/null | head -5 | sed 's/^/         - /'
else
    warn "无共享文件夹（需安装 Parallels Tools 并在宿主机配置）"
fi

# ---------- 软件包 ----------
sec "软件包"
kv "已安装包数" "$(pacman -Q 2>/dev/null | wc -l | tr -d ' ')"
if command -v checkupdates >/dev/null 2>&1; then
    UPD_N=$(checkupdates 2>/dev/null | wc -l | tr -d ' ')
    if [ "${UPD_N:-0}" -eq 0 ]; then
        pass "系统已是最新"
    else
        warn "有 $UPD_N 个待更新包（sudo pacman -Syu）"
    fi
else
    kv "更新检查" "checkupdates 未安装（属于 pacman-contrib 包）"
fi

# ---------- 汇总 ----------
echo ""
echo "=============================================="
printf ' 结果: %b%d 通过%b ｜ %b%d 警告%b ｜ %b%d 失败%b\n' \
    "$G" "$PASS" "$N" "$Y" "$WARN" "$N" "$R" "$FAIL" "$N"
echo "=============================================="
if [ "$FAIL" -eq 0 ]; then
    echo " 系统健康"
else
    echo " 存在失败项，请按上方提示排查"
fi
exit "$FAIL"
