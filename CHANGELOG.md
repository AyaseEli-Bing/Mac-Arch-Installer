# 更新日志

本项目的所有重要变更都会记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [1.4.0] - 2026-09-23

### 新增

- **`dev-env.manifest`**：开发环境包清单，单一事实源。原先包列表以三处硬编码
  散在 `dev-setup.sh` 内（基础工具、CLI 工具、语言映射），既无法回答「我缺什么」，
  也无法复用到第二台机器。`@default_langs` 指令同样收在这里，避免两个脚本各写一份默认值。
- **`dev-setup.sh` 三种模式**：`check` 只核对不安装、不需要 sudo；`apply`（默认）补齐缺失项；
  `export` 把当前环境写成新清单。原有的 `LANGS` / `INSTALL_CLI` / `USE_CN_MIRROR`
  用法保持不变。
- **`install.sh` 镜像探活择优**：写入 mirrorlist 前逐站探测连通性与响应耗时，取最快者置首、
  其余作后备；全部探测失败则退回静态顺序并告警，**不因此中止安装**。
- **`vm-check.sh` 开发环境完整度**：按清单逐项核对，输出 `N/M` 与缺失包列表；
  找不到清单时只打印提示，不判失败（保持单文件拷入虚拟机即可用的既有用法）。
- **`host-res.sh`**：宿主机资源探测共用片段。阈值（磁盘 10 / 30 GiB、内存 50% 警告线与
  40% 建议值、CPU 超配）与取数逻辑单点定义，由 `check.sh` 与 `diagnose.sh`
  各自 source 同一份。此前两脚本各自实现探测逻辑，已经出过一次结论互相矛盾的缺陷。
- **`check.sh` 第 2 组 · 宿主机资源水位**：检查虚拟机**实际所在卷**的可用空间
  （按 `prlctl` 的 `Home:` 定位，不限于默认 `~/Parallels`）、虚拟机内存分配占宿主机
  物理内存的比例、以及 CPU 分配核数是否超配。此前 `check.sh` 不查任何资源水位，
  「装完虚拟机把宿主机磁盘撑满」这类事故完全敞开。
- **`diagnose.sh` 宿主机资源水位一节**：同一组事实的事后复核，并对每个失败项给出
  可直接执行的修复命令。
- **`check.sh` 新增 `[WARN]` 级**：容量或分配量偏紧只提示、不阻断，不计入退出码。
- **`install.sh` 结构化安装日志**：每条记录附加 `run= stage= seq= dt=` 四个字段与本地留底，
  消息文本原样保留（`[15] ALL DONE` 等验收字面量不受影响）。
- **`install.sh` 回传丢失可见**：`r()` 累计 POST 失败次数，收尾 `[99] RUN SUMMARY` 行给出
  `lost=`。此前失败被静默吞掉，宿主机一掉线日志就被腰斩，而文件本身不显示缺了什么。
- **`install.sh` 摘要挂 EXIT trap**：失败出口散落在十几个 `[FATAL]` 分支里，
  逐个补打印既易漏又会在后来新增分支时静默失配，改为退出时统一给出。
- **`install.sh` 日志留存到新系统**：`/root/install-<run>-live.log` 与 `-chroot.log`，
  在宿主机不可达时仍有完整事后证据。
- **`serve.py` 按运行分隔**：遇到新的 `run=` 自动插入分隔行，多次尝试的日志并存可对比。

### 变更与修复

- **`install.sh`**：消除 `r()` 的两处独立定义 —— chroot 脚本现在由 `declare -f r`
  注入同一份函数体。此前改一处漏一处，是 `host-res.sh` 那类「同一逻辑两处实现」问题的又一实例。
- **`serve.py`**：启动时不再删除 `log.txt`。安装失败后重启服务是常见动作，
  原先这一步会把上一次尝试的记录一并抹掉，事后无从对比两次尝试。
