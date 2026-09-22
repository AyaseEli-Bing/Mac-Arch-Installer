# README 徽章（Badge）体系指南

> 面向开源项目维护者。目标：**用最少的徽章，在 3 秒内让访客判断"这个项目活着吗、能用吗、我能用吗"**。
> 全文速读结构：作用与原则 → 分类速查 → 结构原理 → 选型与维护 → 误区 → 可抄模板。

**一个合格的徽章行长这样（4～6 个，首屏可见）：**

```markdown
[![CI](https://github.com/o/r/actions/workflows/ci.yml/badge.svg)](https://github.com/o/r/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/o/r/branch/main/graph/badge.svg)](https://codecov.io/gh/o/r)
[![npm version](https://img.shields.io/npm/v/pkg)](https://www.npmjs.com/package/pkg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
```

---

## 1. 徽章的作用与设计原则

### 1.1 它解决什么问题

README 打开后，访客先扫一眼顶部再决定要不要往下读。徽章的价值是**把需要点进 5 个页面才能确认的事，压缩成一行的视觉信号**：

| 访客的真实疑问 | 对应徽章 |
| --- | --- |
| 这项目还在维护吗？ | 最近提交时间、CI 状态 |
| 我能放心升级吗？ | CI 通过、测试覆盖率、版本号 |
| 我能合法商用吗？ | 开源许可证 |
| 有多少人在用？ | 下载量、Star 数 |
| 我的环境跑得起来吗？ | 语言/框架版本、平台兼容性 |

### 1.2 四条设计原则

1. **一屏原则**：首屏徽章区控制在 **3～8 个**。超过 8 个，信息密度反噬可读性，形成"徽章墙"。
2. **可点击原则**：**每个徽章都必须包一层链接**指向证据页（CI 详情页、覆盖率报告、许可证全文）。不可点击的徽章只是一张贴纸。
3. **只放"会变且有人关心"的信息**：`Python 3.9+` 这类静态事实优先写成一行文字；只有需要颜色语义（通过/失败/告警）时才用徽章。
4. **诚实原则**：徽章反映真实状态。长期显示 `unknown`、`no data` 或红色的徽章，比没有徽章更伤信任。

> 一句话标准：**宁可少一个徽章，不要多一个假徽章。**

---

## 2. 徽章分类速查表（8 个维度）

下表中 `<o>`=仓库所有者、`<r>`=仓库名、`<pkg>`=包名。均为 Shields.io 语法（最通用）。

### 2.1 构建状态（必选，最高优先级）

| 徽章 | 图片 URL | 备注 |
| --- | --- | --- |
| GitHub Actions | `https://github.com/<o>/<r>/actions/workflows/ci.yml/badge.svg` | 文件名须与实际 workflow 一致；可用 `?branch=main` |
| GitLab CI | `https://gitlab.com/<o>/<r>/badges/main/pipeline.svg` | — |
| CircleCI | `https://img.shields.io/circleci/build/github/<o>/<r>/main` | — |
| 自建 Jenkins | `https://img.shields.io/endpoint?url=<你的JSON地址>` | 见 3.4 动态徽章 |

### 2.2 测试覆盖率（推荐，库类项目几乎必备）

| 服务 | 图片 URL | 备注 |
| --- | --- | --- |
| Codecov | `https://codecov.io/gh/<o>/<r>/branch/main/graph/badge.svg` | 主流选择，支持 token 免密 |
| Coveralls | `https://coveralls.io/repos/github/<o>/<r>/badge.svg?branch=main` | 老牌，历史曲线清晰 |
| 自托管 | `https://img.shields.io/endpoint?url=…` | 覆盖率写入 JSON 后由端点渲染 |

### 2.3 版本号（推荐，与发版流程绑定）

