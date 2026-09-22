#!/bin/bash
# ============================================================
# Arch Linux ARM 自动安装脚本
# 目标：Parallels Desktop on Apple Silicon (ARM64 / UEFI)
# 用法：在 Archboot live 环境的 root shell 中执行本脚本
#
# 配置来源（后者覆盖前者）：
#   1. 本脚本内的默认值
#   2. /root/install.conf（若存在）—— 模板见 install.conf.example
# ============================================================

# ---------- 默认配置 ----------
NEW_HOSTNAME="arch-vm"          # 主机名
NEW_TIMEZONE="Asia/Shanghai"    # 时区
NEW_LOCALE="zh_CN.UTF-8"        # 系统语言
NEW_KEYMAP="us"                 # 键盘布局
NEW_USER="arch"                 # 普通用户名
NEW_USER_PW="arch"              # 普通用户密码（⚠️ 安装后请立即修改）
NEW_ROOT_PW="arch"              # root 密码（⚠️ 安装后请立即修改）
NEW_DESKTOP="kde"               # 桌面环境: kde | gnome | xfce | none
NEW_KERNEL="linux-aarch64"      # 内核包（ARM64 必须用 linux-aarch64）
NEW_DISK=""                     # 目标磁盘，留空 = 自动检测容量最大的磁盘
NEW_CJK="yes"                   # 安装中文字体与输入法: yes | no
NEW_MIRROR_CN="yes"             # 优先使用国内镜像: yes | no
NEW_EXTRA_PKGS=""               # 额外软件包（空格分隔）

# ---------- 加载外部配置 ----------
# 安全提示：配置文件以 root 权限被 source，因此必须先校验属主与写权限。
# 若可被非特权用户改写，则等价于本地提权。
for _conf in /root/install.conf /etc/install.conf; do
    [ -f "$_conf" ] || continue
    _owner=$(stat -c %U "$_conf" 2>/dev/null || stat -f %Su "$_conf" 2>/dev/null || echo "unknown")
    if [ "$_owner" != "root" ]; then
        echo "[arch][WARN] 跳过 $_conf：属主为 $_owner（必须为 root）"
        continue
    fi
    if [ -n "$(find "$_conf" -perm -0002 2>/dev/null)" ]; then
        echo "[arch][WARN] 跳过 $_conf：文件可被其他用户写入"
        continue
    fi
    # shellcheck source=/dev/null
    if . "$_conf"; then
        echo "[arch] config loaded: $_conf"
        break
    fi
done

# 桌面环境 → 显示管理器映射
case "$NEW_DESKTOP" in
    kde)   DM="sddm"    ;;
    gnome) DM="gdm"     ;;
    xfce)  DM="lightdm" ;;
    none)  DM=""        ;;
    *)     DM=""        ;;
esac

# 自动探测宿主机在 Parallels 虚拟网段中的地址（Shared / Host-Only 任一）
HOST_IP=""
for ip in 10.211.55.2 10.37.129.2; do
    if curl -s -m 3 "http://$ip:8000/ping" 2>/dev/null | grep -q "ok"; then
        HOST_IP="$ip"
        break
    fi
done
if [ -z "$HOST_IP" ]; then
    HOST_IP="10.211.55.2"
    echo "[arch][WARN] 未探测到宿主机（两个网段均无响应），日志回传可能不可用"
else
    echo "[arch] host detected at $HOST_IP"
fi
HOST_URL="http://$HOST_IP:8000"

# 日志函数：同时打印到屏幕并回传宿主机
r() {
    echo "[arch] $1"
    curl -s -m 10 -X POST -d "$1" "$HOST_URL/log" >/dev/null 2>&1
}

# ---------- 镜像源：候选清单 / 探活 / 择优写入 ----------
# 候选地址只在这里定义一次。原实现在 step 6 与 chroot 脚本里各写一份同样的
# mirrorlist，改一处漏一处，且 chroot 那份会把前面的结果覆盖掉。
MIRROR_CN="
https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm
https://mirrors.ustc.edu.cn/archlinuxarm
http://mirror.archlinuxarm.org
"
MIRROR_OFFICIAL="
http://mirror.archlinuxarm.org
"
MIRROR_PROBE_TIMEOUT=6      # 单站探测上限；三站全超时的最坏情况约 18 秒

MM_STATUS=""                # probed | fallback | official
MM_SELECTED=""
MM_LATENCY=""

