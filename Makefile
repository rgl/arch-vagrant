SHELL=bash
.SHELLFLAGS=-euo pipefail -c

help:
	@echo type make build-libvirt or make build-uefi-libvirt

build-libvirt: arch-amd64-libvirt.box
build-uefi-libvirt: arch-uefi-amd64-libvirt.box

arch-amd64-libvirt.box: install.sh provision.sh arch.pkr.hcl Vagrantfile.template
	rm -f $@
	PACKER_KEY_INTERVAL=10ms CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=$@.log PKR_VAR_vagrant_box=$@ \
		packer build -only=qemu.arch-amd64 -on-error=abort -timestamp-ui arch.pkr.hcl
	@echo BOX successfully built!
	@echo to add to local vagrant install do:
	@echo vagrant box add -f arch-amd64 arch-amd64-libvirt.box

arch-uefi-amd64-libvirt.box: install.sh provision.sh arch.pkr.hcl Vagrantfile-uefi.template
	rm -f $@
	PACKER_KEY_INTERVAL=10ms CHECKPOINT_DISABLE=1 PACKER_LOG=1 PACKER_LOG_PATH=$@.log PKR_VAR_vagrant_box=$@ \
		packer build -only=qemu.arch-uefi-amd64 -on-error=abort -timestamp-ui arch.pkr.hcl
	@echo BOX successfully built!
	@echo to add to local vagrant install do:
	@echo vagrant box add -f arch-uefi-amd64 arch-uefi-amd64-libvirt.box

.PHONY: help buid-libvirt buid-uefi-libvirt
