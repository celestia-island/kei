# U-Boot boot script for kei kernel on NanoPi R3S.
#
# Flashed at /boot/boot.scr on the SD card.
# Compile with: mkimage -C none -A arm -T script -d boot.cmd boot.scr
#
# Boot order:
#   1. If kei_netboot=1 (set in armbianEnv.txt): fetch kernel, DTB and
#      initramfs over TFTP from ${serverip}. Apart from this script,
#      nothing is read from the SD card — kernel iteration needs no
#      reflashing.
#   2. Otherwise, or if TFTP fails: load everything from the SD card.
#
# Iteration workflow (no reflashing):
#   python3 scripts/build.py nanopi-r3s    # rebuild kernel + DTB
#   scripts/push_netboot.sh                # copy artifacts to TFTP root
#   <reset the board>                      # U-Boot fetches over TFTP
#
# kei kernel is linked at KERNEL_LMA=0x40000000 (+0x80000 text offset)
# and is NOT position-independent: the load address must match.

test -n "${distro_bootpart}" || distro_bootpart=1

echo "[kei] boot script starting"

# Scratch area for one-shot loads (Armbian U-Boot presets load_addr;
# fall back to a safe address well above the kernel image).
test -n "${load_addr}" || setenv load_addr 0x4a000000

# Load Armbian environment (kei_netboot / ipaddr / serverip / ...).
if test -e ${devtype} ${devnum}:${distro_bootpart} /boot/armbianEnv.txt; then
    load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} /boot/armbianEnv.txt
    env import -t ${load_addr} ${filesize}
fi

setenv kernel_addr_r   0x40080000
setenv fdt_addr_r      0x50000000
setenv ramdisk_addr_r  0x51000000

setenv bootargs "console=ttyS2,1500000n8 earlycon init=/bin/sh"

# TFTP path prefix on the server (may be overridden from armbianEnv.txt).
test -n "${kei_tftp_prefix}" || setenv kei_tftp_prefix kei

if test "${kei_netboot}" = "1"; then
    echo "[kei] netboot enabled (serverip=${serverip})"
    if test -z "${ipaddr}"; then
        setenv autoload no
        dhcp
    fi
    if tftpboot ${kernel_addr_r} ${kei_tftp_prefix}/kei-kernel.bin; then
        if tftpboot ${fdt_addr_r} ${kei_tftp_prefix}/board.dtb && tftpboot ${ramdisk_addr_r} ${kei_tftp_prefix}/initramfs.cpio.gz; then
            echo "[kei] netboot: all artifacts received, booting"
            fdt addr ${fdt_addr_r}
            booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
        fi
    fi
    echo "[kei] netboot failed — falling back to SD card"
fi

echo "[kei] loading from SD (${devtype} ${devnum}:${distro_bootpart})"
load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /boot/kei-kernel.bin
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} /boot/board.dtb
load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} /boot/initramfs.cpio.gz
fdt addr ${fdt_addr_r}
booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}

# Recompile with:
# mkimage -C none -A arm -T script -d boot.cmd boot.scr