# 逐站探活，取响应最快者。bash 没有浮点比较，交给 awk。
# 注意：curl 即使连接超时失败，-w '%{time_total}' 仍会输出一个数字，
# 因此必须同时校验退出码与 http_code，否则不可达的站点会被当成探活成功。
mm_select() {
    MM_SELECTED=""
    MM_LATENCY=""
    for _u in $MIRROR_CN; do
        _r=$(curl -sS -o /dev/null -m "$MIRROR_PROBE_TIMEOUT" \
                 -w '%{http_code} %{time_total}' "$_u/" 2>/dev/null)
        [ $? -ne 0 ] && continue
        _code=${_r%% *}
        _t=${_r##* }
        # http_code 为 000 表示压根没拿到 HTTP 响应；404/403 只说明路径不对，
        # 站点本身可达，仍应参与择优。
        [ "$_code" = "000" ] && continue
        case "$_t" in ''|*[!0-9.]*) continue ;; esac
        if [ -z "$MM_SELECTED" ] || awk -v a="$_t" -v b="$MM_LATENCY" 'BEGIN{exit !(a<b)}'; then
            MM_SELECTED="$_u"
            MM_LATENCY="$_t"
        fi
    done
}

# 生成 mirrorlist 到 $1。全部探测失败时退回静态顺序而不中止安装
# （探测本身不该成为新的失败源）。结果写入全局 MM_STATUS，
# 因此必须以普通命令调用，不能用 $() —— 那样赋值会随子 shell 丢失。
mm_write() {
    _out="$1"
    if [ "$NEW_MIRROR_CN" != "yes" ]; then
        # shellcheck disable=SC2086
        printf 'Server = %s/$arch/$repo\n' $MIRROR_OFFICIAL > "$_out"
        MM_STATUS="official"
        return
    fi
    mm_select
    if [ -z "$MM_SELECTED" ]; then
        # shellcheck disable=SC2086
        printf 'Server = %s/$arch/$repo\n' $MIRROR_CN > "$_out"
        MM_STATUS="fallback"
        return
    fi
    # 最快者排首位，其余保持原顺序作后备
    printf 'Server = %s/$arch/$repo\n' "$MM_SELECTED" > "$_out"
    for _u in $MIRROR_CN; do
        [ "$_u" = "$MM_SELECTED" ] || printf 'Server = %s/$arch/$repo\n' "$_u" >> "$_out"
    done
    MM_STATUS="probed"
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

# ---------- 2. 确定目标磁盘 ----------
if [ -n "$NEW_DISK" ] && [ -b "$NEW_DISK" ]; then
    # 拒绝光驱 / 回环等非磁盘设备，避免配置写错时误格式化
    case "$NEW_DISK" in
        *rom*|*loop*|*sr[0-9]*)
            r "[2][FATAL] 拒绝使用非磁盘设备：$NEW_DISK"
            exit 1
            ;;
    esac
    DISK="$NEW_DISK"
    r "[2] target disk = $DISK  ($(lsblk -ndo SIZE "$DISK" 2>/dev/null)) [from install.conf]"
else
    [ -n "$NEW_DISK" ] && r "[2][WARN] 配置的磁盘 $NEW_DISK 不存在，回退到自动检测"
    # 排除光驱(rom)与分区(part)，取容量最大的磁盘
    DISK=$(lsblk -ndo NAME,SIZE,TYPE 2>/dev/null | awk '$3=="disk"' | sort -k2 -h | tail -1 | awk '{print "/dev/"$1}')
    r "[2] target disk = $DISK  ($(lsblk -ndo SIZE "$DISK" 2>/dev/null)) [auto-detected]"
fi
if [ -z "$DISK" ] || [ ! -b "$DISK" ]; then
    r "[2][FATAL] cannot detect target disk, abort"
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

# 抹掉磁盘头部的主分区表与残留文件系统签名
# 注意：dd 仅覆盖磁盘开头 32MB（GPT 备份表位于磁盘末尾），
#      备份表由后续分区工具的 -Z / mklabel 处理
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

# 等待分区设备节点出现（最多 10 秒）
for _ in $(seq 1 10); do
    if [ -b "$EFI_PART" ] && [ -b "$ROOT_PART" ]; then
        break
    fi
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

# ---------- 6. 配置镜像源 ----------
mkdir -p /mnt/etc/pacman.d
mm_write /etc/pacman.d/mirrorlist
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
case "$MM_STATUS" in
    probed)   r "[6] mirrorlist: 探活择优 → $MM_SELECTED（${MM_LATENCY}s），其余作后备" ;;
    fallback) r "[6][WARN] 候选镜像全部探测失败，已退回静态顺序；若下一步 pacstrap 失败，先确认虚拟机网卡为 shared 与宿主机代理状态" ;;
    official) r "[6] mirrorlist: 官方源（NEW_MIRROR_CN != yes）" ;;
esac
r "[6] mirrorlist configured"

# ---------- 7. 初始化密钥环 ----------
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinuxarm >/dev/null 2>&1
r "[7] pacman keyring ready"

# ---------- 8. 组装软件包列表并安装 ----------
PKGS="base base-devel $NEW_KERNEL linux-firmware"
PKGS="$PKGS networkmanager sudo vim nano curl bash-completion man-db man-pages texinfo"

