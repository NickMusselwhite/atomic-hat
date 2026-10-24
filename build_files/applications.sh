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
