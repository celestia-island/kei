# U-Boot boot script for kei kernel on NanoPi R3S.
#
# Flashed at /boot.scr on the SD card.
# Compile with: mkimage -C none -A arm -T script -d boot.cmd boot.scr
#
# Boot flow:
#   1. Rockchip BootROM → U-Boot (sector 64)
#   2. U-Boot loads kernel + DTB + initramfs
#   3. U-Boot patches DTB with actual framebuffer address (from video init)
#   4. Kernel starts with FDT in x0

test -n "${distro_bootpart}" || distro_bootpart=1

echo "Booting kei kernel on NanoPi R3S..."

# Load Armbian environment
if test -e ${devtype} ${devnum}:${distro_bootpart} /boot/armbianEnv.txt; then
    load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} /boot/armbianEnv.txt
    env import -t ${load_addr} ${filesize}
fi

setenv bootargs "console=ttyS2,1500000n8 earlycon"

load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /boot/kei-kernel.bin
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} /boot/board.dtb
load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} /boot/initramfs.cpio.gz

fdt addr ${fdt_addr_r}

# Patch framebuffer address into DTB if U-Boot set up video.
# Armbian U-Boot sets ${fb_base} after HDMI init (console=display/both).
if test -n "${fb_base}"; then
    echo "Framebuffer at ${fb_base} ${fb_width}x${fb_height} bpp=${fb_bpp}"
    fdt set /framebuffer reg "<0x0 ${fb_base} 0x0 0x800000>"
    fdt set /framebuffer width "<${fb_width}>"
    fdt set /framebuffer height "<${fb_height}>"
    fdt set /framebuffer stride "<${fb_line_length}>"
    if test ${fb_bpp} -eq 16; then
        fdt set /framebuffer format "r5g6b5"
    else
        fdt set /framebuffer format "a8r8g8b8"
    fi
fi

booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}

# Recompile with:
# mkimage -C none -A arm -T script -d boot.cmd boot.scr
