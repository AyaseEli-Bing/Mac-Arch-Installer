#!/bin/bash
# ============================================================
# 自动发版（在宿主机 macOS 上运行，需在项目根目录执行）
#
# 用法:
#   bash arch-install/release.sh 1.2.0              # 自动生成发布说明
#   bash arch-install/release.sh 1.2.0 notes.md     # 使用指定说明文件
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
    warn "工作区有未提交的变更，建议先提交"
    git status --short | sed 's/^/         /'
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
git push origin "$CUR_BRANCH" >/dev/null 2>&1 || warn "分支推送跳过或失败（可能已是最新）"
git push origin "$TAG" >/dev/null 2>&1 || die "标签推送失败"
ok "标签已推送"

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

if "$GH" release create "$TAG" --repo "$REPO_SLUG" \
        --title "$TAG" --notes-file "$NOTES_FILE" --latest \
        "$TARBALL" "$ZIPFILE" >/dev/null 2>&1; then
    ok "Release 创建成功并已上传附件"
else
    die "Release 创建失败（请检查 gh 权限或网络）"
fi

# ---------- 6. 验证 ----------
step "6/6 验证"
RELEASE_URL="https://github.com/$REPO_SLUG/releases/tag/$TAG"
printf '         发布页: %s\n' "$RELEASE_URL"
for f in "$PREFIX.tar.gz" "$PREFIX.zip"; do
    DL_URL="https://github.com/$REPO_SLUG/releases/download/$TAG/$f"
    CODE=$(curl -sIL -m 30 -o /dev/null -w '%{http_code}' "$DL_URL" 2>/dev/null)
    if [ "$CODE" = "200" ]; then
        ok "下载可用（HTTP 200）: $f"
    else
        warn "下载返回 HTTP $CODE: $f"
    fi
done
printf '         标签指向: %s\n' "$(git rev-parse --short "$TAG^{commit}")"
printf '         当前提交: %s\n' "$(git rev-parse --short HEAD)"

echo ""
echo "=============================================="
if [ "$FAIL" -eq 0 ]; then :; fi
printf ' %b发版完成%b\n' "$G" "$N"
echo "=============================================="
