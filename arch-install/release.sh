#!/bin/bash
# ============================================================
# 自动发版（在宿主机 macOS 上运行，需在项目根目录执行）
#
# 用法:
#   bash arch-install/release.sh 1.2.0              # 自动生成发布说明
#   bash arch-install/release.sh 1.2.0 notes.md     # 使用指定说明文件
#
# 可选覆盖（网络不稳的环境有用）:
#   RETRY_MAX=8 RETRY_WAIT=10 bash arch-install/release.sh 1.2.0
#
# 流程: 前置检查 → 语法校验 → 打 tag → 打包 → 推送 → 建 Release → 验证
# ============================================================
set -o pipefail

VERSION="$1"
NOTES_IN="$2"
GH="${GH:-/opt/homebrew/bin/gh}"
REPO_SLUG="${REPO_SLUG:-AyaseEli-Bing/Mac-Arch-Installer}"
PKG_NAME="Mac-Arch-Installer"

G="\033[32m"; Y="\033[33m"; R="\033[31m"; B="\033[36m"; N="\033[0m"
ok()   { printf '  %b[OK]%b   %s\n' "$G" "$N" "$1"; }
warn() { printf '  %b[WARN]%b %s\n' "$Y" "$N" "$1"; }
err()  { printf '  %b[FAIL]%b %s\n' "$R" "$N" "$1"; }
step() { printf '\n%b== %s ==%b\n' "$B" "$1" "$N"; }
die()  { err "$1"; exit 1; }

# ---------- 网络动作统一入口 ----------
# 推送与建 Release 的动作此前都是 >/dev/null 2>&1 一把梭且无重试：失败时只剩一句
# 自拟结论，真实原因（代理抖动、DNS、鉴权）全被吞掉。实测在 fake-IP 代理间歇断连时
# 会让发版中途随机失败且无从排查。这里统一带重试，并在最终失败时打印真实报错。
RETRY_MAX="${RETRY_MAX:-5}"
RETRY_WAIT="${RETRY_WAIT:-6}"
run_net() {
    local _out _rc _i _first
    _rc=1
    for _i in $(seq 1 "$RETRY_MAX"); do
        _out=$("$@" 2>&1)
        _rc=$?
        if [ "$_rc" -eq 0 ]; then
            return 0
        fi
        if [ "$_i" -lt "$RETRY_MAX" ]; then
            _first=$(printf '%s' "$_out" | head -1)
            if [ -n "$_first" ]; then
                warn "第 $_i/$RETRY_MAX 次失败（rc=$_rc）：$_first"
            else
                warn "第 $_i/$RETRY_MAX 次失败（rc=$_rc，无输出）"
            fi
            warn "${RETRY_WAIT}s 后重试…"
            sleep "$RETRY_WAIT"
        fi
    done
    err "重试 $RETRY_MAX 次仍失败，真实报错如下："
    printf '%s\n' "$_out" | sed 's/^/         /' | head -8
    return "$_rc"
}

# ---------- 参数校验 ----------
if [ -z "$VERSION" ]; then
    echo "用法: bash $0 <版本号> [发布说明文件]"
    echo "示例: bash $0 1.2.0"
    exit 1
fi
if ! printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    die "版本号格式不正确（应遵循语义化版本，如 1.2.0）：$VERSION"
fi
TAG="v$VERSION"

echo "=============================================="
echo " 自动发版"
echo " 版本: $TAG"
echo " 仓库: $REPO_SLUG"
echo "=============================================="

# ---------- 1. 前置检查 ----------
step "1/6 前置检查"
[ -d .git ] || die "当前目录不是 Git 仓库，请在项目根目录执行"
ok "位于 Git 仓库中"

[ -x "$GH" ] || die "未找到 gh CLI: $GH"
"$GH" auth status >/dev/null 2>&1 || die "gh CLI 未登录，请先执行: $GH auth login"
ok "gh CLI 已认证"

CUR_BRANCH=$(git branch --show-current)
if [ "$CUR_BRANCH" != "main" ]; then
    warn "当前分支为 $CUR_BRANCH（通常应在 main 上发版）"
else
    ok "当前分支: main"
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
    die "标签 $TAG 已存在（已发布的标签不应移动，请改用新版本号）"
fi
ok "标签 $TAG 未被占用"

if [ -n "$(git status --porcelain)" ]; then
    warn "工作区有未提交的变更"
    git status --short | sed 's/^/         /'
    printf '         注意：打包使用 git archive HEAD，只包含【已提交】内容，\n'
    printf '               未提交的改动不会进入发布包。\n'
    printf '         是否继续？[y/N] '
    read -r ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || die "已取消"
else
    ok "工作区干净"
fi

