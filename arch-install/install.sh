#!/bin/bash
# ============================================================
# Arch Linux ARM 自动安装脚本
# 目标：Parallels Desktop on Apple Silicon (ARM64 / UEFI)
# 用法：在 Archboot live 环境的 root shell 中执行本脚本
# ============================================================

# 自动探测宿主机在 Parallels 虚拟网段中的地址（Shared / Host-Only 任一）
HOST_IP=""
for ip in 10.211.55.2 10.37.129.2; do
    if curl -s -m 3 "http://$ip:8000/ping" 2>/dev/null | grep -q "ok"; then
        HOST_IP="$ip"
        break
    fi
done
[ -z "$HOST_IP" ] && HOST_IP="10.211.55.2"
HOST_URL="http://$HOST_IP:8000"
echo "[arch] host detected at $HOST_IP"

# 日志函数：同时打印到屏幕并回传宿主机
r() {
    echo "[arch] $1"
    curl -s -m 10 -X POST -d "$1" "$HOST_URL/log" >/dev/null 2>&1
}

# ---------- 0. 环境检查 ----------
r "[0] script started"
ARCH=$(uname -m)
r "[0] architecture=$ARCH"
if [ "$ARCH" != "aarch64" ]; then
    r "[FATAL] not aarch64, abort"
    exit 1
fi
if [ ! -d /sys/firmware/efi ]; then
    r "[FATAL] not booted in UEFI mode, abort"
    exit 1
fi
r "[0] UEFI OK"

# ---------- 1. 时钟同步 ----------
timedatectl set-ntp true >/dev/null 2>&1
r "[1] ntp synced: $(date '+%F %T')"

# ---------- 2. 自动识别目标磁盘 ----------
# 排除光驱(rom)与分区(part)，取容量最大的磁盘
DISK=$(lsblk -ndo NAME,SIZE,TYPE 2>/dev/null | awk '$3=="disk"' | sort -k2 -h | tail -1 | awk '{print "/dev/"$1}')
r "[2] target disk = $DISK  ($(lsblk -ndo SIZE "$DISK" 2>/dev/null))"
if [ -z "$DISK" ] || [ ! -b "$DISK" ]; then
    r "[FATAL] cannot detect target disk, abort"
    exit 1
fi

# 分区名后缀（nvme 需要 p）
case "$DISK" in
    *nvme*) SUF="p" ;;
    *)      SUF=""  ;;
esac
EFI_PART="${DISK}${SUF}1"
ROOT_PART="${DISK}${SUF}2"

# ---------- 3. 清理旧分区并重建分区表 ----------
umount -R /mnt >/dev/null 2>&1
# 卸载该磁盘上所有已挂载的分区、关闭其 swap（Archboot Setup 可能已建立多分区布局并挂载）
for part in $(lsblk -lno NAME "$DISK" 2>/dev/null | tail -n +2); do
    umount "/dev/$part" >/dev/null 2>&1
    swapoff "/dev/$part" >/dev/null 2>&1
done
swapoff -a >/dev/null 2>&1
sleep 1
r "[3] old layout: $(lsblk -lno NAME "$DISK" 2>/dev/null | tail -n +2 | tr '\n' ' ')"

# 探测本环境可用的分区工具（Archboot 精简环境可能缺 parted）
TOOLS=""
for c in sgdisk parted sfdisk fdisk cfdisk gdisk wipefs mkfs.ext4 mkfs.fat mkfs.vfat partprobe partx blockdev; do
    command -v "$c" >/dev/null 2>&1 && TOOLS="$TOOLS $c"
done
r "[3] available tools:$TOOLS"

# 抹掉旧分区表（GPT 主表 + 备份表）与残留文件系统签名
dd if=/dev/zero of="$DISK" bs=1M count=32 conv=notrunc >/dev/null 2>&1
command -v wipefs >/dev/null 2>&1 && wipefs -a "$DISK" >/dev/null 2>&1

# 按可用性逐级降级：sgdisk → parted → sfdisk → fdisk
PART_TOOL=""
if command -v sgdisk >/dev/null 2>&1; then
    sgdisk -Z "$DISK" >>/tmp/part.log 2>&1
    sgdisk -n 1:1MiB:513MiB -t 1:ef00 "$DISK" >>/tmp/part.log 2>&1 && \
    sgdisk -n 2:513MiB:0 -t 2:8300 "$DISK" >>/tmp/part.log 2>&1 && PART_TOOL="sgdisk"
fi
if [ -z "$PART_TOOL" ] && command -v parted >/dev/null 2>&1; then
    parted -s "$DISK" mklabel gpt >>/tmp/part.log 2>&1 && \
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB >>/tmp/part.log 2>&1 && \
    parted -s "$DISK" set 1 esp on >>/tmp/part.log 2>&1 && \
    parted -s "$DISK" mkpart primary ext4 513MiB 100% >>/tmp/part.log 2>&1 && PART_TOOL="parted"