- **`install.sh`**：日志 POST 改用 `--data-raw`，避免消息以 `@` 开头时被 curl 当成文件名读取。
- **`环境配置与验证清单.md`**：修正三处硬编码指向旧克隆工作区的绝对路径
  （`cd /Users/.../WorkBuddy/...`、`.workbuddy/binaries/python/.../python3`），
  这些命令对新克隆的读者直接失效。

- **`install.sh`**：删除 chroot 阶段第二份 mirrorlist。它不只是重复 —— 会把 step 6
  探活择优的结果**覆盖**回静态顺序。
- **`install.sh`**：`pacstrap` 失败原因改为按日志实际内容分类判读
  （镜像不可达 / 签名或密钥环 / 磁盘空间 / 包名不存在），替代原先无法区分的
  「常见原因 网络不可达 / 磁盘空间不足」。
- **`dev-setup.sh`**：安装失败不再把输出重定向丢弃。此前「包已装好」「镜像站挂了」
  「该包在本架构仓库里根本不存在」三种结果全部塌成同一句「安装有告警」；
  现在区分 已装 / 待装 / 仓库无此包 三态并给出对应处置建议。
- **`dev-setup.sh`**：修复核对结论自相矛盾 —— 「仓库无此包」曾被计入缺失数，
  导致同一份输出里既说「缺 1 个」又说「已全部安装」。
- **`install.sh`**：修复探活误判 —— `curl` 在连接超时失败时**仍会输出 `time_total`**，
  仅校验输出是否为数字会把不可达站点判成探活成功。现同时校验退出码与 `http_code`。
- `check.sh` 检查分组由 4 组增至 5 组，结果行增加警告计数。
- 修复 `diagnose.sh` 内存修复建议算出与当前值相同的数：警告线（50%）与
  建议值（40%）分离，使建议真正可执行。
- `环境配置与验证清单.md`：修正「本项目无需设置任何环境变量」这一过时说法，
  改为完整的可选覆盖变量表。

## [1.3.0] - 2026-09-22

本版本为纯文档增量，不涉及任何脚本行为变更。

### 新增

- **`GitHub零基础入门教程.md`**：面向零基础用户的完整中文教程，共 12 节。
  覆盖 Git 与 GitHub 的区别、SSH 密钥准备、仓库创建与克隆、提交与推送、
  分支模型、Pull Request 流程、常见报错自救、命令速查表与术语对照、
  练习路线，以及语义化版本与标签（tag）的用法。
- **`README徽章体系指南.md`**：讲解 README 徽章（badge）的作用与设计原则、
  8 个维度的分类速查表、徽章结构与生成方式、挑选与排布的实践建议、
  常见误区、3 套可直接抄用的模板，以及提交 README 前的逐项速查清单。

### 修复

- **`GitHub零基础入门教程.md`**：修复 6 处 markdownlint 报错
  （引用块内空行、列表内围栏代码块缺空行、强调标记内空格），
  使新增文档与 CI 的 `markdownlint-cli2` 检查口径一致。

## [1.2.2] - 2026-09-22

本版本基于一次全量代码审查（详见 `代码审查报告.md`），修复 4 个高危、8 个中危缺陷。
**其中 4 个高危项均无法被 `shellcheck` / `bash -n` / `py_compile` 发现**——
它们属于「逻辑正确但语义有偏」，详见报告的「审查方法说明」。

### 修复 · 高危（凭据泄露与错误掩盖）

- **`install.sh`**：收尾时一并删除 `.install-vars` 与 `.host_url`。
  此前只删了 `config.sh`，导致**明文密码残留**在新系统的 `/root/.install-vars`。
- **`install.sh`**：用 `${PIPESTATUS[0]}` 捕获 `arch-chroot` 的真实退出码。
  此前 `| tail -5` 使 `$?` 取到 `tail` 的 0，chroot 配置失败时仍输出 `ALL DONE`。
- **`reset-password.sh`**：密码改为经 stdin 传给 `chpasswd`，不再拼进 `bash -c` 参数。
  此前密码会出现在 `ps` / `/proc/*/cmdline` 中；且密码含单引号时引号结构被破坏，构成命令注入。
