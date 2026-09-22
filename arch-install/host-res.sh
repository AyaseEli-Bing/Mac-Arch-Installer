#!/bin/bash
# ============================================================
# 宿主机资源探测（共用片段，被 check.sh 与 diagnose.sh source）
#
# 为什么单独成文件：check.sh 与 diagnose.sh 各自实现同一探测逻辑，
# 曾导致两个脚本对同一环境给出互相矛盾的结论（见 代码审查报告 六-1、
# CHANGELOG 1.2.2「ISO 探测改为按时间取最新，与 check.sh 一致」）。
# 阈值与取数在此单点定义，两脚本只负责各自的呈现与修复建议。
#
# 兼容 macOS 自带 bash 3.2：不使用数组、关联数组与 [[ -v ]]。
# ============================================================

# ---------- 阈值（唯一事实源） ----------
# 磁盘：安装器会建约 60GB 的虚拟布局（install.sh 断言根分区 ~60000MB），
#       base + KDE 实际落盘约 10–20GB，且稀疏镜像随使用增长。
HR_DISK_FAIL_GB=10
HR_DISK_WARN_GB=30
# 内存：虚拟机占用达到宿主机一半时，macOS 与虚拟机桌面同时运行会紧张
HR_MEM_WARN_PCT=50
# 建议值必须明显低于警告线，否则「修复建议」会算出与当前值相同的数，等于没说
HR_MEM_TARGET_PCT=40

# 探测并写入全局变量：
#   HR_AVAIL_GB / HR_VM_HOME / HR_HOST_MEM_GB / HR_HOST_CPU / HR_VM_MEM_MB / HR_VM_CPU
# 取不到的项留空，由调用方判断如何呈现。不打印、不退出，便于两脚本复用。
hr_probe() {
    _hr_prl="$1"
    _hr_vm="$2"

    # 优先按虚拟机实际所在卷测量（可能不在默认 ~/Parallels，甚至在外置盘）
    HR_VM_HOME=""
    if [ -x "$_hr_prl" ]; then
        HR_VM_HOME=$("$_hr_prl" list -i "$_hr_vm" 2>/dev/null | grep -m1 '^Home:' | sed 's/^Home:[[:space:]]*//')
    fi
    if [ -n "$HR_VM_HOME" ] && [ ! -d "$HR_VM_HOME" ]; then
        HR_VM_HOME=""
    fi
    [ -n "$HR_VM_HOME" ] || HR_VM_HOME="$HOME"

    # 取整交给 awk：非数字输入会得到空值，调用方用 -z 分支兜住
    HR_AVAIL_GB=$(df -k "$HR_VM_HOME" 2>/dev/null | tail -1 | awk '{print int($4/1048576)}')
    HR_HOST_MEM_GB=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1073741824)}')
    HR_HOST_CPU=$(sysctl -n hw.ncpu 2>/dev/null)

    HR_VM_MEM_MB=""
    HR_VM_CPU=""
    if [ -x "$_hr_prl" ]; then
        _hr_info=$("$_hr_prl" list -i "$_hr_vm" 2>/dev/null)
        HR_VM_MEM_MB=$(printf '%s\n' "$_hr_info" | sed -n 's/.*memory size=\([0-9]*\)Mb.*/\1/p' | head -1)
        HR_VM_CPU=$(printf '%s\n' "$_hr_info" | sed -n 's/.*cpus=\([0-9]*\).*/\1/p' | head -1)
    fi

    # 非纯数字一律归零，避免调用方算术比较直接报错
    case "${HR_AVAIL_GB:-x}" in ''|*[!0-9]*) HR_AVAIL_GB="" ;; esac
    case "${HR_HOST_MEM_GB:-x}" in ''|*[!0-9]*) HR_HOST_MEM_GB="" ;; esac
    case "${HR_HOST_CPU:-x}" in ''|*[!0-9]*) HR_HOST_CPU="" ;; esac
    case "${HR_VM_MEM_MB:-x}" in ''|*[!0-9]*) HR_VM_MEM_MB="" ;; esac
    case "${HR_VM_CPU:-x}" in ''|*[!0-9]*) HR_VM_CPU="" ;; esac

    unset _hr_prl _hr_vm _hr_info
}

# 磁盘判级：echo fail / warn / ok / unknown（阈值唯一来源，调用方据此呈现）
hr_disk_level() {
    if [ -z "$HR_AVAIL_GB" ]; then
        echo unknown
    elif [ "$HR_AVAIL_GB" -lt "$HR_DISK_FAIL_GB" ]; then
        echo fail
    elif [ "$HR_AVAIL_GB" -lt "$HR_DISK_WARN_GB" ]; then
        echo warn
    else
        echo ok
    fi
}

# 内存分配判级：echo fail / warn / ok / skip（虚拟机未创建或读不到时为 skip）
hr_mem_level() {
    if [ -z "$HR_HOST_MEM_GB" ] || [ -z "$HR_VM_MEM_MB" ]; then
        echo skip
    elif [ "$HR_VM_MEM_MB" -gt $((HR_HOST_MEM_GB * 1024)) ]; then
        echo fail
    elif [ "$HR_VM_MEM_MB" -ge $((HR_HOST_MEM_GB * 1024 * HR_MEM_WARN_PCT / 100)) ]; then
        echo warn
    else
        echo ok
    fi
}

# 虚拟机内存占宿主机百分比（判级为 warn 时用于措辞；取不到则 echo ?）
hr_mem_pct() {
    if [ -n "$HR_HOST_MEM_GB" ] && [ -n "$HR_VM_MEM_MB" ] && [ "$HR_HOST_MEM_GB" -gt 0 ]; then
        echo $((HR_VM_MEM_MB * 100 / (HR_HOST_MEM_GB * 1024)))
    else
        echo '?'
    fi
}

# 建议的虚拟机内存上限（Mb）；读不到宿主机内存时输出空，调用方须自行判空
hr_mem_target_mb() {
    if [ -n "$HR_HOST_MEM_GB" ]; then
        echo $((HR_HOST_MEM_GB * 1024 * HR_MEM_TARGET_PCT / 100))
    fi
}

# CPU 是否超配：echo yes / no
hr_cpu_over() {
    if [ -n "$HR_HOST_CPU" ] && [ -n "$HR_VM_CPU" ] && [ "$HR_VM_CPU" -gt "$HR_HOST_CPU" ]; then
        echo yes
    else
        echo no
    fi
}