fi
if [ -z "$PART_TOOL" ] && command -v sfdisk >/dev/null 2>&1; then
    printf 'label: gpt\nstart=1MiB, size=512MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="ESP"\nstart=513MiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="root"\n' | sfdisk "$DISK" >>/tmp/part.log 2>&1 && PART_TOOL="sfdisk"
fi
if [ -z "$PART_TOOL" ] && command -v fdisk >/dev/null 2>&1; then
    printf 'g\nn\n1\n\n+512M\nt\n1\n1\nn\n2\n\n\nw\n' | fdisk "$DISK" >>/tmp/part.log 2>&1 && PART_TOOL="fdisk"
fi
if [ -z "$PART_TOOL" ]; then
    r "[3][FATAL] 无可用分区工具（sgdisk/parted/sfdisk/fdisk 均缺失），无法继续。"
    exit 1
fi
r "[3] partitioned with $PART_TOOL"

# 通知内核重读分区表
command -v partprobe >/dev/null 2>&1 && partprobe "$DISK" >/dev/null 2>&1
command -v partx >/dev/null 2>&1 && partx -u "$DISK" >/dev/null 2>&1
command -v blockdev >/dev/null 2>&1 && blockdev --rereadpt "$DISK" >/dev/null 2>&1

# 等待分区设备节点出现
for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -b "$EFI_PART" ] && [ -b "$ROOT_PART" ] && break
    sleep 1
done

NPART=$(lsblk -lno NAME "$DISK" 2>/dev/null | tail -n +2 | wc -l)
r "[3] new layout: count=$NPART $(lsblk -lno NAME,SIZE,FSTYPE "$DISK" 2>/dev/null | tail -n +2 | tr '\n' ' ')"
if [ "${NPART:-0}" -ne 2 ] || [ ! -b "$ROOT_PART" ]; then
    r "[3][FATAL] 分区重建失败（count=$NPART）。工具输出：$(tr '\n' ' ' < /tmp/part.log)"
    exit 1
fi

# ---------- 4. 格式化 ----------
if command -v mkfs.fat >/dev/null 2>&1; then
    mkfs.fat -F32 "$EFI_PART" >>/tmp/part.log 2>&1 || r "[4][WARN] mkfs.fat failed"
elif command -v mkfs.vfat >/dev/null 2>&1; then
    mkfs.vfat -F32 "$EFI_PART" >>/tmp/part.log 2>&1 || r "[4][WARN] mkfs.vfat failed"
else
    r "[4][WARN] 无 FAT 格式化工具"
fi
mkfs.ext4 -F "$ROOT_PART" >>/tmp/part.log 2>&1 || r "[4][WARN] mkfs.ext4 failed"
r "[4] format done"

# ---------- 5. 挂载并校验容量 ----------
mount "$ROOT_PART" /mnt >>/tmp/part.log 2>&1
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot >>/tmp/part.log 2>&1
if ! mountpoint -q /mnt || ! mountpoint -q /mnt/boot; then
    r "[5][FATAL] mount failed, abort"
    exit 1
fi
MNT_MB=$(df -m /mnt 2>/dev/null | tail -1 | awk '{print $2}')
EFI_MB=$(df -m /mnt/boot 2>/dev/null | tail -1 | awk '{print $2}')
r "[5] mounted. root=${MNT_MB}MB boot=${EFI_MB}MB"
if [ "${MNT_MB:-0}" -lt 10000 ]; then
    r "[5][FATAL] 根分区仅 ${MNT_MB}MB（应为 ~60000MB），分区未真正生效，中止。"
    exit 1
fi

# ---------- 6. 配置镜像源（清华 Arch Linux ARM 镜像优先） ----------
cat > /etc/pacman.d/mirrorlist <<'MIRROR'
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/$arch/$repo
Server = https://mirrors.ustc.edu.cn/archlinuxarm/$arch/$repo
Server = http://mirror.archlinuxarm.org/$arch/$repo
MIRROR
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist 2>/dev/null
mkdir -p /mnt/etc/pacman.d
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
r "[6] mirrorlist configured"

# ---------- 7. 初始化密钥环 ----------
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinuxarm >/dev/null 2>&1
r "[7] pacman keyring ready"

# ---------- 8. 安装基础系统 + 桌面 ----------
r "[8] pacstrap START (this takes a while)"
pacstrap /mnt base base-devel linux-aarch64 linux-firmware \
    networkmanager sudo vim nano curl bash-completion \
    plasma-meta sddm konsole dolphin kate \
    noto-fonts-cjk noto-fonts-emoji \
    fcitx5 fcitx5-chinese-addons fcitx5-configtool \
    man-db man-pages texinfo 2>&1 | tee /tmp/pacstrap.log
PS_RC=${PIPESTATUS[0]}
r "[8] pacstrap END rc=$PS_RC  size=$(du -sh /mnt 2>/dev/null | awk '{print $1}')"
if [ $PS_RC -ne 0 ]; then
    r "[8][ERROR] last lines: $(tail -5 /tmp/pacstrap.log | tr '\n' ' ')"
    if [ "$PS_RC" -eq 141 ]; then
        r "[8][FATAL] pacstrap 被中断(rc=141 SIGPIPE)：通常是终端里按了 Ctrl+C 或被切走。中止。"
    else
        r "[8][FATAL] pacstrap 失败(rc=$PS_RC)：常见原因 网络不可达 / 磁盘空间不足。中止。"
    fi
    exit 1