- **`proxy-forward.py`**：连接建立后清除 socket 超时（`settimeout(None)`）。
  此前 `create_connection(timeout=15)` 的超时会保留在 socket 上，
  导致**空闲超过 15 秒的连接被静默断开**（经实测确认，修复后空闲 18 秒正常）。

### 修复 · 中危

- **`serve.py`**：限制请求体长度（1 MB），超限返回 413；`Content-Length` 非法值不再抛异常。
- **`serve.py`**：路由改为精确匹配，未知路径返回 404
  （此前 `/key` 会命中 `/k`，且任意路径的 POST 都返回 200）。
- **`proxy-forward.py`**：`accept()` 异常时区分瞬时与致命错误并退避，避免忙等循环；
  新增并发连接上限（128）。
- **`diagnose.sh`**：ISO 探测改为按时间取最新，与 `check.sh` 一致
  （此前按字母序，两脚本可能报告不同文件，导致结论互相矛盾）。
- **`release.sh`**：分支推送失败改为阻断发版，避免「分支未推送但 Release 已创建」。
- **`install.sh`**：加载配置文件前校验属主与写权限；校验目标磁盘非光驱/回环设备。

### 修复 · 低危与健壮性

- **`check.sh` / `diagnose.sh`**：`grep -qF` 避免虚拟机名被当作正则；
  端口探测在 `lsof` 缺失时回退到 `nc`，避免把「工具缺失」误判为「未监听」。
- **`proxy-forward.py`**：转发结束改为半关闭（`SHUT_WR`），避免截断未传完的响应；
  参数支持环境变量覆盖，便于测试与适配。
- **`install.sh`**：宿主机探测失败时显式告警；`pacstrap` 前关闭路径名展开；修正 `dd` 注释。
- **`reset-password.sh`**：校验 `passwd -S` 状态位，未生效则报错退出；宿主机地址支持自动探测。
- **`dev-setup.sh`**：Go 校验库改用 `gosum.io` 并经 goproxy.cn 代理 sumdb。

### 另含

- 新增 `自检功能使用教程.md`；`check.sh` 可移植性修正（自动探测 Python 与 ISO）。

## [1.2.1] - 2026-09-22

### 修复

- `release.sh`：移除对未定义变量 `$FAIL` 的引用。此前发版流程虽能正常完成，
  但结束时会输出 `[: : integer expression expected`。

## [1.2.0] - 2026-09-22

本次为功能扩展版本：让工具从"一次性脚本"变成可配置、可维护的项目。

### 新增

- **配置文件驱动安装**：`install.sh` 支持通过 `/root/install.conf` 覆盖默认配置
  （主机名、时区、语言、用户、密码、磁盘、镜像源等），并提供 `install.conf.example` 模板。
  无配置文件时沿用内置默认值，保持向后兼容。
- **多桌面环境支持**：`install.sh` 可通过 `NEW_DESKTOP` 选择
  `kde` / `gnome` / `xfce` / `none`（纯命令行），自动安装对应桌面与显示管理器（sddm / gdm / lightdm）。
- **`dev-setup.sh`**：开发环境一键配置。安装语言工具链（Go / Python / Node / Rust / C++ / Java 可选）
  与常用 CLI 工具，并配置国内镜像源（goproxy.cn / npmmirror / 清华 PyPI / USTC Cargo）。
- **`vm-check.sh`**：虚拟机健康巡检。只读检查系统、磁盘、服务、网络、桌面、输入法与
  Parallels 集成状态，按 OK / WARN / FAIL 分级汇总，退出码等于失败项数量。
- **`diagnose.sh`**：宿主机侧故障自诊断。逐条检测本项目实际踩过的坑
  （网卡类型、启动顺序、ISO 校验、分发服务、代理转发、虚拟机可达性等），
  并对每项问题给出可执行的修复命令。
- **`release.sh`**：自动发版。一条命令完成前置检查、语法校验、打标签、`git archive` 打包、
  推送、创建 Release 与上传附件，并验证下载链接可用性。
