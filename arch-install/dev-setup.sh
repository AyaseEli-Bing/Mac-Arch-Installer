#!/bin/bash
# ============================================================
# 开发环境一键配置与核对（在 Arch Linux ARM 虚拟机内运行）
#
# 用法：
#   bash dev-setup.sh                  # 补齐：装到清单要求的状态（默认）
#   bash dev-setup.sh check            # 核对：只报缺什么，不装、不用 sudo
#   bash dev-setup.sh export > my.txt  # 导出：把当前环境写成清单
#
#   LANGS="go python" bash dev-setup.sh   # 只管指定语言组
#   INSTALL_CLI=no    bash dev-setup.sh   # 跳过常用 CLI 工具
#   USE_CN_MIRROR=no  bash dev-setup.sh   # 不配置国内镜像
#   MANIFEST=/path/to/dev-env.manifest bash dev-setup.sh check
#
# 可选语言组：go python node rust cpp java
# 包清单来自 dev-env.manifest（单一事实源，vm-check.sh 读同一份）
# ============================================================
set -o pipefail

MODE="${1:-apply}"
# 默认语言组不写死在此处，改从清单的 @default_langs 读取（见 dev-env.manifest）
LANGS="${LANGS:-}"
INSTALL_CLI="${INSTALL_CLI:-yes}"
USE_CN_MIRROR="${USE_CN_MIRROR:-yes}"

G="\033[32m"; Y="\033[33m"; R="\033[31m"; B="\033[36m"; N="\033[0m"
ok()   { printf '%b[OK]%b   %s\n' "$G" "$N" "$1"; }
info() { printf '       %s\n' "$1"; }
warn() { printf '%b[WARN]%b %s\n' "$Y" "$N" "$1"; }
err()  { printf '%b[FAIL]%b %s\n' "$R" "$N" "$1"; }
sec()  { printf '\n%b== %s ==%b\n' "$B" "$1" "$N"; }

# ---------- 参数校验 ----------
case "$MODE" in
    apply|check|export) ;;
    -h|--help|help)
        sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        err "未知模式 '$MODE'（可选 apply | check | export）"
        exit 2
        ;;
esac

# ---------- 前置检查 ----------
if [ "$(id -u)" -eq 0 ]; then
    err "请以普通用户运行（脚本内部会调用 sudo），不要直接用 root"
    exit 1
fi
if ! command -v pacman >/dev/null 2>&1; then
    err "未检测到 pacman —— 本脚本仅适用于 Arch Linux"
    exit 1
fi

# ---------- 定位清单 ----------
MF_DIR=$(dirname -- "$0")
[ "$MF_DIR" = "$0" ] && MF_DIR="."
MANIFEST="${MANIFEST:-$MF_DIR/dev-env.manifest}"
if [ ! -f "$MANIFEST" ]; then
    err "找不到包清单 $MANIFEST"
    info "本脚本不内嵌包清单，以免出现两份互相矛盾的列表。"
    info "修复：把清单与脚本一起拷贝过去 ——"
    info "  scp arch-install/dev-setup.sh arch-install/dev-env.manifest arch@<虚拟机IP>:/tmp/"
    exit 1
fi

# ---------- 清单解析 ----------
# 语法见 dev-env.manifest 头部：[组名] 分段，段内空格或换行分隔包名，# 为注释
mf_groups() {
    awk '/^\[/ { g=$0; sub(/^\[/,"",g); sub(/\].*$/,"",g); print g }' "$1"
}
mf_pkgs() {
    awk -v want="$2" '
        /^\[/ { g=$0; sub(/^\[/,"",g); sub(/\].*$/,"",g); next }
        /^[[:space:]]*[#;]/ { next }
        /^@/ { next }
        g==want { for (i=1; i<=NF; i++) if ($i != "") print $i }
    ' "$1"
}
mf_default_langs() {
    awk '/^@default_langs/ { sub(/^@default_langs[[:space:]]*/,""); print; exit }' "$1"
}

# LANGS 未显式指定时采用清单默认值
if [ -z "$LANGS" ]; then
    LANGS=$(mf_default_langs "$MANIFEST")
    if [ -z "$LANGS" ]; then
        warn "清单缺少 @default_langs 指令，本次只核对 base 与 cli 组"
    fi
fi

# 本次要管的组：base +（可选 cli）+ LANGS 指定的语言组
# 注意不要命名为 GROUPS —— 那是 bash 的特殊数组变量
# mf_groups 按行输出，这里必须转成空格分隔：case 的 *" $lg "* 模式匹配的是空格，
# 留换行会导致所有语言组都被误判成「清单里没有」。
AVAIL_GROUPS=$(mf_groups "$MANIFEST" | tr '\n' ' ')
WANT_GROUPS="base"
[ "$INSTALL_CLI" = "yes" ] && WANT_GROUPS="$WANT_GROUPS cli"
for lg in $LANGS; do
    case " $AVAIL_GROUPS " in
        *" $lg "*) WANT_GROUPS="$WANT_GROUPS $lg" ;;
        *) warn "清单里没有语言组 '$lg'，已跳过（清单提供: $AVAIL_GROUPS）" ;;
    esac