| 渠道 | 图片 URL |
| --- | --- |
| npm | `https://img.shields.io/npm/v/<pkg>` |
| PyPI | `https://img.shields.io/pypi/v/<pkg>` |
| crates.io | `https://img.shields.io/crates/v/<crate>` |
| Go | `https://img.shields.io/github/v/tag/<o>/<r>` |
| GitHub Release | `https://img.shields.io/github/v/release/<o>/<r>`（含 `?include_prereleases`） |

> 版本号徽章**由 Git tag 驱动**——打 tag 并发 Release，徽章自动更新。这也是把版本号纳入语义化版本管理的实际收益（见《GitHub 零基础入门教程》第 11 节）。

### 2.4 开源许可证（必选，法律属性）

| 写法 | 图片 URL | 适用 |
| --- | --- | --- |
| 自动识别 | `https://img.shields.io/github/license/<o>/<r>` | 仓库根目录有 `LICENSE` 时最省事 |
| 静态声明 | `https://img.shields.io/badge/License-MIT-yellow.svg` | 想固定写法 |
| 按包识别 | `https://img.shields.io/npm/l/<pkg>` / `…/pypi/l/<pkg>` | 多包仓库 |

### 2.5 下载量 / 活跃度（可选，面向用户的成熟项目）

| 指标 | 图片 URL |
| --- | --- |
| npm 月下载 | `https://img.shields.io/npm/dm/<pkg>` |
| PyPI 月下载 | `https://img.shields.io/pypi/dm/<pkg>` |
| GitHub 全版本下载 | `https://img.shields.io/github/downloads/<o>/<r>/total` |
| Star（社交样式） | `https://img.shields.io/github/stars/<o>/<r>?style=social` |
| 贡献者数 | `https://img.shields.io/github/contributors/<o>/<r>` |
| 最近提交 | `https://img.shields.io/github/last-commit/<o>/<r>` |

> ⚠️ **最近提交徽章是双刃剑**：它诚实展示活跃度，也会放大"半年没动"的负面印象。维护不规律的项目慎用。

### 2.6 语言与框架（可选，1～2 个足够）

| 目的 | 图片 URL |
| --- | --- |
| 主语言自动识别 | `https://img.shields.io/github/languages/top/<o>/<r>` |
| 静态声明 + 图标 | `https://img.shields.io/badge/Python-3.9%2B-blue?logo=python&logoColor=white` |
| 框架 | `https://img.shields.io/badge/React-18-blue?logo=react` |
| 包管理器 | `https://img.shields.io/badge/pnpm-%3E%3D8-orange?logo=pnpm` |

### 2.7 代码质量与安全（推荐用于中大型项目）

| 维度 | 图片 URL |
| --- | --- |
| Code Climate 可维护性 | `https://img.shields.io/codeclimate/maintainability/<o>/<r>` |
| SonarCloud 质量门 | `https://sonarcloud.io/api/project_badges/measure?project=<key>&metric=alert_status` |
| Snyk 漏洞数 | `https://img.shields.io/snyk/vulnerabilities/github/<o>/<r>` |
| OpenSSF Scorecard | `https://api.securityscorecards.dev/projects/github.com/<o>/<r>/badge` |

### 2.8 兼容性与平台（按受众选择）

| 目的 | 图片 URL |
| --- | --- |
| Python 版本范围 | `https://img.shields.io/pypi/pyversions/<pkg>` |
| Node 版本要求 | `https://img.shields.io/node/v/<pkg>` |
| 静态平台声明 | `https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey` |
| 架构声明 | `https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-blue` |
| 文档站 | `https://img.shields.io/badge/docs-mkdocs--material-blue` |

---

## 3. 徽章的结构与生成方式

### 3.1 URL 三段式：label - message - color

Shields.io 静态徽章的结构是：

```
https://img.shields.io/badge/<label>-<message>-<color>
                              │        │        └─ 颜色（命名色或十六进制）
                              │        └─ 右侧值（版本号、状态）
                              └─ 左侧标签（说明这是什么）
```

**转义规则（务必记住，新手最常在这里卡住）：**