- **GitHub Actions CI**：shellcheck 静态检查 + Python 语法检查 + Markdown 文档检查。
- **英文版文档**：新增 `README.en.md`，与中文 README 结构对应。
- **README 徽章与标签**：新增 5 个 shields.io 徽章（版本 / 许可证 / 平台 / 架构 / 客户机系统）
  与关键词标签行，中英文文档互加语言切换链接。
- **`CONTRIBUTING.md`**：贡献指南与代码规范。
- **本文件** `CHANGELOG.md`。

### 变更

- `install.sh` 内部重构：配置项集中于文件顶部，chroot 阶段通过 `/root/.install-vars`
  显式传递变量（chroot 后无法继承父 shell 变量）。
- 所有面向用户的脚本在非终端环境下自动禁用颜色输出，便于日志与管道处理。

## [1.1.0] - 2026-09-22

### 新增

- **`proxy-forward.py`**：端口转发工具。宿主机的本地代理通常只监听 `127.0.0.1`，
  虚拟机无法直接使用；本工具在虚拟网段上开一个端口并把流量原样转发到宿主机代理，
  使虚拟机可以复用同一条出网通路。纯 TCP 字节转发，天然支持 HTTP `CONNECT` 隧道。
- **`虚拟机网络配置.md`**：记录「虚拟机无法访问 GitHub 而宿主机正常」这一真实案例的
  完整排查链路 —— hosts 屏蔽 / 本地代理仅监听回环 / 虚拟机 DNS 继承解析三层因素叠加，
  含根证书导入、条件代理配置、`.bashrc` 非交互陷阱，以及 Docker / WSL 场景的通用性说明。

### 变更

- `README.md` 补充项目结构与文档索引。

## [1.0.0] - 2026-09-22

首个正式版本。

### 新增

- **`install.sh`**：在 Archboot live 环境内执行的自动安装脚本。分区 → 装包 → 配置 → 写引导，
  共 7 个阶段。
  - 分区工具四级降级链：`sgdisk → parted → sfdisk → fdisk`
    （实测 Archboot 精简环境不含 `parted` / `partprobe`）
  - 分区数量断言（必须为 2）与挂载容量断言（须 > 10 GB），避免在错误布局上继续安装
  - `systemd-boot` 引导 + `BOOTAA64.EFI` 兜底（应对 `bootctl` 无法写 EFI 变量的情况）
  - 内核镜像路径自动探测（ARM 为 `/boot/Image`，不同于 x86 的 `vmlinuz-linux`）
  - 宿主机地址自动探测（无需关心虚拟机落在 Shared 还是 Host-Only 网段）
  - `pacstrap` 失败立即中止，避免在半成品系统上产生误导性的"完成"
- **`serve.py`**：宿主机 HTTP 分发服务，提供 4 条路由 ——
  `/ping` 探活、`/i` 安装脚本、`/k` SSH 公钥、`/r` 密码重置脚本，并接收虚拟机回传的安装日志。
- **`reset-password.sh`**：忘记密码时经 live 环境 chroot 重置。
  脚本不硬编码任何密码，通过环境变量或 `/dev/tty` 交互获取。
- **`check.sh`**：宿主机侧环境自检（11 项）。
- **`Arch-Linux-ARM-Parallels-安装指南.md`**：含 `archinstall` 向导逐步说明的手工安装指引。
- **`环境配置与验证清单.md`**：依赖清单、运行时要求、环境变量、构建调试与验证步骤。
- **`使用教程.md`**：完整操作手册，含逐步说明、功能演示、5 个使用场景与 12 个 FAQ。

### 说明

- 仅适用于 **Apple Silicon** Mac。Intel Mac 可原生虚拟化 x86_64 客户机，
  直接使用 Arch 官方 ISO 即可，无需本项目。
- Parallels Tools 官方不支持 Arch，属社区级支持。

[Unreleased]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/releases/tag/v1.0.0
