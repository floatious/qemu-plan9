# QEMU with kernel modules

Using QEMU is nice, however, using kernel modules together with QEMU is usually
not very convenient.

Some possible options are:
1) Build everything as built-in instead of as kernel modules.
However, sometimes you actually need to test with kernel modules, so this does
not always work.
2) Put all the kernel modules in the initramfs.
However, the contents of the initramfs is usually no longer accessible after
boot. (You could modify your initscript to bind mount your initramfs before
performing the chroot, but even then, this would not allow us to update the
kernel modules while the VM is running.)
3) Use virtio-blk and mkfs.ext2 on a file, and put all the kernel modules in
that file/filesystem.
However, this also does not allow us to update the kernel modules while the VM
is running.
4) Use VirtioFS.
However, VirtioFS requires a separate daemon.
(VirtioFS is supposed to be faster than VirtFS, but for simply loading kernel
modules, performance is not the only thing we care about.)
5) Use VirtFS (Plan 9 folder sharing over Virtio).
VirtFS support is built-in to QEMU and requires no extra daemon.

This guide will explain how to use VirtFS (Plan 9 folder sharing over Virtio).

Install QEMU.
On Ubuntu/Debian:
```
sudo apt install qemu-system-x86 qemu-utils
```

or on Fedora/RHEL:
```
sudo dnf install qemu-system-x86 qemu-img
```

Create a new directory were you will keep the new code, e.g.:
```
mkdir ~/src
```

Clone and build the kernel that you will run inside QEMU:
```
cd ~/src
git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
cd linux
cp /boot/config-$(uname -r) .config
make olddefconfig
./scripts/config --enable CONFIG_BTRFS_FS
./scripts/config --enable CONFIG_BTRFS_FS_POSIX_ACL
./scripts/config --enable CONFIG_PSI
./scripts/config --enable CONFIG_MEMCG
./scripts/config --enable CONFIG_CRYPTO_LZO
./scripts/config --enable CONFIG_ZRAM
./scripts/config --enable CONFIG_ZRAM_DEF_COMP_LZORLE
./scripts/config --enable CONFIG_ISO9660_FS
./scripts/config --enable CONFIG_VFAT_FS
./scripts/config --enable CONFIG_NET_9P
./scripts/config --enable CONFIG_NET_9P_VIRTIO
./scripts/config --enable CONFIG_9P_FS
./scripts/config --enable CONFIG_9P_FS_POSIX_ACL
./scripts/config --enable CONFIG_VIRTIO
./scripts/config --enable CONFIG_VIRTIO_PCI
./scripts/config --enable CONFIG_PCI
./scripts/config --enable CONFIG_VIRTIO_BLK
make olddefconfig
make -j$(nproc)
```

Create a new directory were you will keep the QEMU scripts and data, e.g.:
```
mkdir ~/qemu-data
```

Get a QEMU friendly rootfs image (this guide uses Fedora) using:
```
cd ~/qemu-data
wget https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-UEFI-UKI.x86_64-40-1.14.qcow2
```

Create a new image that will be used as our rootfs, based on the Fedora image that we just downloaded.
It will not modify the Fedora image we just downloaded. Differences will be saved in fedora-rootfs-overlay.img.
It will not take up 128 GB, it will simply allow it to grow up to that size, since this new file will automatically
increase in size when we install new packages.
```
qemu-img create -f qcow2 -b Fedora-Cloud-Base-UEFI-UKI.x86_64-40-1.14.qcow2 -F qcow2 fedora-rootfs-overlay.img 128G
```

Install cloud-localds on Ubuntu/Debian:
```
sudo apt install cloud-image-utils genisoimage
```

or on Fedora/RHEL:
```
sudo dnf install cloud-utils genisoimage
```

We need to tell Fedora to create a user that you can use inside your new image.
This is done using cloud-config. The username will be the same as your current
user ($USER). There will be no password for this user, the only way to login
will be via SSH. Start by saving the value of your public SSH key into a
variable:
```
export PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)
```

Create the user-data file by pasting the following into a terminal and press enter:
```
cat >user-data <<EOF
#cloud-config
chpasswd:
  list: |
    root:your_password
  expire: False
users:
  - name: $USER
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh-authorized-keys:
      - $PUB_KEY
EOF
```

Open the file and change your_password to whatever you prefer. This will be the
password for root. If you do not want to set a root password, remove the whole
chpasswd block.

Generate the binary file user-data.img using:
```
cloud-localds user-data.img user-data
```

Download bkq.sh and make it executable:
```
wget https://raw.githubusercontent.com/floatious/qemu-plan9/main/bkq.sh
chmod +x bkq.sh
```

Download launch-qemu.sh and make it executable:
```
wget https://raw.githubusercontent.com/floatious/qemu-plan9/main/launch-qemu.sh
chmod +x launch-qemu.sh
```

