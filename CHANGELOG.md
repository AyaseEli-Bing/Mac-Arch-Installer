# 更新日志

本项目的所有重要变更都会记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

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

[Unreleased]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/compare/v1.2.2...HEAD
[1.2.1]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/AyaseEli-Bing/Mac-Arch-Installer/releases/tag/v1.0.0
