#!/bin/bash

LFS=/mnt/lfs
KERNEL_VERSION=6.10.5-fegor-1.0
MY_OWN_LINUX=FegorOS
DISK_USB=# Insert your USB disk here

sudo apt install squashfs-tools
sudo apt install xorriso

mkdir -pv /create-iso && cd /create-iso

git clone https://github.com/emmett1/mkinitrd
wget -c http://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz
wget -c https://github.com/libarchive/libarchive/releases/download/v3.7.4/libarchive-3.7.4.tar.xz

tar xvf $LFS/sources/libarchive-3.7.4.tar.xz && cd $LFS/sources/libarchive-3.7.4
./configure --prefix=/usr --disable-static --without-expat && make 
sudo make DESTDIR=$LFS install

cd /create-iso
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
    -e /mnt/lfs/run/* \
    -e /mnt/lfs/sources/*

sudo make -C mkinitrd DESTDIR=$LFS install

sudo chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin     \
    MAKEFLAGS="-j$(nproc)"      \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash --login

# TODO: Create option to continue as chroot
mkinitrd -k $KERNEL_VERSION -a livecd -o /boot/initrd-$KERNEL_VERSION.img

cp -v $LFS/boot/vmlinuz-$KERNEL_VERSION live/boot/vmlinuz
cp -v $LFS/boot/initrd-$KERNEL_VERSION.img live/boot/initrd

touch live/isolinux/isolinux.cfg
cat live/isolinux/isolinux.cfg << EOF
UI /isolinux/menu.c32
DEFAULT silent
TIMEOUT 100

MENU VSHIFT 3

LABEL silent
        MENU LABEL Boot MyOwn Linux
	KERNEL /boot/vmlinuz
	APPEND initrd=/boot/initrd quiet

LABEL debug
        MENU LABEL MyOwn Linux (Debug)
	KERNEL /boot/vmlinuz
	APPEND initrd=/boot/initrd verbose

LABEL existing
	MENU LABEL Boot existing OS
	COM32 chain.c32
	APPEND hd0 0

LABEL reboot
        MENU LABEL Reboot
        COM32 reboot.c32

LABEL poweroff
        MENU LABEL Poweroff
        COM32 poweroff.c32
EOF

sudo mkdir -p live/rootfs/etc
sudo echo "# blank fstab" > live/rootfs/etc/fstab

sudo xorriso -as mkisofs \
    -isohybrid-mbr syslinux-6.03/bios/mbr/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -volid LIVECD \
    -o ${MY_OWN_LINUX}LiveCD.iso live

sudo dd if=${MY_OWN_LINUX}LiveCD.iso of=/dev/${DISK_USB} bs=1m

# If not working, try to use this command for manual boot
sudo mkfs.vfat -F 32 /dev/${DISK_USB}
sudo mount -o loop linux.iso /mnt
sudo cp -r /mnt/* /media/usb/
sudo grub-install --target=i386-pc --boot-directory=/media/usb/boot /dev/${DISK_USB}