# 中文支持
if [ "$NEW_CJK" = "yes" ]; then
    PKGS="$PKGS noto-fonts-cjk noto-fonts-emoji fcitx5 fcitx5-chinese-addons fcitx5-configtool"
    r "[8] 中文支持: 已启用（字体 + fcitx5 输入法）"
fi

# 桌面环境
case "$NEW_DESKTOP" in
    kde)
        PKGS="$PKGS plasma-meta sddm konsole dolphin kate"
        r "[8] 桌面环境: KDE Plasma（显示管理器 sddm）"
        ;;
    gnome)
        PKGS="$PKGS gnome gnome-extra gdm"
        r "[8] 桌面环境: GNOME（显示管理器 gdm）"
        ;;
    xfce)
        PKGS="$PKGS xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"
        r "[8] 桌面环境: XFCE（显示管理器 lightdm）"
        ;;
    none)
        r "[8] 桌面环境: 无（纯命令行）"
        ;;
    *)
        r "[8][WARN] 未知桌面环境 '$NEW_DESKTOP'，按纯命令行处理"
        ;;
esac

# 额外软件包
if [ -n "$NEW_EXTRA_PKGS" ]; then
    PKGS="$PKGS $NEW_EXTRA_PKGS"
    r "[8] 额外软件包: $NEW_EXTRA_PKGS"
fi

r "[8] pacstrap START (this takes a while)"
# 关闭路径名展开：避免当前目录下的同名文件被误当作包名参数
set -f
# shellcheck disable=SC2086
pacstrap /mnt $PKGS 2>&1 | tee /tmp/pacstrap.log
PS_RC=${PIPESTATUS[0]}
set +f
r "[8] pacstrap END rc=$PS_RC  size=$(du -sh /mnt 2>/dev/null | awk '{print $1}')"
if [ $PS_RC -ne 0 ]; then
    r "[8][ERROR] last lines: $(tail -5 /tmp/pacstrap.log | tr '\n' ' ')"
    if [ "$PS_RC" -eq 141 ]; then
        r "[8][FATAL] pacstrap 被中断(rc=141 SIGPIPE)：通常是终端里按了 Ctrl+C 或被切走。中止。"
    else
        # 按日志实际内容定位原因，替代过去那句无法区分的「网络不可达 / 磁盘空间不足」
        r "[8][FATAL] pacstrap 失败(rc=$PS_RC)。按日志判读："
        if grep -qiE 'could not resolve host|connection refused|failed to download|Operation timed out|Could not connect' /tmp/pacstrap.log; then
            r "[8][CAUSE] 镜像站不可达。当时生效的镜像顺序：$(awk -F' = ' '/^Server/{printf "%s ", $2}' /etc/pacman.d/mirrorlist)"
            r "[8][HINT]  最常见原因是虚拟机网卡为 host-only（无外网出口）——宿主机执行: bash diagnose.sh"
        fi
        if grep -qiE 'signature|keyring|invalid or corrupted package' /tmp/pacstrap.log; then
            r "[8][CAUSE] 包签名或密钥环校验失败。多因系统时钟偏差过大，先核对 date 与真实时间。"
        fi
        if grep -qiE 'no space left|not enough free space' /tmp/pacstrap.log; then
            r "[8][CAUSE] 磁盘空间不足：/mnt 可用 $(df -h /mnt 2>/dev/null | tail -1 | awk '{print $4}')"
        fi
        if grep -qiE 'target .* not found|package .* not found' /tmp/pacstrap.log; then
            r "[8][CAUSE] 有包名在当前仓库中不存在：$(grep -ioE 'target [^ ]+ not found' /tmp/pacstrap.log | head -3 | tr '\n' ' ')"
            r "[8][HINT]  若刚改过 NEW_EXTRA_PKGS 或 NEW_DESKTOP 组合，用 pacman -Ss 确认包名"
        fi
    fi
    exit 1
fi

# ---------- 9. 生成 fstab ----------
genfstab -U /mnt >> /mnt/etc/fstab
r "[9] fstab generated: $(grep -c UUID /mnt/etc/fstab) entries"

# ---------- 10. 写入 chroot 配置脚本 ----------
# 配置值必须显式传给 chroot（chroot 后无法继承父 shell 的变量）
cat > /mnt/root/.install-vars <<VARS
NEW_HOSTNAME='$NEW_HOSTNAME'
NEW_TIMEZONE='$NEW_TIMEZONE'
NEW_LOCALE='$NEW_LOCALE'
NEW_KEYMAP='$NEW_KEYMAP'
NEW_USER='$NEW_USER'
NEW_USER_PW='$NEW_USER_PW'
NEW_ROOT_PW='$NEW_ROOT_PW'
NEW_DESKTOP='$NEW_DESKTOP'
DM='$DM'
NEW_CJK='$NEW_CJK'
NEW_MIRROR_CN='$NEW_MIRROR_CN'
VARS
chmod 600 /mnt/root/.install-vars