done

# ---------- 三态判定 ----------
# installed = 已装；missing = 未装且仓库里有；unknown = 仓库里查不到。
# 第三态正是最容易被误报成「镜像挂了」的那类：例如 shellcheck 在 Arch Linux ARM
# 仓库中根本不构建，装它必然失败，与网络毫无关系。
classify() {
    if pacman -Qi "$1" >/dev/null 2>&1; then
        echo installed
    elif pacman -Si "$1" >/dev/null 2>&1; then
        echo missing
    else
        echo unknown
    fi
}

# ---------- export：把当前环境写成清单 ----------
if [ "$MODE" = "export" ]; then
    printf '# 由 dev-setup.sh export 生成于 %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '# 主机: %s ｜ 架构: %s ｜ 仅列出清单关注的组中已安装的包\n' "$(hostname)" "$(uname -m)"
    printf '# 语法同 dev-env.manifest\n\n'
    for grp in $WANT_GROUPS; do
        printf '[%s]\n' "$grp"
        line=""
        for p in $(mf_pkgs "$MANIFEST" "$grp"); do
            pacman -Qi "$p" >/dev/null 2>&1 && line="$line $p"
        done
        printf '%s\n\n' "${line# }"
    done
    exit 0
fi

# ---------- check / apply 共用的差异计算 ----------
TOTAL=0
HAVE=0
N_MISS=0
N_UNK=0
TO_INSTALL=""
UNKNOWN_LIST=""

sec "核对清单（$MANIFEST）"
for grp in $WANT_GROUPS; do
    g_total=0
    g_have=0
    g_miss=""
    g_unk=""
    for p in $(mf_pkgs "$MANIFEST" "$grp"); do
        g_total=$((g_total + 1))
        case "$(classify "$p")" in
            installed) g_have=$((g_have + 1)) ;;
            missing)   g_miss="$g_miss $p" ;;
            unknown)   g_unk="$g_unk $p" ;;
        esac
    done
    TOTAL=$((TOTAL + g_total))
    HAVE=$((HAVE + g_have))
    if [ -n "$g_miss" ]; then
        g_n=0
        for _ in $g_miss; do g_n=$((g_n + 1)); done
        printf '  [%-7s] 缺 %d 个：%s\n' "$grp" "$g_n" "${g_miss# }"
        TO_INSTALL="$TO_INSTALL$g_miss "
    elif [ "$g_total" -gt 0 ]; then
        printf '  [%-7s] 已齐 %d/%d\n' "$grp" "$g_have" "$g_total"
    fi
    [ -n "$g_unk" ] && UNKNOWN_LIST="$UNKNOWN_LIST$g_unk "
done

# 三类计数必须分开：TOTAL-HAVE 会把「仓库里不存在、压根装不上」的包也算成「缺」，
# 从而出现「缺 1 个」与「已全部安装」同时打印的自相矛盾结论。
N_MISS=0
for _ in $TO_INSTALL; do N_MISS=$((N_MISS + 1)); done
N_UNK=0
for _ in $UNKNOWN_LIST; do N_UNK=$((N_UNK + 1)); done

if [ -n "$UNKNOWN_LIST" ]; then
    warn "以下包在同步数据库里查不到，装也不会成功：${UNKNOWN_LIST}"
    info "常见原因 ① 该架构仓库未构建此包（如 shellcheck 不在 Arch ARM 仓库）"
    info "          ② 数据库过旧，先执行 sudo pacman -Sy"
    info "          ③ 包名已变更，用 pacman -Ss 关键字 确认"
fi

# 统一的环境结论（check 与 apply 共用，避免两处措辞分叉）
verdict() {
    printf '  清单要求 %d 个 ｜ 已装 %d ｜ 待装 %d ｜ 仓库无此包 %d\n' \
        "$TOTAL" "$HAVE" "$N_MISS" "$N_UNK"
    if [ "$N_MISS" -eq 0 ] && [ "$N_UNK" -eq 0 ]; then
        ok "环境完全符合清单"
    elif [ "$N_MISS" -eq 0 ]; then
        warn "可安装的包均已就位；另有 $N_UNK 个包在当前仓库中不存在，装不上"
    else
        printf '  %b[待办]%b 还需安装 %d 个包\n' "$Y" "$N" "$N_MISS"
    fi
}

if [ "$MODE" = "check" ]; then
    sec "核对结果"
    verdict
    if [ "$N_MISS" -gt 0 ]; then
        info "本模式不安装任何东西。补齐请执行：bash $0 apply"
    fi
    exit 0
fi

# ---------- apply：只装真正缺的，失败时给出真实原因 ----------
sec "补齐安装"
if [ -z "$TO_INSTALL" ]; then
    ok "清单要求的包已全部安装"