In case you decided to use paths that differ from this guide, you will need to
modify the variables in launch-qemu.sh to match your setup.

Change directory to your kernel directory and run the bkq.sh script, which will
build the kernel and install the kernel modules to the tmp-modules directory
within your kernel directory:
```
cd ~/src/linux
./bkq.sh
```

Launch QEMU:
```
./launch-qemu.sh
```

The launch-qemu.sh script will serve the tmp-modules directory as a VirtFS share
to the guest OS.

You can kill your QEMU machine by typing Ctrl-A and then X. However, it is
recommended to shutdown the QEMU machine just like any other machine, i.e.
using e.g. **shutdown -h now**.

Log on to your QEMU machine using SSH:
```
ssh -A -p 10222 localhost
```

While logged on to your QEMU machine, modify /etc/fstab such that the VirtFS
share will be mounted automatically on boot:
```
sudo sh -c 'echo tag_modules /lib/modules 9p trans=virtio,version=9p2000.L,x-initrd.mount,context="system_u:object_r:modules_object_t:s0" >> /etc/fstab'
```

The **x-initrd.mount** mount option is interpreted by systemd, in order to mount
the share early, before running systemd-udev-trigger.service (which will
coldplug all devices).

The **context="system_u:object_r:modules_object_t:s0"** mount option is needed
such that the SELinux label will be set correctly. Without this option SELinux
will not allow you to load kernel modules from the share, and would result in
something like the following being printed in the journal (which can be dumped
using e.g. **journalctl -b**):
```
audit[570]: AVC avc:  denied  { module_load } for  pid=570 comm="(udev-worker)" path="/usr/lib/modules/6.10.0-rc3/kernel/drivers/ata/libahci.ko" dev="9p" ino=33011355 scontext=system_u:system_r:udev_t:s0-s0:c0.c1023 tcontext=unconfined_u:object_r:user_home_t:s0 tclass=system permissive=0
```

After modifying fstab, reboot the QEMU machine:
```
sudo reboot
```

Log on to your QEMU machine again:
```
ssh -A -p 10222 localhost
```

While logged on to your QEMU machine, list the loaded modules:
```
lsmod
```

If everything is working, the VirtFS share (containing the kernel modules)
should have been mounted before udev coldplugged all devices (before
systemd-udev-trigger.service), and lsmod should show a bunch of modules that
have been automatically loaded, e.g. something like:
```
Module                  Size  Used by
intel_rapl_msr         20480  0
ppdev                  24576  0
intel_rapl_common      57344  1 intel_rapl_msr
pktcdvd                65536  0
kvm_amd               217088  0
ccp                   180224  1 kvm_amd
kvm                  1441792  1 kvm_amd
crct10dif_pclmul       12288  1
crc32_pclmul           12288  0
crc32c_intel           16384  0
polyval_clmulni        12288  0
polyval_generic        12288  1 polyval_clmulni
ghash_clmulni_intel    16384  0
bochs                  20480  0
sha512_ssse3           53248  0
drm_vram_helper        28672  1 bochs
drm_ttm_helper         12288  2 bochs,drm_vram_helper
parport_pc             53248  0
sha256_ssse3           36864  0
ttm                   114688  2 drm_vram_helper,drm_ttm_helper
sha1_ssse3             32768  0
parport                81920  2 parport_pc,ppdev
floppy                163840  0
i2c_piix4              40960  0
pcspkr                 12288  0
joydev                 32768  0
qemu_fw_cfg            20480  0
serio_raw              20480  0
ata_generic            12288  0
pata_acpi              12288  0
msr                    12288  0
loop                   45056  0
fuse                  229376  1
```

If you need to modify a kernel module, you do not need to restart your QEMU
machine, you can simply edit the kernel source and then run:
```
./bkq.sh
```

This is of course assuming that your changes did not change the ABI between the
kernel and your module. (In case of an ABI change, you need to reboot your VM.)

Then on your QEMU machine, run:
```
sudo rmmod <module>
sudo modprobe <module>
```

and enjoy being able to quickly test new changes without rebooting your VM.

<br />

NOTE: The bkq.sh script sets LOCALVERSION= in order to avoid silly suffixes
being added to the kernel modules directory (e.g. -dirty or +). Without this,
the running kernel version string (e.g. 6.10.0-rc4) would not match the kernel
version string of your build (e.g. 6.10.0-rc4-dirty), which means that you
would not be able rmmod + modprobe without rebooting your VM.

This means that if you invoke **make** directly without having LOCALVERSION
set to the empty string, make will rebuild all kernel modules. Therefore, either
always build using bkq.sh, or if invoking make directly, make sure that the
environment variable LOCALVERSION is set to the empty string, e.g.
**make LOCALVERSION=**, in order to avoid recompiling modules needlessly.
