# Mac-Arch-Installer

[![Release](https://img.shields.io/github/v/release/AyaseEli-Bing/Mac-Arch-Installer?label=version&color=blue)](https://github.com/AyaseEli-Bing/Mac-Arch-Installer/releases)
[![License](https://img.shields.io/github/license/AyaseEli-Bing/Mac-Arch-Installer?color=green)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Apple%20Silicon-black)](#requirements)
[![Arch](https://img.shields.io/badge/arch-aarch64-orange)](#why-this-project)
[![Guest OS](https://img.shields.io/badge/guest-Arch%20Linux%20ARM-1793d1)](#why-this-project)

**English** | [简体中文](README.md)

> Install **Arch Linux ARM** on **Apple Silicon Macs** running **Parallels Desktop** — fully automated.

One command handles partitioning, package installation, system configuration, and bootloader setup.
Comes with environment self-check, live install logging, SSH key-based login, and password recovery.

**Keywords:** `arch-linux` · `arch-linux-arm` · `archboot` · `parallels-desktop` · `apple-silicon` · `aarch64` · `arm64` · `virtualization` · `macos` · `installer` · `automation`

---

## Table of Contents

- [Why This Project](#why-this-project)
- [Project Structure](#project-structure)
- [Requirements](#requirements)
- [Usage](#usage)
  - [Step 1 · Environment Self-Check](#step-1--environment-self-check-1-minute)
  - [Step 2 · Create the Virtual Machine](#step-2--create-the-virtual-machine-first-time-only)
  - [Step 3 · Start the Distribution Service](#step-3--start-the-distribution-service-on-the-host)
  - [Step 4 · Boot Into the Live Environment](#step-4--boot-into-the-live-environment)
  - [Step 5 · Run the Automated Install](#step-5--run-the-automated-install)
  - [Step 6 · Finalize and Reboot](#step-6--finalize-and-reboot)
- [Key Features](#key-features)
- [Common Scenarios](#common-scenarios)
- [FAQ](#faq)
- [Notes](#notes)
- [Design Notes](#design-notes)
- [Documentation](#documentation)
- [License](#license)

---

## Why This Project

Parallels Desktop on Apple Silicon can only virtualize **ARM64** guests, while the official Arch Linux ISO ships **x86_64 only** — so the official image simply **will not boot**.

This toolkit is built on [Archboot](https://archboot.com)'s aarch64 image, which the [ArchWiki](https://wiki.archlinux.org/title/Parallels_Desktop) explicitly recommends for Parallels on Apple Silicon, and automates the entire installation.

> **Not for Intel Macs** — x86_64 Macs can virtualize native x86_64 guests, so just use the [official ISO](https://archlinux.org/download/).

## Project Structure

```
.
├── arch-install/
│   ├── install.sh            # Runs inside the VM: partitioning → packages → config → bootloader
│   ├── serve.py              # Host-side HTTP service: distributes scripts, collects logs
│   ├── reset-password.sh     # Password recovery via live-environment chroot
│   ├── check.sh              # Host-side environment self-check
│   ├── proxy-forward.py      # Port forwarder: lets the VM reuse the host's local proxy
│   └── sshkey.pub            # (generated locally, excluded by .gitignore)
├── 使用教程.md                              # Usage tutorial (Chinese)
├── 虚拟机网络配置.md                         # VM network troubleshooting (Chinese)
├── Arch-Linux-ARM-Parallels-安装指南.md     # Manual install guide (Chinese)
├── 环境配置与验证清单.md                     # Environment & verification checklist (Chinese)
└── .gitignore
```

> Documentation is currently in Chinese. This English README covers the full workflow.

## Requirements

| Item | Requirement | How to check |
| --- | --- | --- |
| Hardware | Apple Silicon (M-series) | `uname -m` prints `arm64` |
| OS | macOS 13 or later | About This Mac |
| Virtualization | Parallels Desktop (verified on 27.0.1) | About Parallels Desktop |
| Python | 3.9+ | `python3 --version` |
| Disk | Host ≥ 5 GB; VM 64 GB | `df -h` |

### Download the Boot Image

```bash
cd ~/Downloads
N="archboot-<date>-aarch64-ARCH-aarch64.iso"    # see the list below for the exact name
curl -fL -o "$N" "https://release.archboot.com/aarch64/latest/iso/$N"
curl -fL -o "$N.sig" "https://release.archboot.com/aarch64/latest/iso/$N.sig"

# List available images
curl -sL https://release.archboot.com/aarch64/latest/iso/ | grep -oE 'href="[^"]+\.iso"'
```

| Variant | Size | Purpose |
| --- | --- | --- |
| `...-ARCH-aarch64.iso` | ~470 MB | **Recommended**, installs online |
| `...-ARCH-latest-aarch64.iso` | ~295 MB | Minimal |
| `...-ARCH-local-aarch64.iso` | ~994 MB | Bundled repo, **fully offline install** |

---

## Usage

### Step 1 · Environment Self-Check (1 minute)

```bash
cd arch-install
bash check.sh
```

Verifies 11 items: host tools, ISO presence and SHA256, VM state and network adapter type,
service listening status and script availability. Proceed only when everything is `[PASS]`.

### Step 2 · Create the Virtual Machine (first time only)

```bash
P="/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"
VM="Arch Linux"
ISO="$HOME/Downloads/archboot-<date>-aarch64-ARCH-aarch64.iso"

"$P" create "$VM" -d manjaro --dst "$HOME/Parallels"
"$P" set "$VM" --cpus 4
"$P" set "$VM" --memsize 8192
"$P" set "$VM" --efi-secure-boot off              # must be off, otherwise boot is blocked
"$P" set "$VM" --3d-accelerate highest            # valid: highest | auto | off
"$P" set "$VM" --device-set net0 --type shared    # must be shared; host has no internet
"$P" set "$VM" --device-set cdrom0 --image "$ISO" --connect
"$P" set "$VM" --device-bootorder "cdrom0 hdd0 usb"
```

| Parameter | Why |
| --- | --- |
| `-d manjaro` | Arch-family template → correct ARM64 virtual hardware defaults |
| `--efi-secure-boot off` | Secure Boot blocks the unsigned systemd-boot |
| `--device-set net0 --type shared` | **`host` (Host-Only) has no outbound internet** — every mirror will fail |
| `--device-bootorder` | Boot from CD for install; switch back to `hdd0 cdrom0 usb` afterwards |

### Step 3 · Start the Distribution Service (on the host)

Two hard constraints when pushing scripts into the VM:

1. Parallels clipboard sharing requires Guest Tools (installable only *after* the OS is installed)
2. There is no way to inject keystrokes into the VM's TUI installer

Hence the **host HTTP distribution + VM curl pull** model:

```bash
cd arch-install
python3 serve.py

# Or run detached
nohup python3 serve.py > server.out 2>&1 &
```

The service binds only to Parallels' virtual adapters (`10.211.55.2` / `10.37.129.2`) and is
**not exposed to your Wi-Fi or LAN**.

### Step 4 · Boot Into the Live Environment

```bash
"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl" start "Arch Linux"
```

In the VM window:

1. **GRUB menu** — the second entry is highlighted by default; press `↑` once to select the first:

   ```
   Launch UEFI Archboot - Arch Linux aarch64     ← select this
   *Launch UEFI IPXE Archboot - Arch Linux aarch64
   ```

2. **Welcome screen** — press `CTRL+C` to drop straight into bash
3. You should now see `root@archboot /]#`

**Three checks before continuing:**

```bash
uname -m                          # must print aarch64
ls /sys/firmware/efi/efivars      # any output means UEFI mode is active
curl -s 10.211.55.2:8000/ping     # expect: ok
```

### Step 5 · Run the Automated Install

```bash
curl -s 10.211.55.2:8000/i -o /root/i.sh && bash /root/i.sh
```

> **Write to `/root/`, not `/tmp/`** — Archboot's `/tmp` may be missing or read-only,
> which produces `curl: (23) client returned ERROR on write`.

The script runs seven stages, printing `[arch]`-prefixed progress:

```
[0]  Environment validation (aarch64 / UEFI)   [1]  NTP sync
[2]  Disk detection                            [3]  Partitioning (fallback chain + assertions)
[4]  Formatting                                [5]  Mounting (capacity assertion)
[6]  Mirror configuration                      [7]  pacman keyring
[8]  pacstrap (packages)                       ← longest stage, 10–30 minutes
[9]  fstab generation                          [10] chroot configuration
[11] systemd-boot installation                 [12-15] Final checks
```

**Do not touch the VM during installation** — no `CTRL+C`, no console switching
(`CTRL+ALT+F1~F9`), no closing the window. Interrupting sends SIGPIPE to `pacstrap` (exit code 141).

Completion marker:

```
[arch] [15] ALL DONE - you may reboot now (remember to disconnect the ISO)
```

### Step 6 · Finalize and Reboot

```bash
# On the host: detach the ISO and restore disk-first boot order
P="/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"
"$P" set "Arch Linux" --device-disconnect cdrom0
"$P" set "Arch Linux" --device-bootorder "hdd0 cdrom0 usb"
```

```bash
# Inside the VM
umount -R /mnt; sync; reboot
```

You will land on the **SDDM login screen**; logging in brings up the KDE Plasma desktop.

---

## Key Features

### Live Install Monitoring (host side)

The script reports every step back to the host, so **you don't have to watch the VM screen**:

```bash
tail -f arch-install/log.txt      # live progress
cat arch-install/log.txt          # full record with timestamps
cat arch-install/access.log       # request origins (confirm they come from the VM)
```

### SSH Key-Based Login

On the **host**:

```bash
cp ~/.ssh/id_ed25519.pub arch-install/sshkey.pub   # ssh-keygen -t ed25519 if you have no key
```

Inside the **VM**, one command:

```bash
mkdir -p ~/.ssh;chmod 700 ~/.ssh;curl -s 10.211.55.2:8000/k>>~/.ssh/authorized_keys;chmod 600 ~/.ssh/authorized_keys;echo DONE
```

Then log in from the host:

```bash
ssh arch@<VM_IP>
```

> Permissions matter: `~/.ssh` must be `700` and `authorized_keys` must be `600`.
> SSH silently refuses files with looser permissions.

### Password Recovery

Changing a password requires proving you know the current one, so a forgotten password means
**leaving the system entirely**. This project reduces that to a single command:

```bash
# 1. Attach the ISO on the host and set boot order to cdrom0 first
# 2. Reboot the VM → pick the first GRUB entry → CTRL+C into bash
# 3. Run the reset (prompts for the new password twice)
curl -s 10.211.55.2:8000/r | bash
# 4. Detach the ISO, restore hdd0 boot order, reboot
```

The script **hardcodes no password**; it can also take one non-interactively:
`NEWPW='your-password' bash /root/r.sh`.

---

## Common Scenarios

### Scenario 1 · First-Time Install

```bash
cd arch-install && bash check.sh      # 1. self-check
python3 serve.py &                     # 2. start the service
# 3. create the VM (see Step 2)
# 4. boot it and run inside the live environment:
#    curl -s 10.211.55.2:8000/i -o /root/i.sh && bash /root/i.sh
# 5. detach ISO → restore boot order → reboot
```

Typical timing: ISO download 5–20 min + installation 10–30 min.

### Scenario 2 · Reinstall After a Broken Setup

The script is **idempotent** — it unmounts and wipes the old partition table before recreating,
so simply run it again:

```bash
# Boot from the ISO again, then in the live environment:
curl -s 10.211.55.2:8000/i -o /root/i.sh && bash /root/i.sh
```

> ⚠️ The script **erases all data** on the target disk.

### Scenario 3 · Use the VM as a Development Machine

```bash
sudo pacman -S --needed git curl wget openssh       # basics
sudo pacman -S --needed go python python-pip cmake ninja clang gdb
sudo pacman -S --needed nodejs npm rust
```

Configure regional mirrors (essential outside the US/EU):

```bash
go env -w GOPROXY=https://goproxy.cn,direct                                    # Go
npm config set registry https://registry.npmmirror.com                          # npm
mkdir -p ~/.config/pip && printf "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple\n" > ~/.config/pip/pip.conf   # pip
mkdir -p ~/.cargo && printf "[source.crates-io]\nreplace-with = \"ustc\"\n\n[source.ustc]\nregistry = \"sparse+https://mirrors.ustc.edu.cn/crates.io-index/\"\n" > ~/.cargo/config.toml   # Cargo
```

### Scenario 4 · Share Host Folders With the VM

Requires **Parallels Tools** (officially unsupported on Arch; community-level support):

```bash
# On the host: attach the ARM build of Parallels Tools
"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl" \
  set "Arch Linux" --device-set cdrom0 \
  --image "/Applications/Parallels Desktop.app/Contents/Resources/Tools/prl-tools-lin-arm.iso" --connect
```

```bash
# Inside the VM: compile and install
sudo pacman -S --needed dkms linux-aarch64-headers
sudo mkdir -p /mnt/cdrom && sudo mount /dev/sr0 /mnt/cdrom
cd /mnt/cdrom && sudo ./install
sudo reboot
```

Then add host directories under Parallels' *Configure → Sharing → Shared Folders*;
they appear inside the VM at `/mnt/psf/<folder-name>`.

If `./install` fails, use the AUR package `parallels-tools` instead.

---

## FAQ

### Every mirror fails with `Failed to connect to server`

**Most likely the VM's adapter is Host-Only.** Such networks have **no outbound internet by design**,
yet **hosting services remain reachable** — which makes it very easy to misdiagnose.

```bash
prlctl list -i "Arch Linux" | grep net0                    # inspect
prlctl set "Arch Linux" --device-set net0 --type shared    # fix (hot-swappable)
```

> **Rule of thumb:** host reachable but internet unreachable → check whether the adapter is `host`.

### `parted: command not found`

Archboot's minimal environment ships **neither `parted` nor `partprobe`**.
This project implements a four-level fallback: `sgdisk → parted → sfdisk → fdisk`,
and reports which tool was actually used.

### `curl: (23) client returned ERROR on write of ... bytes`

Archboot's `/tmp` is not writable. The full byte count in the error means **the data arrived fine and
only the write failed** — don't mistake it for a network problem. Write to `/root/` instead.

### `Partition /mnt too full` / pacstrap runs out of space

**The partition table was not actually recreated**, so the script mounted an old, small partition
(typically left over from a previous run of Archboot's Setup wizard).
Fixed in this project: the old table is wiped, then asserted — **partition count must be 2** and
**`/mnt` must exceed 10 GB**, otherwise the script aborts immediately.

### The installed system won't boot

`bootctl` can fail to write EFI firmware variables in some environments.
This project works around it by copying the bootloader to the UEFI fallback path
**`/boot/EFI/BOOT/BOOTAA64.EFI`** (logged as `[11] fallback BOOTAA64.EFI copied`).
If it still fails, verify the boot order is `hdd0 cdrom0 usb`.

### Clipboard sharing doesn't work

It depends on Guest Tools, which must be installed manually (see Scenario 4).
Until then, commands typed into the VM must be **entered by hand** — one reason this project
uses HTTP script distribution, reducing manual typing to a single `curl` command.

### `hostname: command not found`

Arch's `base` group doesn't include it: `sudo pacman -S --needed inetutils`

### Chinese characters render as boxes / IME doesn't work

```bash
sudo pacman -S noto-fonts-cjk noto-fonts-emoji    # fonts
# IME environment variables go in ~/.config/environment.d/im.conf — then log out and back in
```

### SSH suddenly stops connecting

The VM's IP is DHCP-assigned and may change after a reboot:

```bash
prlctl list -a                       # current IP
arp -an | grep 10.211.55             # or scan the ARP table
nc -z -G 2 <IP> 22 && echo OPEN      # confirm port 22
```

### pacman reports GPG signature errors

Usually a clock skew issue: `sudo timedatectl set-ntp true`

---

## Notes

### Data Safety

- **The script erases the target disk** — it unmounts every partition on that disk, wipes the
  partition table, and recreates it. Only use it with a **dedicated VM disk**.
- Take a **snapshot** in Parallels before installing (recommended points: after the live
  environment boots, after first login, after Tools are installed).

### Credential Safety

- **Never hardcode real passwords in scripts.** `reset-password.sh` reads the password from an
  environment variable or `/dev/tty`; the repository contains no passwords.
- Scan before pushing to a public repo:
  `git check-ignore -v <file>` and `git diff --cached | grep -c "<secret>"`
- The distribution service is only needed **during installation**; stop it afterwards:
  `lsof -nP -iTCP:8000 -sTCP:LISTEN` then `kill` the PID.

### Platform Limits

- **Apple Silicon only.** Parallels on Apple Silicon **cannot run x86_64 guests** — there is no way around this.
- Arch Linux ARM differs from x86 Arch: the kernel package is **`linux-aarch64`** (not `linux`),
  the kernel image lives at **`/boot/Image`** (not `vmlinuz-linux`), and some AUR packages
  have no aarch64 build.

### Image Freshness

Archboot images are **updated daily**; the ISO filename and checksum in `install.sh` must be
adjusted accordingly.

### After First Login

1. **Change passwords**: `passwd` (your user), `sudo passwd root` (root)
2. Install common tools: `sudo pacman -S --needed git curl wget openssh inetutils`
3. Set up SSH key login, then manage the VM remotely

---

## Design Notes

**Why the "host distributes, VM pulls" model?**

Pushing scripts into the VM hits two hard limits: Parallels clipboard sharing needs Guest Tools
(available only after the OS is installed), and there is no way to inject keystrokes into the
TUI installer. So the host runs an HTTP service bound to the Parallels virtual subnet, the VM
pulls scripts with `curl`, and each step posts its status back — visible on the host in real time.

`serve.py` exposes four routes:

| Route | Purpose |
| --- | --- |
| `GET /ping` | Connectivity probe |
| `GET /i` | Distribute `install.sh` |
| `GET /k` | Distribute the SSH public key |
| `GET /r` | Distribute the password-reset script |

**Robustness built into the installer**

| Mechanism | Problem it solves |
| --- | --- |
| Four-level partition tool fallback | Archboot has no `parted`; tools cannot be assumed present |
| Partition count assertion (must be 2) | Silent partitioning failure would install onto a wrong layout |
| Mount capacity assertion (> 10 GB) | Mounting a small partition runs out of space mid-install |
| `BOOTAA64.EFI` fallback | `bootctl` cannot always write EFI variables |
| Kernel path auto-detection | ARM uses `/boot/Image`, unlike x86 |
| Host address auto-detection | No need to know whether the VM is on Shared or Host-Only |
| Abort on pacstrap failure | Prevents a misleading "done" on a half-installed system |

## Documentation

| Document | Contents |
| --- | --- |
| **[使用教程.md](使用教程.md)** | Full manual: step-by-step, feature demos, scenarios, 12 FAQs (Chinese) |
| **[虚拟机网络配置.md](虚拟机网络配置.md)** | Diagnosing VM access to host-blocked sites; applies to Docker/WSL too (Chinese) |
| **[Arch-Linux-ARM-Parallels-安装指南.md](Arch-Linux-ARM-Parallels-安装指南.md)** | Manual install guide with `archinstall` walkthrough (Chinese) |
| **[环境配置与验证清单.md](环境配置与验证清单.md)** | Dependencies, runtime requirements, env vars, build & debug, verification (Chinese) |

## License

[MIT](LICENSE)