| 想显示 | 在 URL 中写 |
| --- | --- |
| 空格 | `_` 或 `%20` |
| 下划线 `_` | `__`（双下划线） |
| 连字符 `-` | `--`（双连字符） |
| 竖线 `\|` | `%7C` |
| `+` | `%2B` |
| `>=` | `%3E%3D` |

**颜色语义约定**（跨项目保持一致，别自创）：

| 颜色 | 语义 |
| --- | --- |
| `brightgreen` | 通过 / 正常 / 支持 |
| `yellow` / `orange` | 警告 / 实验性 / 弱约束 |
| `red` | 失败 / 不支持 / 有漏洞 |
| `blue` | 中性信息（版本、平台） |
| `lightgrey` | 未知 / 不适用 |

**常用样式参数：** `?style=flat-square`（默认推荐）、`?style=for-the-badge`（大字块，适合 Hero 区）、`?logo=<simple-icons名>&logoColor=white`。

### 3.2 Markdown 引用语法（图片 + 链接两层嵌套）

```markdown
[![替代文字](图片URL)](点击后跳转URL)
```

- **外层 `[...](链接)`** 把图片变成可点击链接 —— 这就是"可点击原则"的落地。
- **内层 `![替代文字](图片)`** 的替代文字是**无障碍必需**：屏幕阅读器靠它朗读，图片加载失败时也靠它兜底。别偷懒写成 `![img]`。

**源码整洁技巧：引用式写法。** 徽章多了之后，把 URL 收到底部统一定义：

```markdown
[![CI][ci-badge]][ci-link]
[![Coverage][cov-badge]][cov-link]

[ci-badge]: https://github.com/<o>/<r>/actions/workflows/ci.yml/badge.svg
[ci-link]:  https://github.com/<o>/<r>/actions/workflows/ci.yml
[cov-badge]: https://codecov.io/gh/<o>/<r>/branch/main/graph/badge.svg
[cov-link]:  https://codecov.io/gh/<o>/<r>
```

### 3.3 静态徽章 vs 动态徽章

| 类型 | 数据来源 | 更新方式 | 适用 |
| --- | --- | --- | --- |
| **静态徽章** | URL 里写死的文字 | 改 README 才变 | 许可证、平台、架构、纯声明性信息 |
| **动态徽章** | 实时查询第三方服务 | 自动 | CI、覆盖率、版本、下载量 |
| **端点徽章（Endpoint）** | 你自己的 JSON 接口 | 你更新 JSON 即变 | 自有指标、内网 CI、任何官方没适配的数据 |

**端点徽章的 JSON 契约**（schemaVersion 必须为 1）：

```json
{
  "schemaVersion": 1,
  "label": "coverage",
  "message": "87%",
  "color": "brightgreen"
}
```

渲染：

```markdown
[![coverage](https://img.shields.io/endpoint?url=https%3A%2F%2Fexample.com%2Fbadge.json)](https://example.com/report)
```

> URL 里的 `url=` 参数**必须做百分号编码**，否则 `://` 会被截断解析。

### 3.4 常见图标 / 渲染服务

| 服务 | 定位 | 备注 |
| --- | --- | --- |
| **Shields.io** | 事实标准，覆盖面最广 | 支持静态/动态/端点；可自托管 |
| **Badgen.net** | 轻量替代，`badgen.net/npm/v/pkg` 语法更短 | 速度快，覆盖面略小 |
| **Simple Icons** | 图标库，通过 `?logo=` 引用 | 品牌图标来源 |
| **For the Badge** | `?style=for-the-badge` 或 forthebadge.com | 大字块，适合项目首页 |
| **自托管 Shields** | Docker 部署 | 内网、对外部服务稳定性有要求时 |

> 国内访问提示：Shields.io 偶尔加载缓慢。徽章是 `<img>`，**加载失败不影响正文阅读**，可接受；若 README 面向国内为主，可考虑自托管或改用 Badgen。

---

## 4. 实践建议：怎么挑、怎么排、怎么摆、怎么养

### 4.1 按项目规模挑选

