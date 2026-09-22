#!/bin/bash
# ============================================================
# 虚拟机健康巡检（在 Arch Linux ARM 虚拟机内运行）
#
# 用法: bash vm-check.sh
#       MANIFEST=/path/to/dev-env.manifest bash vm-check.sh   # 指定环境清单
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

# ---------- 时钟 ----------
sec "时钟"
# 基准取 HTTP（而非 HTTPS）镜像站响应的 Date 头：时钟偏到证书有效期之外时，
# HTTPS 自身就会握手失败，拿它来校时钟会陷入循环依赖。
# 阈值与 diagnose.sh 的「宿主机↔虚拟机」偏差判定保持一致（60s 容忍网络抖动）。
CLK_HDR=$(curl -sI -m 8 http://mirror.archlinuxarm.org/ 2>/dev/null | tr -d '\r')
CLK_REF_TXT=$(printf '%s\n' "$CLK_HDR" | sed -n 's/^[Dd]ate:[[:space:]]*//p' | head -1)
CLK_REF=$(date -u -d "$CLK_REF_TXT" +%s 2>/dev/null)
CLK_NOW=$(date -u +%s)
if [ -z "$CLK_REF" ]; then
    kv "外部基准" "未取到可用时间源（镜像站无响应或 Date 头无法解析），跳过偏差判定"
else
    CLK_SKEW=$((CLK_NOW - CLK_REF))
    CLK_ABS=$CLK_SKEW
    [ "$CLK_ABS" -lt 0 ] && CLK_ABS=$(( -CLK_SKEW ))
    if [ "$CLK_SKEW" -ge 0 ]; then CLK_DIR="快"; else CLK_DIR="慢"; fi
    kv "本机 UTC"      "$(date -u '+%F %T')"
    kv "基准 UTC"      "$(date -u -d "@$CLK_REF" '+%F %T')"
    kv "偏差"          "${CLK_ABS}s（本机${CLK_DIR}）"
    if   [ "$CLK_ABS" -le 60 ];  then pass "时钟准确（偏差 ${CLK_ABS}s）"
    elif [ "$CLK_ABS" -le 600 ]; then warn "时钟偏差 ${CLK_ABS}s，可能影响证书与 pacman 签名校验"
    else fail "时钟偏差 ${CLK_ABS}s（本机${CLK_DIR}），TLS 与包签名校验大概率失败"; fi
    if [ "$CLK_ABS" -gt 60 ]; then
        kv "校正" "sudo hwclock --hctosys    # 从主板 RTC 回读，挂起导致的漂移这一步就能修"
        kv "兜底" "sudo timedatectl set-ntp true && sudo systemctl restart systemd-timesyncd"
    fi
fi
# 刻意不以 timedatectl 的 "System clock synchronized" 作判据：
# 实测虚拟机挂起/恢复后时钟停在挂起那一刻，该字段仍报 yes。
kv "NTP 服务" "$(timedatectl show -p NTP --value 2>/dev/null || echo 未知)"

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

# ---------- 开发环境清单完整度 ----------
# 清单格式与解析规则以 dev-env.manifest 头部为准，此处只读核对、不做任何修改。
# 找不到清单时不报失败：vm-check.sh 支持单文件拷进虚拟机使用，不应因此变红。
vc_pkgs() {
    awk -v want="$2" '
        /^\[/ { g=$0; sub(/^\[/,"",g); sub(/\].*$/,"",g); next }
        /^[[:space:]]*[#;]/ { next }
        /^@/ { next }
        g==want { for (i=1; i<=NF; i++) if ($i != "") print $i }
    ' "$1"
}
vc_has_group() {
    awk -v want="$2" '
        /^\[/ { g=$0; sub(/^\[/,"",g); sub(/\].*$/,"",g); if (g==want) { found=1; exit } }
        END { exit !found }
    ' "$1"
}

VC_MF="$MANIFEST"
if [ -z "$VC_MF" ]; then
    VC_D=$(dirname -- "$0")
    [ "$VC_D" = "$0" ] && VC_D="."
    for cand in "$VC_D/dev-env.manifest" "$HOME/dev-env.manifest" "/tmp/dev-env.manifest"; do
        if [ -f "$cand" ]; then VC_MF="$cand"; break; fi
    done
fi

if [ -n "$VC_MF" ] && [ -f "$VC_MF" ]; then
    VC_LANGS=$(awk '/^@default_langs/ { sub(/^@default_langs[[:space:]]*/,""); print; exit }' "$VC_MF")
    VC_GROUPS="base cli"
    for lg in $VC_LANGS; do
        vc_has_group "$VC_MF" "$lg" && VC_GROUPS="$VC_GROUPS $lg"
    done
    VC_TOTAL=0; VC_HAVE=0; VC_MISS=""
    for grp in $VC_GROUPS; do
        for p in $(vc_pkgs "$VC_MF" "$grp"); do
            VC_TOTAL=$((VC_TOTAL + 1))
            if pacman -Qi "$p" >/dev/null 2>&1; then
                VC_HAVE=$((VC_HAVE + 1))
            else
                VC_MISS="$VC_MISS $p"
            fi
        done
    done
    kv "环境清单" "$(basename "$VC_MF")（组: $(printf '%s' "$VC_GROUPS" | tr '\n' ' ')）"
    if [ "$VC_TOTAL" -gt 0 ]; then
        if [ "$VC_HAVE" -eq "$VC_TOTAL" ]; then
            pass "开发环境完整度 $VC_HAVE/$VC_TOTAL"
        else
            warn "开发环境完整度 $VC_HAVE/$VC_TOTAL，缺：${VC_MISS# }"
            kv "补齐方式" "bash dev-setup.sh"
        fi
    fi
else
    kv "环境清单" "未找到 dev-env.manifest —— 与 dev-setup.sh 一起拷贝后可核对完整度"
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
