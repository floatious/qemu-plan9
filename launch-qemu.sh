#!/bin/sh

QEMU_BINARY=qemu-system-x86_64
KERNEL_DIR=~/src/linux
KERNEL=${KERNEL_DIR}/arch/x86/boot/bzImage
ROOTFS=~/qemu-data/fedora-rootfs-overlay.img
USER_DATA=~/qemu-data/user-data.img
QEMU_GUEST_SSH_FWD_PORT=10222
RAM=4G

# do not change this
MODULES=${KERNEL_DIR}/tmp-modules/lib/modules

$QEMU_BINARY -m $RAM -cpu host -smp $(nproc) -enable-kvm -nographic \
             -drive file=$ROOTFS,format=qcow2,if=virtio \
             -drive file=$USER_DATA,format=raw,if=virtio \
             -fsdev local,id=test_dev,path=$MODULES,security_model=mapped,multidevs=remap \
             -device virtio-9p-pci,fsdev=test_dev,mount_tag=tag_modules \
             -kernel $KERNEL \
             -append "console=ttyS0 root=/dev/vda3 rootflags=subvol=root net.ifnames=0 nokaslr oops=panic panic=0" \
             -device virtio-net-pci,netdev=usernet \
             -netdev user,id=usernet,hostfwd=tcp::$QEMU_GUEST_SSH_FWD_PORT-:22