fi

# ---------- 9. 生成 fstab ----------
genfstab -U /mnt >> /mnt/etc/fstab
r "[9] fstab generated: $(grep -c UUID /mnt/etc/fstab) entries"

# ---------- 10. 写入 chroot 配置脚本 ----------
cat > /mnt/root/config.sh <<'CHROOT'
#!/bin/bash
set -o pipefail
HOST_URL=$(cat /root/.host_url 2>/dev/null || echo "http://10.211.55.2:8000")
r() { echo "[arch] $1"; curl -s -m 10 -X POST -d "$1" "$HOST_URL/log" >/dev/null 2>&1; }

# 时区
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc 2>/dev/null
r "[10] timezone=Asia/Shanghai"

# 本地化
sed -i 's/^#zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen >/dev/null 2>&1
echo "LANG=zh_CN.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
r "[10] locale generated (zh_CN.UTF-8)"

# 主机名
echo "arch-vm" > /etc/hostname
cat > /etc/hosts <<'H'
127.0.0.1   localhost
::1         localhost
127.0.1.1   arch-vm.localdomain arch-vm
H
r "[10] hostname=arch-vm"

# root 密码
echo "root:arch" | chpasswd
r "[10] root password set"

# 普通用户
useradd -m -G wheel,audio,video,storage -s /bin/bash arch 2>/dev/null
echo "arch:arch" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
r "[10] user 'arch' created with sudo"

# 启用服务
systemctl enable NetworkManager >/dev/null 2>&1
systemctl enable sddm >/dev/null 2>&1
r "[10] services: NetworkManager + sddm enabled"

# 镜像源
mkdir -p /etc/pacman.d
cat > /etc/pacman.d/mirrorlist <<'MIRROR'
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/$arch/$repo
Server = https://mirrors.ustc.edu.cn/archlinuxarm/$arch/$repo
Server = http://mirror.archlinuxarm.org/$arch/$repo
MIRROR

# initramfs
mkinitcpio -P >/tmp/mkinitcpio.log 2>&1
r "[10] mkinitcpio rc=$? : $(tail -2 /tmp/mkinitcpio.log | tr '\n' ' ')"

# ---------- 引导器 systemd-boot ----------
bootctl install >/tmp/bootctl.log 2>&1
BC_RC=$?
r "[11] bootctl install rc=$BC_RC : $(tail -3 /tmp/bootctl.log | tr '\n' ' ')"

# 兜底：把 systemd-boot 复制到 EFI 默认启动路径 BOOTAA64.EFI
if [ -f /usr/lib/systemd/boot/efi/systemd-bootaa64.efi ]; then
    mkdir -p /boot/EFI/BOOT
    cp /usr/lib/systemd/boot/efi/systemd-bootaa64.efi /boot/EFI/BOOT/BOOTAA64.EFI
    r "[11] fallback BOOTAA64.EFI copied"
fi

# 检测内核镜像文件名（ALARM 通常为 /Image）
KIMG=""
for k in /boot/Image /boot/Image.gz /boot/vmlinuz-linux; do
    [ -f "$k" ] && KIMG=$(basename "$k") && break
done
[ -z "$KIMG" ] && KIMG="Image"
r "[11] kernel image = $KIMG"

# root 分区 UUID
RUUID=$(findmnt -no UUID /)
r "[11] root UUID = $RUUID"

mkdir -p /boot/loader/entries
cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux ARM
linux   /$KIMG
initrd  /initramfs-linux.img
options root=UUID=$RUUID rw
ENTRY
cat > /boot/loader/loader.conf <<'LC'
default  arch
timeout  3
LC
r "[11] loader entry written"

# 中文输入法环境变量
mkdir -p /home/arch/.config/environment.d
cat > /home/arch/.config/environment.d/im.conf <<'IM'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
IM
chown -R arch:arch /home/arch/.config 2>/dev/null

r "[12] chroot configuration COMPLETE"
CHROOT
chmod +x /mnt/root/config.sh
echo "$HOST_URL" > /mnt/root/.host_url
r "[10] chroot config script written"

# ---------- 11. 执行 chroot 配置 ----------
arch-chroot /mnt /bin/bash /root/config.sh 2>&1 | tail -5
r "[13] chroot execution finished"

# ---------- 12. 收尾检查 ----------
r "[14] boot files: $(ls /mnt/boot/ 2>/dev/null | tr '\n' ' ')"
r "[14] entry: $(cat /mnt/boot/loader/entries/arch.conf 2>/dev/null | tr '\n' ' | ')"
rm -f /mnt/root/config.sh
r "[15] ALL DONE - you may reboot now (remember to disconnect the ISO)"
