#!/bin/sh

# Change this to contain the PCI address of the device you want to pass through
# to QEMU. In this example, we will use:
# 0000:00:17.0 SATA controller: Intel Corporation C620 Series Chipset Family SATA Controller [AHCI mode] (rev 0a)
# Therefore, the variable will be set to: 0000:00:17.0
PCI_BDF=0000:00:17.0

sudo modprobe vfio-pci

bind_driver() {
	local drv="$1"
	for DEV in $(ls /sys/bus/pci/devices/$PCI_BDF/iommu_group/devices) ; do
		if [ $(( 0x$(setpci -s $DEV HEADER_TYPE) & 0x7f )) -eq 0 ]; then
			sudo sh -c "echo $drv > /sys/bus/pci/devices/$DEV/driver_override"
			sudo sh -c "echo $DEV > /sys/bus/pci/devices/$DEV/driver/unbind"
			sudo sh -c "echo $DEV > /sys/bus/pci/drivers_probe"
		fi
	done
}

if [ $# -eq 1 ] && [ $1 = reset ]; then
	bind_driver ""
else
	bind_driver "vfio-pci"
	group=$(readlink /sys/bus/pci/devices/$PCI_BDF/iommu_group)
	group_nbr=$(printf '%s' $group | sed 's,.*/iommu_groups/,,')
	sudo chown $USER:$USER /dev/vfio/$group_nbr
fi
