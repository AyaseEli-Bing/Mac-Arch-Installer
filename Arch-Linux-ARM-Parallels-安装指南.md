# 在 Parallels Desktop 上安装 Arch Linux ARM（Apple M4）

> 环境：macOS 26 (Darwin 27.0) · Apple M4 (arm64) · Parallels Desktop 27.0.1
> 生成时间：2026-09-21

---

## 0. 为什么不能直接用官方 Arch ISO

Arch Linux 官方 ISO 只发布 **x86_64** 版本。Apple Silicon 上的 Parallels 只能原生虚拟化
**ARM64 (aarch64)** 客户机，因此官方 ISO 无法启动。

正确路线（ArchWiki 明确推荐）：使用 **Archboot 的 aarch64 ISO**。Archboot 由 Arch Linux
开发者 Tobias Powalowski 维护，本质是一个带完整 Arch 安装工具链的 ARM64 live 环境，
官方 wiki 的 [Parallels Desktop](https://wiki.archlinux.org/title/Parallels_Desktop) 条目
已将其列为 Apple Silicon 上的推荐方案。

---

## 1. 已完成的环境准备

以下由助手在宿主机上自动完成，无需重复操作：

| 项目 | 状态 |
| --- | --- |
| Archboot aarch64 ISO 下载 | `~/Downloads/archboot-2026.09.21-02.26-7.2.6-1-aarch64-ARCH-aarch64.iso`（469 MB）<br>SHA256: `00e54a62f5e367ce320b053b2715e6cd33d66d34c51091b06c74f189902fc181` |
| GPG 签名文件 | 同名 `.sig`（已下载） |
| 虚拟机创建 | `~/Parallels/Arch Linux.pvm`，OS profile = **manjaro**（Arch 系，硬件默认值正确） |
| CPU | 4 核 |
| 内存 | 8 GB |
| 硬盘 | 64 GB，SATA，动态扩容 |
| 网卡 | virtio，共享网络（NAT） |
| 显卡 | virtio，3D 加速 = highest |
| 固件 | ARM64 EFI，Secure Boot = **off** |
| 光驱 | 已挂载 Archboot ISO，启动顺序 cdrom0 优先 |

> 说明：选择 `manjaro` profile 是为了让 Parallels 生成正确的 ARM64 虚拟硬件默认值。
> 这只是硬件模板，实际安装的仍然是纯 Arch Linux ARM。

### 1.1 校验 ISO 签名（可选，推荐）

Archboot 镜像由 Arch Linux 开发者 Tobias Powalowski 签名，其公钥指纹为
`5B7E 3FB7 1B7F 1032 9A1C 03AB 771D F662 7EDF 681F`。

```bash
cd ~/Downloads
N=archboot-2026.09.21-02.26-7.2.6-1-aarch64-ARCH-aarch64.iso

# 导入并核对公钥指纹
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 5B7E3FB71B7F10329A1C03AB771DF6627EDF681F
gpg --fingerprint 5B7E3FB71B7F10329A1C03AB771DF6627EDF681F

# 验证签名（必须看到 Good signature）
gpg --verify "$N.sig" "$N"

# 对照 SHA256
shasum -a 256 "$N"
# 期望：00e54a62f5e367ce320b053b2715e6cd33d66d34c51091b06c74f189902fc181
```

若指纹不匹配或签名验证失败，**不要继续安装**，重新下载镜像。

---

## 2. 启动虚拟机并进入 live 环境

```bash
# 宿主机执行
"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl" start "Arch Linux"
```

或在 Parallels Desktop 图形界面中选中 "Arch Linux" 点启动。

首次启动会从 ISO 引导，进入 Archboot live 环境，自动以 **root** 登录。

### 2.1 确认关键前提

进入 live 环境后，依次确认以下三项，任一不符都不要继续：

```bash
# 1. 确认架构是 aarch64（必须）
uname -m
# 期望输出：aarch64

# 2. 确认 UEFI 模式（目录存在即正确）
ls /sys/firmware/efi/efivars

# 3. 确认网络连通（archinstall 需要联网下载软件包）
ping -c 3 archlinux.org
```

若第 3 项不通：

```bash
# 查看网卡名（通常是 enp0s5 或 eth0）
ip link
# virtio + 共享网络应自动 DHCP；未获取地址时重启网络服务
systemctl restart systemd-networkd
```

### 2.2 同步系统时钟（重要）

时间不准会导致 pacman 校验 GPG 签名失败：

```bash
timedatectl set-ntp true
timedatectl status
```

---

## 3. 使用 archinstall 安装（推荐新手）

Archboot live 环境内置 Arch 官方的 `archinstall` 引导式安装器，是文本图形界面（TUI），
用方向键 + 回车操作，比手工分区可靠得多。

```bash
archinstall
```

### 3.1 向导各步骤的选择

| 步骤 | 选择 | 说明 |
| --- | --- | --- |
| Archinstall language | `English`（界面语言，不影响系统） | 中文界面翻译不完整，建议英文 |
| Locales - Keyboard layout | `us` | 物理键盘布局 |
| Locales - Locale language | `zh_CN` | 系统语言 |
| Locales - Locale encoding | `UTF-8` | |
| Mirror - Mirror region | `China` | 决定下载速度 |
| Disk configuration | `Use a best-effort default partition layout` | 新手推荐 |
| 选择磁盘 | `/dev/sda`（64 GB 那个） | **注意**：不要选到 ISO 设备 |
| 文件系统 | `ext4` | 稳定；btrfs 功能多但对新手不必要 |
| 是否要 swap | 选 `Yes`（或按需求） | 8 GB 内存建议加 2–4 GB swap |
| Bootloader | **`systemd-boot`** | ARM64 + UEFI 的标准选择 |
| Unified kernel images | `no` | |
| Kernel | **`linux-aarch64`** | ⚠️ **必须选这个名字**，不要选 `linux` |
| Hostname | 自定义，如 `arch-vm` | |
| Root password | 设置并记住 | |
| User account | 新建普通用户，勾选 `sudo` 权限 | 不要直接用 root 日常登录 |
| Profile - Type | `Desktop` | |
| Profile - Desktop environment | **`kde` (KDE Plasma)** | |
| Profile - Graphics driver | `All open-source` | 虚拟机无独显，开源驱动即可 |
| Audio | `pipewire` | |
| Network configuration | `NetworkManager` | 图形桌面需要它管理网络 |
| Additional packages | 追加：`noto-fonts-cjk fcitx5 fcitx5-chinese-addons fcitx5-configtool kate konsole dolphin` | 中文字体与输入法 |
| Timezone | `Asia/Shanghai` | |
| Automatic time sync (NTP) | `Yes` | |

确认无误后选择 **Install**，等待下载安装完成（视网络约 10–30 分钟）。

> **重要**：安装完成后，向导会询问是否 `chroot` 进入新系统做后续配置，
> 选 **No**，直接重启即可。

### 3.2 重启

```bash
reboot
```

在 Parallels 菜单中执行 **操作 → 停止 → 光盘/DVD** 弹出 ISO，避免再次从光驱启动；
或在重启前于宿主机执行：

```bash
"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl" set "Arch Linux" --device-disconnect cdrom0
```

---

## 4. 首次启动后的必要配置

用普通用户登录，打开 Konsole 终端。

### 4.1 更新系统并确认内核

```bash
uname -r          # 应包含 aarch64
sudo pacman -Syu
```

### 4.2 若安装时漏装中文字体或输入法

```bash
sudo pacman -S noto-fonts-cjk noto-fonts-emoji fcitx5 fcitx5-chinese-addons fcitx5-configtool
```

在 `~/.config/environment.d/im.conf`（不存在则创建）中加入：

```
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
```

注销重新登录后生效。

### 4.3 安装 AUR 助手（可选）

```bash
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay.git
cd yay && makepkg -si
cd .. && rm -rf yay
```

---

## 5. 安装 Parallels Tools

Parallels Tools 提供剪贴板共享、共享文件夹、随窗口自动调整分辨率。
**注意**：Parallels 官方不为 Arch 提供测试过的包，属社区支持范围。

1. 菜单：**设备 → CD/DVD → 连接镜像**，或在 Parallels 主菜单选 **安装 Parallels Tools**
2. 虚拟机内挂载并安装：

```bash
sudo pacman -S dkms linux-aarch64-headers        # 编译内核模块必需
sudo mkdir -p /mnt/cdrom
sudo mount /dev/cdrom /mnt/cdrom
cd /mnt/cdrom
sudo ./install
sudo reboot
```

若 `./install` 报错退出，可先查看日志 `/var/log/parallels-tools-install.log`。

### 5.1 不装 Parallels Tools 也能用的部分

`linux-aarch64` 内核自带 virtio 驱动，以下功能**开箱即用**，无需 Tools：

- 网络（virtio-net）
- 显示输出（virtio-gpu）
- 键盘鼠标

需要 Tools 才有的：剪贴板互通、macOS 文件夹共享、窗口自适应分辨率。

---

## 6. 故障排查

| 现象 | 原因与处理 |
| --- | --- |
| 启动后进入 EFI Shell / 报 no OS | ISO 未正确连接，或启动顺序不是 cdrom0 优先。检查 `prlctl list -i "Arch Linux"` 的 Boot order |
| `uname -m` 不是 aarch64 | 用错了 x86_64 ISO，重新下载 aarch64 版 |
| pacman 报 GPG 签名错误 | 系统时间不准，执行 `timedatectl set-ntp true` |
| 装完重启黑屏 | 未弹出 ISO 或 boot order 未切回 hdd0；确认 systemd-boot 已安装：`bootctl status` |
| Plasma 中文显示方块 | 缺 `noto-fonts-cjk`，见 4.2 |
| 桌面卡顿 | Parallels 在 Apple Silicon 上 3D 加速有限。可在 Plasma 设置 → 外观 → 动画速度调为"瞬间"，或关闭桌面特效 |
| 分辨率不随窗口变化 | 需安装 Parallels Tools，见第 5 节 |

---

## 7. 快照建议

在以下节点用 Parallels 的 **快照** 功能各存一份，出问题可秒回退：

1. live 环境首次启动成功时
2. archinstall 安装完成、首次进入桌面时
3. Parallels Tools 安装成功后

---

## 附：宿主机常用管理命令

```bash
P="/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"

"$P" list -a                        # 列出所有虚拟机
"$P" start "Arch Linux"             # 启动
"$P" stop "Arch Linux" --kill       # 强制停止
"$P" list -i "Arch Linux"           # 查看详细配置
"$P" snapshot-list "Arch Linux"     # 列出快照
"$P" snapshot-switch "Arch Linux" -i <id>   # 回退到某快照
```

> 注意：本助手所用终端的 PATH 不含 Parallels 工具目录，需使用上述绝对路径调用。