# ---------- 2. 语法校验 ----------
step "2/6 语法校验"
SYNTAX_FAIL=0
for f in arch-install/*.sh; do
    [ -f "$f" ] || continue
    if bash -n "$f" 2>/dev/null; then
        ok "bash 语法: $(basename "$f")"
    else
        err "bash 语法错误: $f"
        SYNTAX_FAIL=1
    fi
done
for f in arch-install/*.py; do
    [ -f "$f" ] || continue
    if python3 -m py_compile "$f" 2>/dev/null; then
        ok "python 语法: $(basename "$f")"
    else
        err "python 语法错误: $f"
        SYNTAX_FAIL=1
    fi
done
[ "$SYNTAX_FAIL" -eq 0 ] || die "存在语法错误，已中止发版"
rm -rf arch-install/__pycache__

# ---------- 3. 打标签 ----------
step "3/6 创建标签"
git tag -a "$TAG" -m "$TAG" -m "发布 $TAG（由 release.sh 自动创建）" || die "创建标签失败"
ok "已创建 annotated tag: $TAG"

# ---------- 4. 打包 ----------
step "4/6 打包"
PREFIX="$PKG_NAME-$VERSION"
TARBALL="/tmp/$PREFIX.tar.gz"
ZIPFILE="/tmp/$PREFIX.zip"
git archive --format=tar.gz --prefix="$PREFIX/" -o "$TARBALL" HEAD || die "tar.gz 打包失败"
git archive --format=zip    --prefix="$PREFIX/" -o "$ZIPFILE" HEAD || die "zip 打包失败"
ok "tar.gz: $(ls -lh "$TARBALL" | awk '{print $5}')"
ok "zip:    $(ls -lh "$ZIPFILE" | awk '{print $5}')"
printf '         包含文件: %s 个\n' "$(git ls-files | wc -l | tr -d ' ')"

# ---------- 5. 推送并创建 Release ----------
step "5/6 推送并创建 Release"
# 分支必须先推成功：否则会出现「分支未推送但 Release 已创建」的不一致状态，
# 别人 clone 不到与发布对应的提交。
if [ "$(git rev-parse HEAD)" != "$(git rev-parse "origin/$CUR_BRANCH" 2>/dev/null || echo none)" ]; then
    if run_net git push origin "$CUR_BRANCH"; then
        ok "分支已推送"
    else
        die "分支推送失败（真实报错见上方）"
    fi
else
    ok "分支已是最新"
fi
if run_net git push origin "$TAG"; then
    ok "标签已推送"
else
    die "标签推送失败（真实报错见上方）"
fi

if [ -n "$NOTES_IN" ] && [ -f "$NOTES_IN" ]; then
    NOTES_FILE="$NOTES_IN"
    ok "使用指定发布说明: $NOTES_IN"
else
    NOTES_FILE="/tmp/release-notes-$VERSION.md"
    PREV_TAG=$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || echo "")
    {
        echo "# $TAG"
        echo ""
        if [ -n "$PREV_TAG" ]; then
            echo "自 $PREV_TAG 以来的变更："
            echo ""
            git log --oneline --no-decorate "$PREV_TAG..$TAG" | sed 's/^/ - /'
        fi
        echo ""
        echo "## 下载"
        echo ""
        echo "| 文件 | 适用平台 |"
        echo "| --- | --- |"
        echo "| \`$PREFIX.tar.gz\` | macOS / Linux |"
        echo "| \`$PREFIX.zip\` | Windows |"
        echo ""
        echo "## 许可证"
        echo ""
        echo "[MIT](LICENSE)"
    } > "$NOTES_FILE"
    ok "已自动生成发布说明"
fi

if run_net "$GH" release create "$TAG" --repo "$REPO_SLUG" \
        --title "$TAG" --notes-file "$NOTES_FILE" --latest \
        "$TARBALL" "$ZIPFILE"; then
    ok "Release 创建成功并已上传附件"
else
    die "Release 创建失败（真实报错见上方）"
fi

# ---------- 6. 验证 ----------
step "6/6 验证"
RELEASE_URL="https://github.com/$REPO_SLUG/releases/tag/$TAG"
printf '         发布页: %s\n' "$RELEASE_URL"
for f in "$PREFIX.tar.gz" "$PREFIX.zip"; do
    DL_URL="https://github.com/$REPO_SLUG/releases/download/$TAG/$f"
    CODE=""
    # 附件上传与 CDN 生效有延迟，且本机代理会间歇断连，故带重试
    for _v in 1 2 3; do
        CODE=$(curl -sIL -m 30 -o /dev/null -w '%{http_code}' "$DL_URL" 2>/dev/null)
        [ "$CODE" = "200" ] && break
        sleep 4
    done
    if [ "$CODE" = "200" ]; then
        ok "下载可用（HTTP 200）: $f"
    else
        warn "下载返回 HTTP ${CODE:-无响应}: $f（附件可能仍在上传或 CDN 未就绪，稍后手动确认）"
    fi
done
printf '         标签指向: %s\n' "$(git rev-parse --short "$TAG^{commit}")"
printf '         当前提交: %s\n' "$(git rev-parse --short HEAD)"

echo ""
echo "=============================================="
printf ' %b发版完成%b\n' "$G" "$N"
echo "=============================================="
