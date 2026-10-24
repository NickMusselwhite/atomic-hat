#!/bin/bash
set -euo pipefail

# Steam and gaming utilities
dnf5 install -y --setopt=install_weak_deps=False \
    steam \
    steam-devices \
    gamemode \
    mangohud \
    xorg-x11-drv-nvidia-libs.i686