| 规模 | 建议徽章数 | 必选 | 可选 |
| --- | --- | --- | --- |
| **个人 / 小工具**（< 1k star） | 3～4 | CI、许可证、版本 | 语言/框架 1 个 |
| **中型库 / 框架** | 5～7 | + 覆盖率、下载量 | 兼容性、Node/Python 版本 |
| **大型 / 基础设施** | 6～8 | + 安全、质量门、贡献者 | OpenSSF Scorecard、文档站、路线图 |
| **应用 / 内部项目** | 2～3 | CI、许可证 | 平台兼容（README 非主要门面时可不放） |

### 4.2 排序：把"决定生死"的放前面

推荐顺序（从左到右）：

1. **构建状态** —— 项目活着的证据
2. **测试覆盖率** —— 代码可信度
3. **版本 / 发布** —— 用户能否用上
4. **许可证** —— 能否合法用
5. **兼容性 / 平台** —— 我的环境行不行
6. **下载量 / Star** —— 社区热度（放最后，它是结果不是前提）

> 视觉分组技巧：每组之间加一个空格或两个空格分隔；超过 6 个时**换行分组**（第一行状态类，第二行元数据类）。

### 4.3 摆放位置

| 位置 | 适用 | 说明 |
| --- | --- | --- |
| **标题正下方一行** | 绝大多数项目 | 默认且最有效，滚动前即可见 |
| **Hero / Banner 下方** | 有头图的项目 | 与项目 slogan 同屏 |
| **徽章表格** | 徽章 ≥ 8 个 | 用两列表格（徽章 \| 说明）避免横向溢出 |
| **分区内嵌** | 兼容性矩阵等 | 放在"支持平台"小节而非顶部 |

**排版细节**：徽章默认同行连续排列，GitHub 会自动换行；需要精确控制时用 HTML：

```markdown
<p align="center">
  <a href="..."><img src="..." alt="CI" height="20"></a>
  <a href="..."><img src="..." alt="Coverage" height="20"></a>
</p>
```

### 4.4 持续维护

| 维护动作 | 做法 | 频率 |
| --- | --- | --- |
| **链接有效性** | CI 中跑链接检查（`lychee`、`markdown-link-check`），失效即告警 | 每次 PR |
| **版本号自动更新** | 以 tag + Release 驱动徽章，不在 README 里手写版本号 | 每次发版 |
| **覆盖率数据** | CI 上传覆盖率到 Codecov/Coveralls，徽章自动刷新 | 每次 CI |
| **季度审计** | 检查是否有 `unknown`/红色徽章、废弃服务、过期平台声明 | 每季度 |
| **服务迁移** | 第三方关停时及时替换（历史上 Travis CI、david-dm 均已退出主流） | 按需 |

**最小可用的链接检查配置（GitHub Actions）：**

```yaml
- name: Check links
  uses: lycheeverse/lychee-action@v2
  with:
    args: --no-progress README.md
```

---

## 5. 常见误区

| 误区 | 后果 | 正确做法 |
| --- | --- | --- |
| **徽章墙**：一排 15 个以上 | 视觉噪音，核心状态被淹没 | 首屏 ≤ 8 个，其余收进表格或折叠区 |
| **信息过期**：写了 `Python 3.6+` 实际只测到 3.12 | 用户按错误信息做决策 | 静态声明随支持矩阵同步更新，或改用自动徽章 |
| **链接失效**：图片能显示但点击 404 | 违反可点击原则，信任受损 | 每个徽章配落地页；CI 定期校验 |
| **`unknown` / `no data` 徽章常驻** | 暗示"没人管" | 要么接上数据源，要么删掉这个徽章 |
| **假动态徽章**：手写数字冒充实时数据 | 本质是欺骗 | 一律用服务驱动或端点 JSON |
| **依赖已关停服务** | 图片 404，README 出现破图 | 优先 Shields.io / 官方服务，季度审计 |
| **缺失 alt 文本** | 无障碍问题，破图时无兜底 | `![CI 状态](...)` 写清含义 |
| **用徽章替代文档** | 徽章无法说明"怎么装、怎么用" | 徽章是入口，正文仍需安装/快速开始 |
| **徽章区堆砌社交 Proof** | Star 数不等于项目质量 | 热度类徽章放末位或省略 |
| **忽视移动端** | 长串徽章在窄屏折行混乱 | 控制数量，必要时用表格分组 |

