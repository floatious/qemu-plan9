#!/bin/sh -e

# Build Kernel for QEMU (bkq)

if [ ! -e ".git" ]; then
	echo "you are not standing in a git tree or a git worktree"
	echo ""
	echo "while standing in your kernel directory:"
	echo ""
	echo "usage: bqk.sh"
	exit
fi

# remove tmp files
# virtio-9p does cache things, but if a file is removed + added, the client
# will see the new file, e.g. if a rebuild is done without rebooting the VM
rm -rf tmp-modules/lib/modules/*

# set LOCALVERSION to the empty string, to avoid scripts/setlocalversion from
# appending -dirty or + to the kernel version string. If we do not do this, the
# kernel modules (which uses the kernel version string) might get installed to a
# directory that does not match the kernel version string of the running kernel.
make -j$(nproc) LOCALVERSION=
make -j$(nproc) -s modules_install INSTALL_MOD_PATH=tmp-modules INSTALL_MOD_STRIP=1 LOCALVERSION=
