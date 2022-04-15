#!/bin/bash
set -euxo pipefail

# install the Guest Additions.
if [ -n "$(lspci | grep 'Red Hat' | head -1)" ]; then
    # install the qemu-kvm Guest Additions.
    pacman -S --noconfirm qemu-guest-agent
    systemctl enable qemu-guest-agent.service
else
    echo 'ERROR: Unknown VM host.'
    exit 1
fi

# reboot.
nohup bash -c "ps -eo pid,comm | awk '/sshd/{print \$1}' | xargs kill; sync; reboot"
