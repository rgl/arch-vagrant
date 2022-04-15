#!/usr/bin/bash
set -euxo pipefail


# wait for the system to finish its initialization.
# NB this is required because, at least, the pacman-init.service might still
#    be initialing, and when that happens, unexpected errors crop up at the
#    pacstrap step with errors alike:
#       pacstrap failed to initialize pacman keyring
#       error keyring is not writable
systemctl is-system-running --wait
systemd-analyze


firmware="$([ -d /sys/firmware/efi ] && echo 'uefi' || echo 'bios')"
boot_device=/dev/sda
extra_packages=()

if [ "$firmware" == 'uefi' ]; then
    extra_packages+=('efibootmgr')
elif [ "$firmware" == 'bios' ]; then
    extra_packages+=('grub')
else
    echo "unknown firmware: $firmware"
    exit 1
fi

# update the system time from NTP.
timedatectl set-ntp true
while [ "$(timedatectl show -p NTPSynchronized)" != 'NTPSynchronized=yes' ]; do sleep 3; done

# format and mount the boot disk.
if [ "$firmware" == 'uefi' ]; then
    # NB by default systemd-boot expects /boot to be in the ESP.
    parted --script $boot_device mklabel gpt
    parted --script $boot_device mkpart primary fat32 1MiB 100MiB
    parted --script $boot_device set 1 esp on
    parted --script $boot_device set 1 boot on
    parted --script $boot_device mkpart primary ext4 100MiB 100%
    mkfs -t vfat -n ESP ${boot_device}1
    mkfs -t ext4 -L ROOT -F ${boot_device}2
    mount ${boot_device}2 /mnt
    mount ${boot_device}1 /mnt/boot --mkdir
elif [ "$firmware" == 'bios' ]; then
    parted --script $boot_device mklabel msdos
    parted --script $boot_device mkpart primary ext4 1MiB 100%
    parted --script $boot_device set 1 boot on
    mkfs -t ext4 -L ROOT -F ${boot_device}1
    mount ${boot_device}1 /mnt
else
    echo "unknown firmware: $firmware"
    exit 1
fi

# install base system.
# TODO set mirror.
sed -i -E 's,^#?(ParallelDownloads)\s*=.*,\1 = 5,g' /etc/pacman.conf
pacstrap /mnt base linux openssh vim ${extra_packages[@]}
genfstab -U /mnt >>/mnt/etc/fstab

# revert the systemd.mask=sshd.service kernel command line so we can enable
# ssh from within the arch-chroot.
rm /run/systemd/generator.early/sshd.service

# configure the system.
arch-chroot /mnt bash <<'INSTALL_EOF'
set -euxo pipefail
sed -i -E 's,^#?(ParallelDownloads)\s*=.*,\1 = 5,g' /etc/pacman.conf
timedatectl set-ntp true
ln -sf /usr/share/zoneinfo/Europe/Lisbon /etc/localtime
hwclock --systohc
systemctl enable systemd-timesyncd.service
cat >/etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
pt_PT.UTF-8 UTF-8
EOF
cat >/etc/locale.conf <<'EOF'
LANG=en_US.UTF-8
EOF
cat >/etc/vconsole.conf <<'EOF'
KEYMAP=pt-latin1
EOF
locale-gen
echo 'root:vagrant' | chpasswd
cat >/etc/systemd/network/eth0.network <<'EOF'
[Match]
Name=eth0

[Network]
DHCP=yes
EOF
systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
sed -i -E 's,^#?(PermitRootLogin)\s*.*,\1 yes,g' /etc/ssh/sshd_config
systemctl enable sshd.service
INSTALL_EOF

# configure the resolver to use systemd-resolved.
# NB this cannot be done from within the arch-chroot.
ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

# install the bootloader.
# under uefi install systemd-boot.
# under bios install grub.
if [ "$firmware" == 'uefi' ]; then
    arch-chroot /mnt bash <<'INSTALL_EOF'
set -euxo pipefail
bootctl install
cat >/boot/loader/loader.conf <<'EOF'
timeout 4
console-mode max
editor no
EOF
cat >/boot/loader/entries/arch.conf <<'EOF'
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root="LABEL=ROOT" net.ifnames=0
EOF
cat >/boot/loader/entries/arch-fallback.conf <<'EOF'
title Arch Linux (fallback initramfs)
linux /vmlinuz-linux
initrd /initramfs-linux-fallback.img
options root="LABEL=ROOT" net.ifnames=0
EOF
systemctl enable systemd-boot-update.service
INSTALL_EOF
elif [ "$firmware" == 'bios' ]; then
    arch-chroot /mnt bash <<INSTALL_EOF
set -euxo pipefail
grub-install --target=i386-pc $boot_device
sed -i -E 's,^(GRUB_CMDLINE_LINUX_DEFAULT)\s*=.*,\1="net.ifnames=0",g' /etc/default/grub
sed -i -E 's,^#?(GRUB_TERMINAL_OUTPUT)\s*=.*,\1=console,g' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
INSTALL_EOF
else
    echo "unknown firmware: $firmware"
    exit 1
fi

# umount the boot disk.
umount -R /mnt

# reboot into the installed system.
reboot
