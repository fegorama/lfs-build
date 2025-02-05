#!/bin/bash

LFS=/mnt/lfs
sudo apt install squashfs-tools

mkdir -pv /create-iso && cd /create-iso

git clone https://github.com/emmett1/mkinitrd
wget -c http://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz

mkdir -p live/{isolinux,boot}

tar xvf syslinux-6.03.tar.xz
cp syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32 live/isolinux
cp syslinux-6.03/bios/com32/chain/chain.c32 live/isolinux
cp syslinux-6.03/bios/core/isolinux.bin live/isolinux
cp syslinux-6.03/bios/com32/libutil/libutil.c32 live/isolinux
cp syslinux-6.03/bios/com32/modules/reboot.c32 live/isolinux
cp syslinux-6.03/bios/com32/menu/menu.c32 live/isolinux
cp syslinux-6.03/bios/com32/lib/libcom32.c32 live/isolinux
cp syslinux-6.03/bios/com32/modules/poweroff.c32 live/isolinux

sudo mksquashfs $LFS live/boot/filesystem.sfs \
    -b 1048576 \
    -comp zstd \
    -e /mnt/lfs/root/* \
    -e /mnt/lfs/tools* \
    -e /mnt/lfs/tmp/* \
    -e /mnt/lfs/dev/* \
    -e /mnt/lfs/proc/* \
    -e /mnt/lfs/sys/* \
    -e /mnt/lfs/run/*

sudo make -C mkinitrd DESTDIR=$LFS install

# Pasar a chroot
sudo chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin     \
    MAKEFLAGS="-j$(nproc)"      \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash --login