---

## 6. 可直接抄用的三套模板

### 6.1 个人小工具（4 个）

```markdown
# 项目名

一句话说明这个项目解决什么问题。

[![CI](https://github.com/<o>/<r>/actions/workflows/ci.yml/badge.svg)](https://github.com/<o>/<r>/actions/workflows/ci.yml)
[![Version](https://img.shields.io/github/v/release/<o>/<r>)](https://github.com/<o>/<r>/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python](https://img.shields.io/badge/Python-3.9%2B-blue?logo=python&logoColor=white)](https://www.python.org)
```

### 6.2 中型开源库（7 个，分两组）

```markdown
# 项目名

一句话说明 + 30 字价值主张。

[![CI](https://github.com/<o>/<r>/actions/workflows/ci.yml/badge.svg)](https://github.com/<o>/<r>/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/<o>/<r>/branch/main/graph/badge.svg)](https://codecov.io/gh/<o>/<r>)
[![npm](https://img.shields.io/npm/v/<pkg>)](https://www.npmjs.com/package/<pkg>)
[![License](https://img.shields.io/github/license/<o>/<r>)](./LICENSE)

[![Downloads](https://img.shields.io/npm/dm/<pkg>)](https://www.npmjs.com/package/<pkg>)
[![Node](https://img.shields.io/node/v/<pkg>)](https://nodejs.org)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](./README.md#兼容性)
```

### 6.3 大型基础设施项目（8 个 + 表格化元信息）

```markdown
# 项目名

<div align="center">
  <a href="..."><img src=".../ci.yml/badge.svg" alt="CI" height="20"></a>
  <a href="..."><img src="https://codecov.io/gh/<o>/<r>/branch/main/graph/badge.svg" alt="Coverage" height="20"></a>
  <a href="..."><img src="https://img.shields.io/github/v/release/<o>/<r>" alt="Release" height="20"></a>
  <a href="..."><img src="https://img.shields.io/github/license/<o>/<r>" alt="License" height="20"></a>
</div>

| 维度 | 状态 |
| --- | --- |
| 安全审计 | ![Snyk](https://img.shields.io/snyk/vulnerabilities/github/<o>/<r>) |
| 质量门 | ![Sonar](https://sonarcloud.io/api/project_badges/measure?project=<key>&metric=alert_status) |
| OpenSSF | ![Scorecard](https://api.securityscorecards.dev/projects/github.com/<o>/<r>/badge) |
| 贡献者 | ![Contributors](https://img.shields.io/github/contributors/<o>/<r>) |
```

---

## 7. 速查清单（提交 README 前逐项对照）

- [ ] 徽章总数 ≤ 8 个，首屏可见
- [ ] 每个徽章都可点击，且链接指向真实证据页
- [ ] 每个徽章都写了有意义的 alt 文本
- [ ] 无长期 `unknown` / 红色 / 破图徽章
- [ ] 静态声明（平台、最低版本）与实际支持矩阵一致
- [ ] 版本号徽章由 tag / Release 驱动，非手写
- [ ] CI 中包含 README 链接检查
- [ ] 未使用已关停或不稳定服务
- [ ] 徽章排序符合"状态 → 版本 → 许可 → 兼容 → 热度"

---

*本指南基于 2026 年主流服务现状编写（Shields.io 为事实标准，支持静态 / 动态 / 端点三类徽章；端点徽章 JSON 契约 `schemaVersion` 固定为 1）。第三方服务存续状况会变化，建议每季度做一次徽章审计。*
