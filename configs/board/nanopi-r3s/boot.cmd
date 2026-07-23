# U-Boot boot script for kei kernel on NanoPi R3S.
#
# Flashed at /boot/boot.cmd on the SD card rootfs.
# Compile with: mkimage -C none -A arm -T script -d boot.cmd boot.scr
#
# Boot flow:
#   1. Rockchip BootROM → U-Boot (sector 64)
#   2. U-Boot reads /boot.scr → loads kernel + DTB + initramfs
#   3. Kernel starts with FDT in x0, initramfs at initrd_start

test -n "${distro_bootpart}" || distro_bootpart=1

echo "Booting kei kernel on NanoPi R3S..."

# Load Armbian environment if present (provides fdt_addr_r, kernel_addr_r, etc.)
if test -e ${devtype} ${devnum}:${distro_bootpart} /boot/armbianEnv.txt; then
    load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} /boot/armbianEnv.txt
    env import -t ${load_addr} ${filesize}
fi

setenv bootargs "console=ttyS2,1500000n8 earlycon kei.console=ttyS2,1500000"

load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /boot/kei-kernel.bin
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} /boot/board.dtb
load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} /boot/initramfs.cpio.gz

fdt addr ${fdt_addr_r}

booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}

# Recompile with:
# mkimage -C none -A arm -T script -d boot.cmd boot.scr
