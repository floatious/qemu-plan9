#!/bin/sh

QEMU_BINARY=qemu-system-x86_64
KERNEL=arch/x86/boot/bzImage
ROOTFS=~/qemu-data/fedora-rootfs-overlay.img
USER_DATA=~/qemu-data/user-data.img
QEMU_GUEST_SSH_FWD_PORT=10222
RAM=4G

# do not change this
MODULES=tmp-modules/lib/modules

if [ ! -f "$KERNEL" ]; then
	echo "you are not standing in a kernel tree"
	exit
fi

exec $QEMU_BINARY -m $RAM -cpu host -smp $(nproc) -enable-kvm -nographic \
	-drive file=$ROOTFS,format=qcow2,if=virtio \
	-drive file=$USER_DATA,format=raw,if=virtio \
	-fsdev local,id=test_dev,path=$MODULES,security_model=mapped,multidevs=remap \
	-device virtio-9p-pci,fsdev=test_dev,mount_tag=tag_modules \
	-kernel $KERNEL \
	-append "console=ttyS0 root=/dev/vda3 rootflags=subvol=root net.ifnames=0 nokaslr oops=panic panic=0" \
	-net nic,model=virtio -net user,hostfwd=tcp::$QEMU_GUEST_SSH_FWD_PORT-:22 \
	-drive driver=null-co,read-zeroes=on,latency-ns=50000000,if=none,id=disk \
	-device ich9-ahci,id=ahci -device ide-hd,drive=disk,bus=ahci.0
