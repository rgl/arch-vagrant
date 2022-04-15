#!/bin/bash
set -euxo pipefail

# install the vagrant public key.
# NB vagrant will replace it on the first run.
install -d -m 700 ~/.ssh
install -m 600 /dev/null ~/.ssh/authorized_keys
curl -s https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant.pub >~/.ssh/authorized_keys

# install cloud-init.
# see https://wiki.archlinux.org/title/Cloud-init
pacman -S --noconfirm cloud-init cloud-guest-utils
cat >/etc/cloud/cloud.cfg.d/95_default_user.cfg <<'EOF'
system_info:
  default_user:
    name: root
EOF
# limit the datasources to the supported hypervisors/environments.
# NB this is especially required for not waiting for datasources that try to
#    contact the metadata service at http://169.254.169.254 (like the AWS
#    datasource) that do not exist in our supported hypervisors.
# NB you cannot use debconf-set-selections with dpkg-reconfigure (it ignores
#    debconf), so we have to directly edit the configuration.
cat >/etc/cloud/cloud.cfg.d/95_datasources.cfg <<'EOF'
datasource_list:
  - NoCloud
  - VMware
  - None
EOF
systemctl enable cloud-init.service
systemctl enable cloud-final.service

# install the nfs client to support nfs synced folders in vagrant.
pacman -S --noconfirm nfs-utils

# install the smb client to support cifs/smb/samba synced folders in vagrant.
pacman -S --noconfirm cifs-utils

# install rsync to support rsync synced folders in vagrant.
pacman -S --noconfirm rsync

# disable the DNS reverse lookup on the SSH server. this stops it from
# trying to resolve the client IP address into a DNS domain name, which
# is kinda slow and does not normally work when running inside VB.
echo UseDNS no >>/etc/ssh/sshd_config

# use the up/down arrows to navigate the bash history.
# NB to get these codes, press ctrl+v then the key combination you want.
cat >/etc/inputrc <<'EOF'
"\e[A": history-search-backward
"\e[B": history-search-forward
set show-all-if-ambiguous on
set completion-ignore-case on
EOF

# reset the machine-id.
# NB systemd will re-generate it on the next boot.
# NB machine-id is indirectly used in DHCP as Option 61 (Client Identifier), which
#    the DHCP server uses to (re-)assign the same or new client IP address.
# see https://www.freedesktop.org/software/systemd/man/machine-id.html
# see https://www.freedesktop.org/software/systemd/man/systemd-machine-id-setup.html
echo '' >/etc/machine-id
rm -f /var/lib/dbus/machine-id

# reset the random-seed.
# NB systemd-random-seed re-generates it on every boot and shutdown.
# NB you can prove that random-seed file does not exist on the image with:
#       sudo virt-filesystems -a ~/.vagrant.d/boxes/arch-amd64/0/libvirt/box.img
#       sudo guestmount -a ~/.vagrant.d/boxes/arch-amd64/0/libvirt/box.img -m /dev/sda1 --pid-file guestmount.pid --ro /mnt
#       sudo ls -laF /mnt/var/lib/systemd
#       sudo guestunmount /mnt
#       sudo bash -c 'while kill -0 $(cat guestmount.pid) 2>/dev/null; do sleep .1; done; rm guestmount.pid' # wait for guestmount to finish.
# see https://www.freedesktop.org/software/systemd/man/systemd-random-seed.service.html
# see https://man.archlinux.org/man/random.4
# see https://man.archlinux.org/man/random.7
# see https://github.com/systemd/systemd/blob/master/src/random-seed/random-seed.c
# see https://github.com/torvalds/linux/blob/master/drivers/char/random.c
systemctl stop systemd-random-seed
rm -f /var/lib/systemd/random-seed

# clean packages.
(pacman -Qtdq || true) | xargs --no-run-if-empty pacman -Rns
# NB we use "|| true" because yes will fail the pipeline with 141.
yes | pacman -Scc || true

# zero the free disk space -- for better compression of the box file.
# NB prefer discard/trim (safer; faster) over creating a big zero filled file
#    (somewhat unsafe as it has to fill the entire disk, which might trigger
#    a disk (near) full alarm; slower; slightly better compression).
root_dev="$(findmnt -no SOURCE /)"
if [ "$(lsblk -no DISC-GRAN $root_dev | awk '{print $1}')" != '0B' ]; then
    while true; do
        output="$(fstrim -v /)"
        cat <<<"$output"
        sync && sync && sync && blockdev --flushbufs $root_dev && sleep 15
        if [ "$output" == '/: 0 B (0 bytes) trimmed' ]; then
            break
        fi
    done
else
    dd if=/dev/zero of=/EMPTY bs=1M || true; rm -f /EMPTY
fi
