#!/usr/bin/env bash
set -euo pipefail

# Install the desktop software into the clean runtime.
# NVIDIA modules were signed in nvidia-builder and installed from a temporary
# read-only mount; do not install akmods or compilation dependencies here.

# applications.sh depends on the signed third-party repository definitions,
# 1Password group reservations, and other system customizations.
cp -avf /ctx/system_files/. /

# Match the codecs and Mesa replacements performed by the existing build.
# Keep these operations before applications.sh, just as in build.sh.
if rpm -q ffmpeg-free >/dev/null 2>&1; then
    dnf5 swap -y --allowerasing ffmpeg-free ffmpeg
else
    dnf5 install -y --allowerasing ffmpeg
fi

dnf5 install -y mesa-va-drivers-freeworld
if rpm -q mesa-vulkan-drivers >/dev/null 2>&1; then
    dnf5 swap -y --allowerasing mesa-vulkan-drivers mesa-vulkan-drivers-freeworld
else
    dnf5 install -y mesa-vulkan-drivers-freeworld
fi

# tmux is presently installed by build.sh alongside the NVIDIA drivers.
# It is a runtime utility, not part of compiling NVIDIA.
dnf5 install -y --setopt=install_weak_deps=False tmux

# Reuse the exact application installer from the known-good image. This
# includes Steam, 32-bit NVIDIA libraries, Zoom, 1Password, Sunshine,
# virtualization tools, shell utilities, and their existing security checks.
bash /ctx/applications.sh
systemctl enable podman.socket

# Check a representative set of installed applications and media packages.
# The installation commands above remain the source of truth for the full set.
rpm -q bootc kernel-core plasma-workspace mesa-dri-drivers \
    ffmpeg ffmpeg-libs mesa-va-drivers-freeworld \
    mesa-vulkan-drivers-freeworld tmux steam chromium zoom \
    1password distrobox fish fastfetch qemu-kvm virt-manager Sunshine \
    xorg-x11-drv-nvidia-libs.i686 libva-nvidia-driver
# Capture the full listing first so grep -q cannot SIGPIPE ffmpeg.
ffmpeg -hide_banner -encoders > /tmp/atomic-hat-encoders.txt
grep -q 'libx264' /tmp/atomic-hat-encoders.txt
grep -q 'h264_nvenc' /tmp/atomic-hat-encoders.txt
rm -f /tmp/atomic-hat-encoders.txt
command -v nvidia-smi
echo 'PASS: clean NVIDIA runtime installed Atomic Hat desktop applications'

# Reject an accidental reintroduction of the NVIDIA compilation environment.
for pkg in akmods akmod-nvidia kernel-devel kernel-devel-matched \
           gcc make rpm-build dwarves xorg-x11-drv-nvidia-kmodsrc; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
        echo "Unexpected build-only package in clean runtime: $pkg" >&2
        exit 1
    fi
done

# Avoid leaving DNF transient files and logs in the experimental runtime.
dnf5 clean all
rm -rf -- /run/dnf /run/akmods /run/gluster /run/selinux-policy
rm -f -- /var/log/dnf5.log
