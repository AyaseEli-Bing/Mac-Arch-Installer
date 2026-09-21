# Mac 虚拟机安装 Arch Linux 懒人包

[![Release](https://img.shields.io/github/v/release/AyaseEli-Bing/Mac-Arch-Installer?label=version&color=blue)](https://github.com/AyaseEli-Bing/Mac-Arch-Installer/releases)
[![License](https://img.shields.io/github/license/AyaseEli-Bing/Mac-Arch-Installer?color=green)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Apple%20Silicon-black)](#环境要求)
[![Arch](https://img.shields.io/badge/arch-aarch64-orange)](#为什么需要这个包)
[![Guest OS](https://img.shields.io/badge/guest-Arch%20Linux%20ARM-1793d1)](#为什么需要这个包)

[简体中文](README.md) | [English](README.en.md)

在 **Apple Silicon Mac** 上用 **Parallels Desktop** 安装 **Arch Linux ARM** 的自动化工具包。

> 一条命令完成分区、装包、系统配置与引导安装。附带环境自检、实时日志回传、SSH 免密登录与密码重置能力。

**关键词：** `arch-linux` · `arch-linux-arm` · `archboot` · `parallels-desktop` · `apple-silicon` · `aarch64` · `arm64` · `虚拟化` · `macos` · `自动化安装`

---

## 目录

- [为什么需要这个包](#为什么需要这个包)
- [项目结构](#项目结构)
- [环境要求](#环境要求)
- [安装配置（可选）](#安装配置可选)
- [使用教程](#使用教程)
  - [步骤 1 · 环境自检](#步骤-1--环境自检1-分钟)
  - [步骤 2 · 创建虚拟机](#步骤-2--创建虚拟机仅首次)
  - [步骤 3 · 启动分发服务](#步骤-3--启动分发服务宿主机)
  - [步骤 4 · 引导进入 live 环境](#步骤-4--引导进入-live-环境)
  - [步骤 5 · 执行自动安装](#步骤-5--执行自动安装)
  - [步骤 6 · 收尾并重启](#步骤-6--收尾并重启)
- [关键功能](#关键功能)
- [常见使用场景](#常见使用场景)
- [常见问题](#常见问题)
- [注意事项](#注意事项)
- [设计要点](#设计要点)
- [文档](#文档)

---

## 为什么需要这个包

Apple Silicon 上的 Parallels 只能虚拟化 **ARM64** 客户机，而 Arch Linux 官方 ISO 仅有 **x86_64** 版本——直接下载官方镜像**根本无法启动**。

本工具包基于 [Archboot](https://archboot.com) 的 aarch64 镜像（ArchWiki 对此有[明确推荐](https://wiki.archlinux.org/title/Parallels_Desktop)），把整个安装过程自动化。

> Intel Mac 不适用本项目——Intel Mac 可原生虚拟化 x86_64，直接用[官方 ISO](https://archlinux.org/download/) 即可。

## 项目结构

```
.
├── arch-install/
│   ├── install.sh            # [VM 内]   自动安装：分区 → 装包 → 配置 → 写引导
│   ├── install.conf.example  # [模板]    安装配置模板（主机名/用户/磁盘/桌面环境…）
│   ├── dev-setup.sh          # [VM 内]   开发环境一键配置（工具链 + 国内镜像源）
│   ├── vm-check.sh           # [VM 内]   健康巡检（系统/服务/网络/桌面/Tools）
│   ├── reset-password.sh     # [VM 内]   忘记密码时经 live 环境 chroot 重置
│   ├── serve.py              # [宿主机]  HTTP 服务：分发脚本 + 接收安装日志
│   ├── check.sh              # [宿主机] 环境自检（11 项）
│   ├── diagnose.sh           # [宿主机] 故障自诊断（逐条检查并给出修复命令）
│   ├── release.sh            # [宿主机] 自动发版（打标签 / 打包 / 建 Release / 上传附件）
│   ├── proxy-forward.py      # [宿主机] 端口转发：让虚拟机复用宿主机的本地代理
│   └── sshkey.pub            # （本地生成，已被 .gitignore 排除）
├── README.md                                # 本文件（简体中文）
├── README.en.md                             # English README
├── CHANGELOG.md                             # 版本变更记录
├── CONTRIBUTING.md                          # 贡献指南与代码规范
├── 使用教程.md                              # 完整操作手册（逐步说明 / 功能演示 / 场景 / FAQ）
├── 虚拟机网络配置.md                         # 虚拟机访问被宿主机屏蔽站点的排查与解法
├── Arch-Linux-ARM-Parallels-安装指南.md     # 手工安装指引（含 archinstall 向导逐步说明）
├── 环境配置与验证清单.md                     # 依赖清单、环境变量、构建调试、验证步骤
├── .github/workflows/ci.yml                 # CI：shellcheck / Python 语法 / Markdown 检查
├── .markdownlint.json                       # Markdown 检查规则
└── .gitignore
```

## 环境要求

| 项目 | 要求 | 检查方式 |
| --- | --- | --- |
| 硬件 | Apple Silicon（M 系列） | `uname -m` 输出 `arm64` |
| 系统 | macOS 13 或更高 | 关于本机 |
| 虚拟机 | Parallels Desktop（在 27.0.1 验证） | 关于 Parallels Desktop |
| Python | 3.9+ | `python3 --version` |
| 磁盘 | 宿主机 ≥ 5 GB；虚拟机 64 GB | `df -h` |

### 下载引导镜像

```bash
cd ~/Downloads
N="archboot-<日期>-aarch64-ARCH-aarch64.iso"    # 文件名见下方说明
curl -fL -o "$N" "https://release.archboot.com/aarch64/latest/iso/$N"
curl -fL -o "$N.sig" "https://release.archboot.com/aarch64/latest/iso/$N.sig"

# 列出最新可用镜像
curl -sL https://release.archboot.com/aarch64/latest/iso/ | grep -oE 'href="[^"]+\.iso"'
```

| 变体 | 体积 | 用途 |
| --- | --- | --- |
| `...-ARCH-aarch64.iso` | ~470 MB | **推荐**，联网安装 |
| `...-ARCH-latest-aarch64.iso` | ~295 MB | 最小化 |
| `...-ARCH-local-aarch64.iso` | ~994 MB | 内置仓库，**可离线安装** |

---

## 安装配置（可选）

`install.sh` 支持通过配置文件定制，**无需修改脚本**。
把 `install.conf.example` 复制为 `/root/install.conf` 并按需修改即可；不提供该文件时全部沿用默认值，行为与旧版本一致。

**可配置项**

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `NEW_HOSTNAME` | `arch-vm` | 主机名 |
| `NEW_TIMEZONE` | `Asia/Shanghai` | 时区 |
| `NEW_LOCALE` | `zh_CN.UTF-8` | 系统语言 |
| `NEW_KEYMAP` | `us` | 键盘布局 |
| `NEW_USER` / `NEW_USER_PW` | `arch` / `arch` | 普通用户（⚠️ 装后请改密码） |
| `NEW_ROOT_PW` | `arch` | root 密码（⚠️ 装后请改密码） |
| `NEW_DESKTOP` | `kde` | **桌面环境**，见下表 |
| `NEW_DISK` | 空 | 目标磁盘；留空 = 自动检测容量最大的磁盘 |
| `NEW_KERNEL` | `linux-aarch64` | 内核包（ARM64 必须此项，勿改成 `linux`） |
| `NEW_CJK` | `yes` | 是否安装中文字体与 fcitx5 输入法 |
| `NEW_MIRROR_CN` | `yes` | 是否优先使用国内镜像（清华 / USTC） |
| `NEW_EXTRA_PKGS` | 空 | 额外软件包，空格分隔，如 `"firefox git htop"` |

**四种桌面环境**

| `NEW_DESKTOP` | 安装内容 | 显示管理器 |
| --- | --- | --- |
| `kde` | KDE Plasma | sddm |
| `gnome` | GNOME | gdm |
| `xfce` | XFCE | lightdm |
| `none` | 纯命令行，不装桌面 | 无 |

---

## 使用教程

### 步骤 1 · 环境自检（1 分钟）

```bash
cd arch-install
bash check.sh
```

检查 11 项：宿主工具、ISO 存在性与 SHA256、虚拟机状态与网卡类型、服务监听与可下载性。
全部 `[PASS]` 后再继续。

### 步骤 2 · 创建虚拟机（仅首次）

```bash
P="/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"
VM="Arch Linux"
ISO="$HOME/Downloads/archboot-<日期>-aarch64-ARCH-aarch64.iso"

"$P" create "$VM" -d manjaro --dst "$HOME/Parallels"
"$P" set "$VM" --cpus 4
"$P" set "$VM" --memsize 8192
"$P" set "$VM" --efi-secure-boot off              # 必须关闭，否则引导被拦截
"$P" set "$VM" --3d-accelerate highest            # 合法值：highest | auto | off
"$P" set "$VM" --device-set net0 --type shared    # 必须 shared，host 无外网
"$P" set "$VM" --device-set cdrom0 --image "$ISO" --connect
"$P" set "$VM" --device-bootorder "cdrom0 hdd0 usb"
```

| 参数 | 为什么这样设 |
| --- | --- |
| `-d manjaro` | Arch 系硬件模板，让 Parallels 生成正确的 ARM64 默认值 |
| `--efi-secure-boot off` | Secure Boot 会拦截未签名的 systemd-boot |
| `--device-set net0 --type shared` | **`host`（Host-Only）没有外网出口**，会导致所有镜像站连不上 |
| `--device-bootorder` | 首次从光盘装；装完改回 `hdd0 cdrom0 usb` |

### 步骤 3 · 启动分发服务（宿主机）

安装时要把脚本送进虚拟机，但有两个硬限制：Parallels 剪贴板互通依赖 Guest Tools
（要等系统装完才能装），且无法向虚拟机 TUI 界面注入按键。
因此采用**宿主机 HTTP 分发 + 虚拟机 curl 拉取**。

```bash
cd arch-install
python3 serve.py

# 或后台常驻
nohup python3 serve.py > server.out 2>&1 &
```

服务只绑定 Parallels 的虚拟网卡（`10.211.55.2` / `10.37.129.2`），**不暴露到你的 WiFi 或局域网**。

### 步骤 4 · 引导进入 live 环境

```bash
"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl" start "Arch Linux"
```

在虚拟机窗口按顺序操作：

1. **GRUB 菜单**：默认高亮第二项，按一次 `↑` 选第一项，回车

   ```
   Launch UEFI Archboot - Arch Linux aarch64     ← 选这个
   *Launch UEFI IPXE Archboot - Arch Linux aarch64
   ```

2. **欢迎界面**：直接按 `CTRL+C` 进 bash（跳过所有菜单）
3. 出现 `root@archboot /]#` 即成功

**进入后先做三项确认**：

```bash
uname -m                          # 必须是 aarch64
ls /sys/firmware/efi/efivars      # 有输出 = UEFI 模式正常
curl -s 10.211.55.2:8000/ping     # 期望输出 ok
```

### 步骤 5 · 执行自动安装

```bash
curl -s 10.211.55.2:8000/i -o /root/i.sh && bash /root/i.sh
```

> **注意写到 `/root/` 而非 `/tmp/`**：Archboot 的 `/tmp` 可能不存在或不可写，
> 会导致 `curl: (23) client returned ERROR on write`。

脚本自动完成 7 个阶段，每步都有 `[arch]` 前缀的进度输出：

```
[0] 环境校验（aarch64 / UEFI）      [1] NTP 同步
[2] 磁盘识别                        [3] 分区（工具降级链 + 数量断言）
[4] 格式化                          [5] 挂载（容量断言）
[6] 镜像源配置                      [7] pacman 密钥环
[8] pacstrap 安装软件包             ← 最耗时，10~30 分钟
[9] 生成 fstab                      [10] chroot 配置（时区/语言/用户/密码/服务）
[11] 安装 systemd-boot 引导         [12-15] 收尾校验
```

**安装期间不要操作虚拟机**：不要按 `CTRL+C`、不要切换控制台（`CTRL+ALT+F1~F9`）、不要关闭窗口。
中断会让 `pacstrap` 收到 SIGPIPE（退出码 141）而失败。

完成标志：

```
[arch] [15] ALL DONE - you may reboot now (remember to disconnect the ISO)
```

### 步骤 6 · 收尾并重启

```bash
# 宿主机：断开 ISO 并把启动顺序切回硬盘
P="/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"
"$P" set "Arch Linux" --device-disconnect cdrom0
"$P" set "Arch Linux" --device-bootorder "hdd0 cdrom0 usb"
```

```bash
# 虚拟机内：重启
umount -R /mnt; sync; reboot
```

重启后进入 **SDDM 登录界面**，登录即可见到 KDE Plasma 桌面。

---

## 关键功能

### 实时监控安装进度（宿主机侧）

脚本每完成一步都把状态回传宿主机，**你不必盯着虚拟机屏幕**：

```bash
tail -f arch-install/log.txt      # 实时跟踪
cat arch-install/log.txt          # 带时间戳的完整记录
cat arch-install/access.log       # 请求来源（确认来自虚拟机而非本机）
```

### SSH 公钥免密登录

**宿主机**先发布公钥：

```bash
cp ~/.ssh/id_ed25519.pub arch-install/sshkey.pub   # 无密钥先 ssh-keygen -t ed25519
```

**虚拟机内**执行一条命令：

```bash
mkdir -p ~/.ssh;chmod 700 ~/.ssh;curl -s 10.211.55.2:8000/k>>~/.ssh/authorized_keys;chmod 600 ~/.ssh/authorized_keys;echo DONE
```

之后即可从宿主机直接登录：

```bash
ssh arch@<虚拟机IP>
```

> 权限必须严格：`~/.ssh` 为 `700`、`authorized_keys` 为 `600`，过宽时 SSH 会静默拒绝。

### 密码重置

改密码必须先证明你知道当前密码，所以忘记密码时只能**脱离系统本身**。本项目把用户操作压缩到一条命令：

```bash
# ① 宿主机挂回 ISO 并切换启动顺序（cdrom0 优先）
# ② 虚拟机重启 → GRUB 选第一项 → CTRL+C 进 bash
# ③ 执行重置（会交互式询问新密码两次）
curl -s 10.211.55.2:8000/r | bash
# ④ 宿主机断开 ISO、启动顺序切回 hdd0，重启
```

脚本**不硬编码任何密码**；也可非交互传入：`NEWPW='新密码' bash /root/r.sh`。

---

## 常见使用场景

### 场景一 · 首次全新安装

```bash
cd arch-install && bash check.sh      # ① 自检
python3 serve.py &                     # ② 起服务
# ③ 创建虚拟机（见步骤 2）
# ④ 启动虚拟机，在 live 环境执行：
#    curl -s 10.211.55.2:8000/i -o /root/i.sh && bash /root/i.sh
# ⑤ 装完 → 断 ISO → 切启动顺序 → 重启
```

预计耗时：下载 ISO 5~20 分钟 + 安装 10~30 分钟。

### 场景二 · 装坏了想重装

脚本是**幂等**的——会自动卸载并抹掉旧分区表重建，直接重跑即可：

```bash
# 重新从 ISO 引导后，在 live 环境执行同一条命令
curl -s 10.211.55.2:8000/i -o /root/i.sh && bash /root/i.sh
```

> ⚠️ 脚本会**清除目标磁盘上的所有数据**。

### 场景三 · 想在虚拟机里当开发机

```bash
sudo pacman -S --needed git curl wget openssh       # 基础工具
sudo pacman -S --needed go python python-pip cmake ninja clang gdb
sudo pacman -S --needed nodejs npm rust
```

国内网络务必配置镜像源：

```bash
go env -w GOPROXY=https://goproxy.cn,direct                                    # Go
npm config set registry https://registry.npmmirror.com                          # npm
mkdir -p ~/.config/pip && printf "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple\n" > ~/.config/pip/pip.conf   # pip
mkdir -p ~/.cargo && printf "[source.crates-io]\nreplace-with = \"ustc\"\n\n[source.ustc]\nregistry = \"sparse+https://mirrors.ustc.edu.cn/crates.io-index/\"\n" > ~/.cargo/config.toml   # Cargo
```

### 场景四 · 宿主机文件夹共享给虚拟机

需安装 **Parallels Tools**（官方不支持 Arch，属社区级支持）：

```bash
# 宿主机：挂载 ARM 版 Tools 镜像
"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl" \
  set "Arch Linux" --device-set cdrom0 \
  --image "/Applications/Parallels Desktop.app/Contents/Resources/Tools/prl-tools-lin-arm.iso" --connect
```

```bash
# 虚拟机内：编译安装
sudo pacman -S --needed dkms linux-aarch64-headers
sudo mkdir -p /mnt/cdrom && sudo mount /dev/sr0 /mnt/cdrom
cd /mnt/cdrom && sudo ./install
sudo reboot
```

装好后在 Parallels「配置 → 共享 → 共享文件夹」添加宿主机目录，虚拟机会出现在 `/mnt/psf/<文件夹名>`。
若 `./install` 失败，改用 AUR 的 `parallels-tools` 包。

---

## 常见问题

### 所有镜像站都连不上（`Failed to connect to server`）

**最可能的原因：虚拟机网卡是 Host-Only 类型。** 这类网络按设计没有外网出口，
但**访问宿主机服务仍然正常**，所以极易误判为"网络没问题"。

```bash
prlctl list -i "Arch Linux" | grep net0          # 检查
prlctl set "Arch Linux" --device-set net0 --type shared   # 修复（支持热切换）
```

> **排查口诀**：能连宿主机、连不上外网 → 先查网卡是不是 `host` 类型。

### `parted: command not found`

**Archboot 精简环境不含 `parted`，也不含 `partprobe`。**
本项目已内置四级降级：`sgdisk → parted → sfdisk → fdisk`，并在日志中回报实际使用的工具。

### `curl: (23) client returned ERROR on write of ... bytes`

Archboot 的 `/tmp` 不可写。报错里出现完整字节数说明**数据已全部收到、仅落盘失败**，
别误判为网络问题。改用 `/root/` 目录即可。

### `Partition /mnt too full` / pacstrap 空间不足

**分区表没有被真正重建**，脚本仍挂载了旧的小分区（常见于此前在 Archboot Setup 向导里分过区）。
本项目已修复：抹掉旧分区表后断言**分区数必须为 2**、`/mnt` **容量必须大于 10 GB**，不满足立即中止。

### 安装完成后无法引导

`bootctl` 在部分环境无法写入 EFI 固件变量。本项目已兜底：把引导器复制到 UEFI 标准回退路径
**`/boot/EFI/BOOT/BOOTAA64.EFI`**（日志显示 `[11] fallback BOOTAA64.EFI copied`）。
仍失败时检查启动顺序应为 `hdd0 cdrom0 usb`。

### 剪贴板不能互通 / 无法复制粘贴

依赖 Guest Tools，需手动安装（见场景四）。装好之前往虚拟机输入命令只能**手打**——
这也是本项目采用 HTTP 分发脚本的原因之一。

### `hostname: command not found`

Arch 的 `base` 包不含它：`sudo pacman -S --needed inetutils`

### 中文显示方块 / 输入法无效

```bash
sudo pacman -S noto-fonts-cjk noto-fonts-emoji    # 字体
# 输入法环境变量写入 ~/.config/environment.d/im.conf 后需「注销并重新登录」
```

### SSH 突然连不上

虚拟机 IP 由 DHCP 分配，重启后可能变化：

```bash
prlctl list -a                       # 查当前 IP
arp -an | grep 10.211.55             # 或扫 ARP 表
nc -z -G 2 <IP> 22 && echo OPEN      # 确认 22 端口
```

### pacman 报 GPG 签名错误

系统时间不准所致：`sudo timedatectl set-ntp true`

> 更多问题（含 `sudo` 密码错误、输入法详细配置等）见 **[使用教程.md](使用教程.md)** 第五节。

---

## 注意事项

### 数据安全

- **脚本会清空目标磁盘**：会卸载该盘所有分区、抹掉分区表并重建。
  只对**专用虚拟机磁盘**使用，不要指向有数据的磁盘。
- 安装前建议在 Parallels 里制作**快照**（推荐时机：live 启动成功、首次进入桌面、Tools 装好后）。

### 凭据安全

- **不要在任何脚本里硬编码真实密码**。本项目的 `reset-password.sh` 通过环境变量或
  `/dev/tty` 交互获取密码，仓库中不含任何密码。
- 上传公开仓库前务必扫描：`git check-ignore -v <文件>`、`git diff --cached | grep -c "<秘密>"`
- 分发服务**仅在安装期间需要**，用完请关闭：`lsof -nP -iTCP:8000 -sTCP:LISTEN` 查进程后 `kill`。

### 平台限制

- 仅适用于 **Apple Silicon**；Parallels 在 Apple Silicon 上**不支持 x86_64 客户机**，无法绕过。
- Arch Linux ARM 与 x86 Arch 有差异：内核包名是 **`linux-aarch64`**（非 `linux`）、
  内核镜像在 **`/boot/Image`**（非 `vmlinuz-linux`）；部分 AUR 包不提供 aarch64 构建。

### 镜像时效

Archboot 镜像**每日更新**，`install.sh` 中的 ISO 文件名与校验值需按实际情况调整。

### 首次登录后的必做事项

1. **修改密码**：`passwd`（当前用户）、`sudo passwd root`
2. 补装常用工具：`sudo pacman -S --needed git curl wget openssh inetutils`
3. 配置 SSH 免密登录，之后即可远程管理

---

## 设计要点

**为什么用「宿主机分发 + 虚拟机拉取」的模式？**

安装时需要往虚拟机投送脚本，但存在两个硬限制：① Parallels 剪贴板互通依赖 Guest Tools，
而 Tools 要等系统装完才能装；② 无法向虚拟机 TUI 安装界面注入按键。
因此由宿主机起一个只绑定 Parallels 虚拟网段的 HTTP 服务，虚拟机用 `curl` 拉取执行，
每步进度通过 `POST /log` 回传，宿主机侧实时可见。

`serve.py` 提供 4 条路由：

| 路由 | 用途 |
| --- | --- |
| `GET /ping` | 连通性探活 |
| `GET /i` | 分发安装脚本 `install.sh` |
| `GET /k` | 分发 SSH 公钥（免密登录） |
| `GET /r` | 分发密码重置脚本 |

**安装脚本内置的鲁棒性设计**

| 机制 | 解决的问题 |
| --- | --- |
| 分区工具四级降级 | Archboot 无 `parted`，工具不能假设存在 |
| 分区数量断言（必须为 2） | 分区命令静默失败后在错误布局上继续安装 |
| 挂载容量断言（> 10 GB） | 误挂载到小分区导致装到一半空间不足 |
| `BOOTAA64.EFI` 兜底 | `bootctl` 无法写 EFI 变量时仍能引导 |
| 内核路径自动探测 | ARM 是 `/boot/Image`，与 x86 不同 |
| 宿主机地址自动探测 | 无需关心虚拟机落在 Shared 还是 Host-Only 网段 |
| `pacstrap` 失败即中止 | 避免在半成品系统上继续跑出误导性的"完成" |

## 文档

| 文档 | 内容 |
| --- | --- |
| **[使用教程.md](使用教程.md)** | 完整操作手册：逐步说明、功能演示、场景示例、12 个 FAQ、注意事项 |
| **[虚拟机网络配置.md](虚拟机网络配置.md)** | 虚拟机访问被宿主机屏蔽站点的排查与解法（含容器 / WSL 通用性说明） |
| **[Arch-Linux-ARM-Parallels-安装指南.md](Arch-Linux-ARM-Parallels-安装指南.md)** | 手工安装指引，含 `archinstall` 向导逐步说明 |
| **[环境配置与验证清单.md](环境配置与验证清单.md)** | 依赖清单、运行时要求、环境变量、构建调试、验证步骤 |
| **[CHANGELOG.md](CHANGELOG.md)** | 版本变更记录（遵循 Keep a Changelog 与语义化版本） |
| **[CONTRIBUTING.md](CONTRIBUTING.md)** | 贡献指南、代码规范与发版流程 |
| **[README.en.md](README.en.md)** | English introduction & usage guide |

## 许可证

[MIT](LICENSE)
