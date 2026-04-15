#!/bin/sh

QEMU_BINARY=qemu-system-x86_64
KERNEL=arch/x86/boot/bzImage
ROOTFS=~/qemu-data/fedora-rootfs-overlay.img
USER_DATA=~/qemu-data/user-data.img
QEMU_GUEST_SSH_FWD_PORT=10222
RAM=4G

# Change this to contain the PCI address of the device you want to pass through
# to QEMU. It has to be the same PCI address as you specified in setup_dev.sh
PCI_BDF=0000:00:17.0

# do not change this
MODULES=tmp-modules/lib/modules

if [ ! -f "$KERNEL" ]; then
	echo "you are not standing in a kernel tree"
	exit
fi

exec $QEMU_BINARY -m $RAM -cpu host -smp $(nproc) -enable-kvm -nographic \
	-kernel $KERNEL -drive file=$ROOTFS,format=qcow2,if=virtio \
	-drive file=$USER_DATA,format=raw,if=virtio \
	-fsdev local,id=test_dev,path=$MODULES,security_model=mapped,multidevs=remap \
	-device virtio-9p-pci,fsdev=test_dev,mount_tag=tag_modules \
	-append "console=ttyS0 root=/dev/vda3 rootflags=subvol=root net.ifnames=0 nokaslr oops=panic panic=0" \
	-net nic,model=virtio -net user,hostfwd=tcp::$QEMU_GUEST_SSH_FWD_PORT-:22 \
	-drive driver=null-co,read-zeroes=on,latency-ns=50000000,if=none,id=disk \
	-device ich9-ahci,id=ahci -device ide-hd,drive=disk,bus=ahci.0
	#-device vfio-pci,host=$PCI_BDF
