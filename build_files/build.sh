#!/bin/bash

set -euo pipefail

# Select the open NVIDIA module independently of the CI runner's hardware.
cp -avf /ctx/system_files/. /

fedora_version="$(rpm -E %fedora)"
architecture="$(rpm -E '%{_arch}')"
if [[ "${fedora_version}" != 44 || "${architecture}" != x86_64 ]]; then
    echo 'This package selection targets Fedora 44 on x86_64.' >&2
    exit 1
fi

# Use the kernel IN the image, never uname -r (the builder's kernel).
kernel="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n')"
if [[ -z "${kernel}" || "${kernel}" == *$'\n'* ]]; then
    echo 'Expected exactly one kernel-core in the base image.' >&2
    exit 1
fi

# Stock Kinoite does not enable RPM Fusion. Retain RPM signature checking.
dnf5 install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"

# Fail if matching headers are unavailable; retry with a newer base image.
dnf5 install -y --setopt=install_weak_deps=False \
    "kernel-devel-${kernel}" \
    "kernel-devel-matched-${kernel}" \
    gcc make elfutils-libelf-devel rpm-build redhat-rpm-config \
    akmods kmodtool pciutils dwarves util-linux

# Fedora Atomic's automatic hook invokes akmodsbuild as root and makes the
# DNF transaction fail. Defer only that hook to the explicit unprivileged
# build below; restore the packaged script immediately after installation.
akmods_hook="$(rpm -ql akmods | grep '/akmods-ostree-post$')"
test -f "${akmods_hook}"
mv "${akmods_hook}" "${akmods_hook}.atomic-hat-original"
restore_akmods_hook() {
    mv -f "${akmods_hook}.atomic-hat-original" "${akmods_hook}"
}
trap restore_akmods_hook EXIT
printf '#!/bin/sh\nexit 0\n' > "${akmods_hook}"
chmod 0755 "${akmods_hook}"
dnf5 install -y --exclude='kernel*' --setopt=install_weak_deps=False \
    akmod-nvidia \
    xorg-x11-drv-nvidia \
    xorg-x11-drv-nvidia-cuda \
    xorg-x11-drv-nvidia-power \
    tmux
restore_akmods_hook
trap - EXIT

# Replace Fedora's restricted FFmpeg build and its split libraries.
if rpm -q ffmpeg-free >/dev/null 2>&1; then
    dnf5 swap -y --allowerasing ffmpeg-free ffmpeg
else
    dnf5 install -y --allowerasing ffmpeg
fi

# On Fedora 44 VA-API is part of mesa-dri-drivers; Freeworld coexists with
# it. VDPAU is no longer a separate Mesa Freeworld package.
dnf5 install -y mesa-va-drivers-freeworld
if rpm -q mesa-vulkan-drivers >/dev/null 2>&1; then
    dnf5 swap -y --allowerasing mesa-vulkan-drivers mesa-vulkan-drivers-freeworld
else
    dnf5 install -y mesa-vulkan-drivers-freeworld
fi

# RPM scriptlets alone do not reliably build akmods in an OCI build. Build
# as an unprivileged user, then install the generated kmod RPM as root.
test "$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n')" = "${kernel}"
test -f "/usr/src/kernels/${kernel}/Makefile"
test -r /usr/src/akmods/nvidia-kmod.latest
getent passwd akmods >/dev/null
build_dir="$(mktemp -d /tmp/atomic-hat-nvidia.XXXXXXXX)"
trap 'rm -rf "${build_dir}"' EXIT
chown akmods:akmods "${build_dir}"
runuser -u akmods -- akmodsbuild \
    --kernels "${kernel}" \
    --outputdir "${build_dir}" \
    /usr/src/akmods/nvidia-kmod.latest

shopt -s nullglob
module_rpms=("${build_dir}"/kmod-nvidia-*.rpm)
if (( ${#module_rpms[@]} == 0 )); then
    echo 'The NVIDIA build did not produce a kernel module RPM.' >&2
    exit 1
fi
dnf5 install -y "${module_rpms[@]}"
depmod -a "${kernel}"

# Verify every runtime module matches the kernel and user-space driver.
driver_version="$(rpm -q xorg-x11-drv-nvidia --qf '%{VERSION}')"
for module in nvidia nvidia_modeset nvidia_drm nvidia_uvm; do
    test "$(modinfo -k "${kernel}" -F version "${module}")" = "${driver_version}"
    [[ "$(modinfo -k "${kernel}" -F vermagic "${module}")" == "${kernel} "* ]]
done
[[ "$(modinfo -k "${kernel}" -F license nvidia)" == *MIT* ]]

# Catch unwanted erasures and missing codecs before publication.
rpm -q bootc kernel-core plasma-workspace mesa-dri-drivers \
    mesa-va-drivers-freeworld mesa-vulkan-drivers-freeworld \
    ffmpeg ffmpeg-libs xorg-x11-drv-nvidia-cuda
ffmpeg -hide_banner -encoders > "${build_dir}/encoders.txt"
grep -q 'libx264' "${build_dir}/encoders.txt"
grep -q 'h264_nvenc' "${build_dir}/encoders.txt"
command -v nvidia-smi

# Preserve the template's existing service customization.
systemctl enable podman.socket

# Never ship an automatically generated akmods private key. Trusted Secure
# Boot module signing remains separate work; see docs/rpmfusion.md.
rm -f /etc/pki/akmods/private/private_key.priv
dnf5 clean all

