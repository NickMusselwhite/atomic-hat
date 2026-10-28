#!/bin/bash
set -euo pipefail

# Steam and gaming utilities
dnf5 install -y --setopt=install_weak_deps=False \
    steam \
    steam-devices \
    gamemode \
    mangohud \
    xorg-x11-drv-nvidia-libs.i686

# 1Password — official signed RPM repository
# The signing key is verified and included in system_files.
rpm --import /etc/pki/rpm-gpg/1password.asc

dnf5 install -y 1password

# Distrobox — mutable development environments
dnf5 install -y --setopt=install_weak_deps=False distrobox

# NVIDIA VA-API decoding and AppImage FUSE 2 compatibility
dnf5 install -y --setopt=install_weak_deps=False \
    libva-nvidia-driver \
    libva-utils \
    fuse \
    fuse-libs

# Interactive shell and system information
dnf5 install -y --setopt=install_weak_deps=False \
    fish \
    fastfetch

# Virtualization — Windows 11 VM support
dnf5 install -y --setopt=install_weak_deps=False \
    qemu-kvm \
    libvirt-daemon-kvm \
    libvirt-client \
    virt-manager \
    virt-viewer \
    virt-install \
    edk2-ovmf \
    swtpm \
    passt \
    virtiofsd \
    freerdp

# Sunshine — official LizardByte stable RPM repository
rpm --import /etc/pki/rpm-gpg/lizardbyte-stable.asc

dnf5 install -y --setopt=install_weak_deps=False Sunshine
