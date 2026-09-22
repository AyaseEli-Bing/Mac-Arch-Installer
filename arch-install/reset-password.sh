#!/bin/bash
# ============================================================
# 密码重置脚本（在 Archboot live 环境中执行）
# 用途：忘记 Arch 登录密码时，绕过登录直接重置
#
# 用法（二选一）：
#   1) 交互式（推荐，适用于 curl | bash）：
#        curl -s http://<宿主机>:8000/r | bash
#   2) 通过环境变量指定新密码：
#        curl -s http://<宿主机>:8000/r -o /root/r.sh && \
#        NEWPW='你的新密码' bash /root/r.sh
#
# 注意：本脚本不硬编码任何密码，必须由使用者提供。
# ============================================================
# 宿主机地址：优先由环境变量指定，否则自动探测（与 install.sh 保持一致）
if [ -z "${HOST:-}" ]; then
    HOST=""
    for _ip in 10.211.55.2 10.37.129.2; do
        if curl -s -m 3 "http://$_ip:8000/ping" 2>/dev/null | grep -q "ok"; then
            HOST="http://$_ip:8000"
            break
        fi
    done
    [ -z "$HOST" ] && HOST="http://10.211.55.2:8000"
fi

r() {
    echo "[reset] $1"
    curl -s -m 10 -X POST -d "$1" "$HOST/log" >/dev/null 2>&1
}

# ---------- 获取新密码 ----------
NEWPW="${NEWPW:-}"
if [ -z "$NEWPW" ]; then
    # 从终端读取，避免与 `curl | bash` 的标准输入冲突
    if [ -r /dev/tty ]; then
        printf "请输入要设置的新密码: " >/dev/tty
        read -rs NEWPW </dev/tty
        printf "\n" >/dev/tty
        printf "请再次输入以确认: " >/dev/tty
        read -rs NEWPW2 </dev/tty
        printf "\n" >/dev/tty
        if [ "$NEWPW" != "$NEWPW2" ]; then
            echo "[reset][FATAL] 两次输入不一致，中止"
            exit 1
        fi
    else
        echo "[reset][FATAL] 未提供新密码且无可用终端"
        echo "请改用: NEWPW='你的密码' bash 本脚本"
        exit 1
    fi
fi
[ -z "$NEWPW" ] && { echo "[reset][FATAL] 密码为空，中止"; exit 1; }
r "=== 密码重置开始 ==="

# 定位根分区（ext4 的那个，容量最大）
ROOT=$(lsblk -lno NAME,FSTYPE,SIZE | awk '$2=="ext4"{print $3, "/dev/"$1}' | sort -h | tail -1 | awk '{print $2}')
r "根分区 = $ROOT"
if [ -z "$ROOT" ] || [ ! -b "$ROOT" ]; then
    r "[FATAL] 未找到 ext4 根分区，中止"
    exit 1
fi

# 清理可能已存在的挂载
umount -R /mnt >/dev/null 2>&1
mkdir -p /mnt

# 挂载根分区
if ! mount "$ROOT" /mnt; then
    r "[FATAL] 挂载 $ROOT 失败"
    exit 1
fi
r "已挂载，开始 chroot 重置"

# chroot 需要的基础挂载
mount --bind /dev  /mnt/dev  2>/dev/null
mount --bind /proc /mnt/proc 2>/dev/null
mount --bind /sys  /mnt/sys  2>/dev/null

# 重置 arch 与 root 的密码
# 安全要点：密码经 stdin 传给 chpasswd，绝不进入命令行参数。
# 若写成 `bash -c "echo 'arch:${NEWPW}' | chpasswd"`，会有两个后果：
#   ① 命令执行期间密码出现在 ps / /proc/*/cmdline 中，明文可读；
#   ② 密码含单引号时引号结构被破坏，构成命令注入。
CHOUT=$(printf 'arch:%s\nroot:%s\n' "$NEWPW" "$NEWPW" | arch-chroot /mnt chpasswd 2>&1)
CH_RC=$?
r "chpasswd rc=$CH_RC 输出: $(printf '%s' "$CHOUT" | tr '\n' ' ')"

# 顺带解锁账号（若曾被锁定）
arch-chroot /mnt /bin/bash -c "passwd -u arch 2>/dev/null; passwd -u root 2>/dev/null" >/dev/null 2>&1

# 验证（passwd -S 的第二个字段：P=已设密码，L=锁定，NP=无密码）
VERIFY=$(arch-chroot /mnt passwd -S arch 2>&1)
r "账号状态: $VERIFY"
case "$VERIFY" in
    *"arch P "*)
        r "[OK] 密码已生效"
        ;;
    *)
        r "[FATAL] 密码未生效（状态: $VERIFY）—— 请检查根分区是否可写"
        umount -R /mnt 2>/dev/null
        exit 1
        ;;
esac

# 卸载
umount -R /mnt 2>/dev/null
sync

r "=== 完成 ==="
echo ""
echo "=================================="
echo " 密码已重置"
echo "   arch 密码: $NEWPW"
echo "   root 密码: $NEWPW"
echo "=================================="
echo ""
r "[DONE] 密码重置成功，可以重启了"