cat > /mnt/root/config.sh <<'CHROOT'
#!/bin/bash
set -o pipefail
HOST_URL=$(cat /root/.host_url 2>/dev/null || echo "http://10.211.55.2:8000")
r() { echo "[arch] $1"; curl -s -m 10 -X POST -d "$1" "$HOST_URL/log" >/dev/null 2>&1; }

# 加载安装配置
# shellcheck source=/dev/null
. /root/.install-vars

# ---------- 时区 ----------
ln -sf "/usr/share/zoneinfo/$NEW_TIMEZONE" /etc/localtime
hwclock --systohc 2>/dev/null
r "[10] timezone=$NEW_TIMEZONE"

# ---------- 本地化 ----------
LOC_BASE=${NEW_LOCALE%%.*}
sed -i "s/^#\(${LOC_BASE}\.UTF-8\)/\1/" /etc/locale.gen
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen >/dev/null 2>&1
echo "LANG=$NEW_LOCALE" > /etc/locale.conf
echo "KEYMAP=$NEW_KEYMAP" > /etc/vconsole.conf
r "[10] locale=$NEW_LOCALE keymap=$NEW_KEYMAP"

# ---------- 主机名 ----------
echo "$NEW_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $NEW_HOSTNAME.localdomain $NEW_HOSTNAME
HOSTS
r "[10] hostname=$NEW_HOSTNAME"

# ---------- root 密码 ----------
echo "root:$NEW_ROOT_PW" | chpasswd
r "[10] root password set"

# ---------- 普通用户 ----------
useradd -m -G wheel,audio,video,storage -s /bin/bash "$NEW_USER" 2>/dev/null
echo "$NEW_USER:$NEW_USER_PW" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
r "[10] user '$NEW_USER' created with sudo"

# ---------- 启用服务 ----------
systemctl enable NetworkManager >/dev/null 2>&1
if [ -n "$DM" ]; then
    systemctl enable "$DM" >/dev/null 2>&1
    r "[10] services: NetworkManager + $DM enabled"
else
    r "[10] services: NetworkManager enabled (无显示管理器)"
fi

# ---------- 镜像源 ----------
# 此处刻意不再重写 mirrorlist：step 6 已探活择优并复制到 /mnt/etc/pacman.d/mirrorlist。
# 原实现在这里又写了一遍静态顺序，会把择优结果覆盖掉。

# ---------- initramfs ----------
mkinitcpio -P >/tmp/mkinitcpio.log 2>&1
r "[10] mkinitcpio rc=$? : $(tail -2 /tmp/mkinitcpio.log | tr '\n' ' ')"

# ---------- 引导器 systemd-boot ----------
bootctl install >/tmp/bootctl.log 2>&1
BC_RC=$?
r "[11] bootctl install rc=$BC_RC : $(tail -3 /tmp/bootctl.log | tr '\n' ' ')"

# 兜底：复制到 UEFI 默认启动路径，防止 bootctl 无法写 EFI 变量
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

# ---------- 中文输入法环境变量 ----------
if [ "$NEW_CJK" = "yes" ]; then
    mkdir -p "/home/$NEW_USER/.config/environment.d"
    cat > "/home/$NEW_USER/.config/environment.d/im.conf" <<'IM'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
IM
    chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.config" 2>/dev/null
    r "[12] fcitx5 环境变量已写入"
fi

r "[12] chroot configuration COMPLETE"
CHROOT
chmod +x /mnt/root/config.sh
echo "$HOST_URL" > /mnt/root/.host_url
r "[10] chroot config script written"

# ---------- 11. 执行 chroot 配置 ----------
# 管道会让 $? 取到 tail 的退出码（恒为 0），必须用 PIPESTATUS[0] 才能拿到 chroot 的真实结果
arch-chroot /mnt /bin/bash /root/config.sh 2>&1 | tail -5
CH_RC=${PIPESTATUS[0]}
if [ "$CH_RC" -ne 0 ]; then
    r "[13][FATAL] chroot 配置失败（rc=$CH_RC），系统可能无法启动。中止。"
    exit 1
fi
r "[13] chroot 配置完成（rc=0）"

# ---------- 12. 收尾检查 ----------
r "[14] boot files: $(ls /mnt/boot/ 2>/dev/null | tr '\n' ' ')"
r "[14] entry: $(cat /mnt/boot/loader/entries/arch.conf 2>/dev/null | tr '\n' ' | ')"
# 清理安装期临时文件（.install-vars 含明文密码，必须一并删除）
rm -f /mnt/root/config.sh /mnt/root/.install-vars /mnt/root/.host_url
r "[15] ALL DONE - you may reboot now (remember to disconnect the ISO)"
