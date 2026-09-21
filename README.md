# Mac 虚拟机安装 Arch Linux 懒人包

在 **Apple Silicon Mac** 上用 **Parallels Desktop** 安装 **Arch Linux ARM** 的自动化工具包。

## 为什么需要这个包

Apple Silicon 上的 Parallels 只能虚拟化 **ARM64** 客户机，而 Arch Linux 官方 ISO 仅有 **x86_64** 版本——直接下载官方镜像根本无法启动。

本工具包基于 [Archboot](https://archboot.com) 的 aarch64 镜像（ArchWiki 对此有[明确推荐](https://wiki.archlinux.org/title/Parallels_Desktop)），把整个安装过程自动化。

## 项目结构

```
.
├── arch-install/
│   ├── install.sh            # 在 Arch VM 内执行：分区 → 装包 → 配置 → 写引导
│   ├── serve.py              # 宿主机 HTTP 服务：分发脚本 + 接收安装日志
│   ├── reset-password.sh     # 忘记密码时用 live 环境 chroot 重置（需自行提供新密码）
│   ├── check.sh              # 环境自检脚本（宿主机侧一键体检）
│   └── sshkey.pub            # （本地生成，已被 .gitignore 排除）
├── Arch-Linux-ARM-Parallels-安装指南.md   # 手工安装指引（含 archinstall 向导逐步说明）
├── 环境配置与验证清单.md                   # 依赖清单、环境变量、构建调试、验证步骤
└── .gitignore
```

## 设计要点

**为什么用「宿主机分发 + 虚拟机拉取」的模式？**

安装时需要往虚拟机里投送脚本，但存在两个硬限制：
1. Parallels 的剪贴板互通需要 Guest Tools，而 Tools 要等系统装完才能装
2. 无法向虚拟机的 TUI 安装界面注入按键

因此由宿主机起一个只绑定在 Parallels 虚拟网段的 HTTP 服务，虚拟机用 `curl` 拉取脚本执行，每步进度通过 `POST /log` 回传，宿主机侧可实时监控。

`serve.py` 提供 4 条路由：

| 路由 | 用途 |
| --- | --- |
| `GET /ping` | 连通性探活 |
| `GET /i` | 分发安装脚本 `install.sh` |
| `GET /k` | 分发 SSH 公钥（用于免密登录） |
| `GET /r` | 分发密码重置脚本 |

## 快速开始

```bash
# 宿主机：环境自检
cd arch-install && bash check.sh

# 宿主机：启动分发服务
python3 serve.py

# 虚拟机（Archboot live 环境）中执行
curl -s 10.211.55.2:8000/i -o /root/i.sh && bash /root/i.sh
```

详细步骤见 **[Arch-Linux-ARM-Parallels-安装指南.md](Arch-Linux-ARM-Parallels-安装指南.md)**，
环境依赖与验证方法见 **[环境配置与验证清单.md](环境配置与验证清单.md)**。

## 踩过的坑（本项目已内置处理）

| 问题 | 现象 | 处理 |
| --- | --- | --- |
| 网卡类型为 Host-Only | 能连宿主机、但所有镜像站都连不上 | 必须 `type=shared`（带 NAT） |
| Archboot 无 `parted` | `parted: command not found`，分区静默失败 | 四级降级：sgdisk → parted → sfdisk → fdisk |
| `/tmp` 不可写 | `curl: (23) client returned ERROR on write` | 改写 `/root/` |
| 内核镜像路径不同 | 引导项写错导致起不来 | ARM 是 `/boot/Image`，非 x86 的 `vmlinuz-linux` |
| `bootctl` 无法写 EFI 变量 | 固件找不到启动项 | 兜底复制 `BOOTAA64.EFI` 到 EFI 默认路径 |

## 已知限制

- 仅适用于 **Apple Silicon（arm64）** 的 Parallels Desktop；Intel Mac 请直接用官方 x86_64 ISO
- Archboot 镜像更新频繁，`install.sh` 中的 ISO 文件名与校验值需按实际情况调整
- Parallels Tools 官方不支持 Arch，属社区级支持

## 许可证

[MIT](LICENSE)
