# 贡献指南

感谢你有兴趣参与本项目。以下是参与方式与协作规范。

---

## 报告问题

提交 Issue 前，请先：

1. 运行 `bash arch-install/diagnose.sh` —— 多数常见问题它已能定位并给出修复建议
2. 搜索现有 Issue，避免重复

提交时请附上：

- **运行环境**：macOS 版本、芯片型号、Parallels Desktop 版本
- **复现步骤**：你执行了哪些命令
- **实际结果与预期结果**
- **相关日志**：`arch-install/log.txt`（安装日志）或终端输出

> ⚠️ **请先移除日志中的敏感信息**（IP、用户名、密码、令牌等）再粘贴。

---

## 提交改动

```bash
# 1. Fork 并克隆
git clone git@github.com:<你的用户名>/Mac-Arch-Installer.git
cd Mac-Arch-Installer

# 2. 建立分支（分支名体现改动性质）
git checkout -b fix/nic-type-detection

# 3. 改动、自测（见下方规范）

# 4. 提交
git commit -m "fix: 修正网卡类型检测在 host-only 下的误判"

# 5. 推送并发起 Pull Request
git push origin fix/nic-type-detection
```

分支命名建议：

| 前缀 | 用途 |
| --- | --- |
| `feat/` | 新功能 |
| `fix/` | 缺陷修复 |
| `docs/` | 文档更新 |
| `refactor/` | 重构 |
| `chore/` | 杂项（依赖、CI 等） |

---

## 代码规范

### Shell 脚本

- **必须通过 `shellcheck`**（CI 会检查，severity ≥ warning）
- 使用 `bash`（`#!/bin/bash`），需要 bash 特性时不做 POSIX 兼容妥协
- 变量引用统一加引号：`"$VAR"`（数组/有意分词处显式加 `# shellcheck disable=SC2086`）
- **错误处理**：破坏性命令（分区、格式化、删除）**绝不能把 stderr 丢进 `/dev/null`**——
  静默失败会让脚本在错误的前提上继续执行，最终以无关的现象报错，把排查引向错误方向
- **关键步骤加断言**：如分区数量、挂载容量必须在继续前校验
- 面向用户的输出使用中文，代码注释可使用中文

```bash
# 好的做法：保留输出 + 断言
parted -s "$DISK" mklabel gpt >>/tmp/part.log 2>&1 || true
NPART=$(lsblk -lno NAME "$DISK" | tail -n +2 | wc -l)
if [ "$NPART" -ne 2 ]; then
    echo "分区失败，parted 输出：$(cat /tmp/part.log)"
    exit 1
fi
```

### Python 脚本

- 仅使用标准库（本项目的分发服务刻意保持零依赖）
- 需通过 `python -m py_compile`

### 兼容性

- 面向虚拟机的脚本以 **Arch Linux ARM (aarch64)** 为准
- 面向宿主机的脚本需兼容 **macOS 自带 bash 3.2**（避免 `declare -A`、`${var,,}` 等 4.x 特性）

---

## 文档规范

- 文档面向**中文读者**为主，英文 README 与中文 README 保持结构对应
- 使用表格承载参数说明与对比信息，比散文更利于速查
- **FAQ 不只写"怎么修"，还要写清根因与判别特征**——
  例如"能连宿主机但连不上外网 → 先查网卡是不是 `host` 类型"
- 涉及命令的章节给出**可直接复制**的完整命令，避免省略关键参数
- Markdown 需通过 `markdownlint`（CI 会检查）

---

## 测试要求

提交前请确认：

```bash
# 1. 语法检查
for f in arch-install/*.sh; do bash -n "$f" || echo "FAIL: $f"; done
python3 -m py_compile arch-install/*.py

# 2. 静态检查
shellcheck -S warning arch-install/*.sh

# 3. 端到端自检（宿主机侧）
bash arch-install/check.sh
bash arch-install/diagnose.sh
```

若改动涉及虚拟机内部逻辑，请在真实环境中验证，并在 PR 描述中说明验证方式与结果。

**涉及安装流程的改动**：请在 PR 中说明是否完整跑通了安装，或说明因条件所限未能验证的部分。

---

## 提交信息规范

采用 [Conventional Commits](https://www.conventionalcommits.org/)：

```
<类型>: <简短描述>

<可选正文：说明动机与影响>
```

常用类型：`feat` / `fix` / `docs` / `refactor` / `chore` / `test`

示例：

```
feat: 支持配置文件驱动安装与多桌面环境选择

- 新增 install.conf 配置模板，可覆盖主机名、用户、磁盘、桌面环境等
- NEW_DESKTOP 支持 kde / gnome / xfce / none
- 无配置文件时沿用内置默认值，保持向后兼容
```

---

## 发版流程（维护者）

```bash
# 1. 更新 CHANGELOG.md，把 Unreleased 的内容归入新版本号
# 2. 提交
git add -A && git commit -m "chore: 发布 v1.2.0"
# 3. 一键发版（自动打标签、打包、创建 Release、上传附件并验证）
bash arch-install/release.sh 1.2.0
```

版本号遵循语义化版本：不兼容改动升 `MAJOR`，向下兼容的新功能升 `MINOR`，修 bug 升 `PATCH`。

---

## 许可证

贡献的代码将以 [MIT](LICENSE) 许可发布。
