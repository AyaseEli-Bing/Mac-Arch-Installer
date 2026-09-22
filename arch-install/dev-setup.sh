#!/bin/bash
# ============================================================
# 开发环境一键配置（在 Arch Linux ARM 虚拟机内运行）
#
# 用法：
#   bash dev-setup.sh                    # 默认语言组合 + 国内镜像源
#   LANGS="go python" bash dev-setup.sh  # 只装指定语言
#   INSTALL_CLI=no bash dev-setup.sh     # 跳过常用 CLI 工具
#   USE_CN_MIRROR=no bash dev-setup.sh   # 不配置国内镜像
#
# 可选语言: go python node rust cpp java
# ============================================================
set -o pipefail

LANGS="${LANGS:-go python node rust}"
INSTALL_CLI="${INSTALL_CLI:-yes}"
USE_CN_MIRROR="${USE_CN_MIRROR:-yes}"

G="\033[32m"; Y="\033[33m"; R="\033[31m"; N="\033[0m"
ok()   { printf '%b[OK]%b   %s\n' "$G" "$N" "$1"; }
info() { printf '       %s\n' "$1"; }
warn() { printf '%b[WARN]%b %s\n' "$Y" "$N" "$1"; }
err()  { printf '%b[FAIL]%b %s\n' "$R" "$N" "$1"; }

# ---------- 前置检查 ----------
if [ "$(id -u)" -eq 0 ]; then
    err "请以普通用户运行（脚本内部会调用 sudo），不要直接用 root"
    exit 1
fi
if ! command -v pacman >/dev/null 2>&1; then
    err "未检测到 pacman —— 本脚本仅适用于 Arch Linux"
    exit 1
fi

echo "=============================================="
echo " 开发环境一键配置"
echo " 语言: $LANGS"
echo " CLI 工具: $INSTALL_CLI ｜ 国内镜像: $USE_CN_MIRROR"
echo "=============================================="

# ---------- 1. 基础工具 ----------
echo ""
echo "[1/3] 基础工具"
BASE="git curl wget unzip which inetutils base-devel"
# shellcheck disable=SC2086
if sudo pacman -S --needed --noconfirm $BASE >/dev/null 2>&1; then
    ok "基础工具就绪"
else
    warn "基础工具安装有告警，请检查网络或镜像源"
fi

if [ "$INSTALL_CLI" = "yes" ]; then
    CLI="ripgrep fd bat htop tmux jq tree less"
    # shellcheck disable=SC2086
    if sudo pacman -S --needed --noconfirm $CLI >/dev/null 2>&1; then
        ok "常用 CLI 工具就绪"
    else
        warn "CLI 工具安装有告警"
    fi
fi

# ---------- 2. 语言工具链 ----------
echo ""
echo "[2/3] 语言工具链"
PKGS=""
for lang in $LANGS; do
    case "$lang" in
        go)     PKGS="$PKGS go" ;;
        python) PKGS="$PKGS python python-pip python-virtualenv" ;;
        node)   PKGS="$PKGS nodejs npm" ;;
        rust)   PKGS="$PKGS rust" ;;
        cpp)    PKGS="$PKGS cmake ninja clang gdb" ;;
        java)   PKGS="$PKGS jdk-openjdk" ;;
        *)      warn "未知语言 $lang（可选: go python node rust cpp java）" ;;
    esac
done
if [ -n "$PKGS" ]; then
    # shellcheck disable=SC2086
    if sudo pacman -S --needed --noconfirm $PKGS >/dev/null 2>&1; then
        ok "语言工具链安装完成"
    else
        err "语言工具链安装失败，请检查网络或镜像源"
    fi
fi

# ---------- 3. 镜像源 ----------
echo ""
echo "[3/3] 包管理镜像源"
if [ "$USE_CN_MIRROR" = "yes" ]; then
    if command -v go >/dev/null 2>&1; then
        go env -w GOPROXY=https://goproxy.cn,direct
        # 官方 sum.golang.org 在国内常被墙：即便镜像配好，模块校验仍会超时失败。
        # 指向 gosum.io 并通过 goproxy.cn 代理 sumdb 可避免这一情况。
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
echo ""
echo "=============================================="
echo " 工具版本"
echo "=============================================="
for c in go python node npm rustc cargo clang gcc cmake ninja gdb git rg fd bat htop tmux jq; do
    if command -v "$c" >/dev/null 2>&1; then
        v=$("$c" --version 2>/dev/null | head -1 | tr -d '\n')
        printf '  %-7s %s\n' "$c" "${v:0:58}"
    fi
done

echo ""
echo "完成。提示：镜像源配置对新开的终端会话生效。"