else
    PLOG=$(mktemp)
    # 保留输出而非 >/dev/null 丢弃：失败时必须能区分「包不存在」「镜像不可达」
    # 「密钥环校验失败」三类，此前它们都塌成同一句「安装有告警」。
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm $TO_INSTALL 2>&1 | tee "$PLOG" >/dev/null
    RC=${PIPESTATUS[0]}
    if [ "$RC" -eq 0 ]; then
        ok "已安装：${TO_INSTALL}"
    else
        err "pacman 退出码 $RC，正在判读原因："
        NF=$(sed -n 's/.*target not found: *//p' "$PLOG" | tr '\n' ' ')
        if [ -n "$NF" ]; then
            printf '  %b[仓库]%b 这些包在仓库中不存在，本次不会被装上：%s\n' "$R" "$N" "$NF"
        fi
        if grep -qiE 'could not resolve host|connection refused|failed to download|curl error|operation timed out' "$PLOG"; then
            printf '  %b[镜像]%b 镜像站不可达。确认网络后重试；网卡须为 shared 而非 host-only。\n' "$R" "$N"
        fi
        if grep -qiE 'signature|keyring|invalid or corrupted' "$PLOG"; then
            printf '  %b[密钥]%b 签名或密钥环校验失败。可尝试：sudo pacman-key --refresh-keys\n' "$R" "$N"
        fi
        if grep -qiE 'no space left' "$PLOG"; then
            printf '  %b[磁盘]%b 空间不足。可先清理缓存：sudo paccache -rk1\n' "$R" "$N"
        fi
        info "原始输出末 6 行："
        tail -6 "$PLOG" | sed 's/^/       /'
    fi
    rm -f "$PLOG"
fi

# ---------- 语言生态镜像源 ----------
sec "语言生态镜像源"
if [ "$USE_CN_MIRROR" = "yes" ]; then
    if command -v go >/dev/null 2>&1; then
        go env -w GOPROXY=https://goproxy.cn,direct
        # 官方 sum.golang.org 在国内常被墙：即便 GOPROXY 配好，模块校验仍会超时失败。
        # 指向 gosum.io 并经 goproxy.cn 代理 sumdb 可避免这一情况。
        go env -w GOSUMDB=gosum.io+https://goproxy.cn/sumdb/sum.golang.org
        ok "Go    → goproxy.cn（含 sumdb 代理）"
    fi
    if command -v npm >/dev/null 2>&1; then
        npm config set registry https://registry.npmmirror.com >/dev/null 2>&1
        ok "npm   → registry.npmmirror.com"
    fi
    if command -v python >/dev/null 2>&1; then
        mkdir -p ~/.config/pip
        printf "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple\ntrusted-host = pypi.tuna.tsinghua.edu.cn\n" > ~/.config/pip/pip.conf
        ok "pip   → 清华 TUNA"
    fi
    if command -v cargo >/dev/null 2>&1; then
        mkdir -p ~/.cargo
        printf "[source.crates-io]\nreplace-with = \"ustc\"\n\n[source.ustc]\nregistry = \"sparse+https://mirrors.ustc.edu.cn/crates.io-index/\"\n" > ~/.cargo/config.toml
        ok "Cargo → USTC 索引"
    fi
else
    info "已按配置跳过镜像源设置"
fi

# ---------- 汇总 ----------
sec "工具版本"
for c in go python node npm rustc cargo clang gcc cmake ninja gdb git rg fd bat htop tmux jq; do
    if command -v "$c" >/dev/null 2>&1; then
        v=$("$c" --version 2>/dev/null | head -1 | tr -d '\n')
        printf '  %-7s %s\n' "$c" "${v:0:58}"
    fi
done

# ---------- 安装后复核 ----------
# 必须重新统计：前面的 HAVE 是「安装前」的快照，拿它汇报会虚报进度。
sec "安装后复核"
AFTER_TOTAL=0
AFTER_HAVE=0
for grp in $WANT_GROUPS; do
    for p in $(mf_pkgs "$MANIFEST" "$grp"); do
        AFTER_TOTAL=$((AFTER_TOTAL + 1))
        pacman -Qi "$p" >/dev/null 2>&1 && AFTER_HAVE=$((AFTER_HAVE + 1))
    done
done
printf '  环境完整度 %d/%d\n' "$AFTER_HAVE" "$AFTER_TOTAL"
if [ "$AFTER_HAVE" -eq "$AFTER_TOTAL" ]; then
    ok "全部就位"
else
    warn "仍有 $((AFTER_TOTAL - AFTER_HAVE)) 个包未安装，可执行 bash $0 check 查看具体缺哪些"
fi
if [ "$N_UNK" -gt 0 ]; then
    info "注：清单中有 $N_UNK 个包在当前仓库不存在，未计入上面的分母差异（见上方 WARN）"
fi
info "镜像源配置对新开的终端会话生效。"
