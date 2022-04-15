variable "disk_size" {
  type    = string
  default = "30720"
}

variable "iso_url" {
  type    = string
  default = "https://ftp.rnl.tecnico.ulisboa.pt/pub/archlinux/iso/2022.04.05/archlinux-2022.04.05-x86_64.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:5934a1561f33a49574ba8bf6dbbdbd18c933470de4e2f7562bec06d24f73839b"
}

variable "vagrant_box" {
  type = string
}

source "qemu" "arch-amd64" {
  accelerator = "kvm"
  qemuargs = [
    ["-m", "2048"],
    ["-smp", "2"],
    ["-device", "virtio-scsi-pci,id=scsi0"],
    ["-device", "scsi-hd,bus=scsi0.0,drive=drive0"],
    ["-object", "rng-random,filename=/dev/urandom,id=rng0"],
    ["-device", "virtio-rng-pci,rng=rng0"],
  ]
  headless = true
  http_directory = "."
  format = "qcow2"
  disk_size = var.disk_size
  disk_interface = "virtio-scsi"
  disk_discard = "unmap"
  iso_url = var.iso_url
  iso_checksum = var.iso_checksum
  ssh_username = "root"
  ssh_password = "vagrant"
  ssh_timeout = "30m"
  boot_wait = "5s"
  boot_command = [
    "<tab>",
    " ipv6.disable=1",
    " ip=dhcp",
    " net.ifnames=0",
    " systemd.mask=sshd.service",
    " script=http://{{.HTTPIP}}:{{.HTTPPort}}/install.sh",
    "<enter>",
  ]
  shutdown_command = "poweroff"
}

source "qemu" "arch-uefi-amd64" {
  accelerator = "kvm"
  qemuargs = [
    ["-bios", "/usr/share/ovmf/OVMF.fd"],
    ["-m", "2048"],
    ["-smp", "2"],
    ["-device", "virtio-scsi-pci,id=scsi0"],
    ["-device", "scsi-hd,bus=scsi0.0,drive=drive0"],
    ["-object", "rng-random,filename=/dev/urandom,id=rng0"],
    ["-device", "virtio-rng-pci,rng=rng0"],
  ]
  headless = true
  http_directory = "."
  format = "qcow2"
  disk_size = var.disk_size
  disk_interface = "virtio-scsi"
  disk_discard = "unmap"
  iso_url = var.iso_url
  iso_checksum = var.iso_checksum
  ssh_username = "root"
  ssh_password = "vagrant"
  ssh_timeout = "30m"
  boot_wait = "5s"
  boot_command = [
    "e<end>",
    " ipv6.disable=1",
    " ip=dhcp",
    " net.ifnames=0",
    " systemd.mask=sshd.service",
    " script=http://{{.HTTPIP}}:{{.HTTPPort}}/install.sh",
    "<enter>",
  ]
  shutdown_command = "poweroff"
}

build {
  sources = [
    "source.qemu.arch-amd64",
    "source.qemu.arch-uefi-amd64",
  ]

  provisioner "shell" {
    expect_disconnect = true
    scripts = [
      "provision-guest-additions.sh",
      "provision.sh",
    ]
  }

  post-processor "vagrant" {
    only = [
      "qemu.arch-amd64",
    ]
    output = var.vagrant_box
    vagrantfile_template = "Vagrantfile.template"
  }

  post-processor "vagrant" {
    only = [
      "qemu.arch-uefi-amd64",
    ]
    output = var.vagrant_box
    vagrantfile_template = "Vagrantfile-uefi.template"
  }
}
