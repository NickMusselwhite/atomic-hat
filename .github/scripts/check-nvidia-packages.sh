#!/usr/bin/env bash
# Run inside registry.fedoraproject.org/fedora:45 before starting an image build.
set -euo pipefail

: "${KERNEL_VERSION:?Preflight requires the kernel from the pinned Kinoite image}"
[[ "${KERNEL_VERSION}" == *fc45.x86_64 ]] || {
  echo "::error::Unexpected Fedora 45 kernel: ${KERNEL_VERSION}" >&2
  exit 1
}

format='%{name}-%{version}-%{release}.%{arch}\n'
for pkg in kernel-devel kernel-devel-matched; do
  expected="${pkg}-${KERNEL_VERSION}"
  available="$(dnf5 repoquery --available --queryformat "${format}" "${pkg}")"
  if ! grep -Fxq "${expected}" <<< "${available}"; then
    echo "::error title=Kernel mismatch::Missing ${expected}" >&2
    exit 1
  fi
  echo "MATCH: ${expected}"
done

# Match the repositories and signature checks used by the actual image build.
dnf5 install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-45.noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-45.noarch.rpm

# Ensure the exact same NVIDIA driver version-release is published for both
# the build-source package and every userspace package needed by Atomic Hat.
get_versions() {
  local package="$1"
  dnf5 repoquery --available --queryformat '%{version}-%{release}\n' "${package}" | sort -u
}

builder_versions="$(get_versions akmod-nvidia)"
runtime_versions="$(get_versions xorg-x11-drv-nvidia)"
if [[ -z "${builder_versions}" || -z "${runtime_versions}" ]]; then
  echo '::error title=NVIDIA unavailable::Missing akmod-nvidia or NVIDIA runtime driver' >&2
  exit 1
fi

compatible_version=''
while IFS= read -r version; do
  if grep -Fxq "${version}" <<< "${runtime_versions}"; then
    compatible_version="${version}"
    break
  fi
done <<< "${builder_versions}"

if [[ -z "${compatible_version}" ]]; then
  echo "::error title=NVIDIA version mismatch::No compatible build and runtime driver" >&2
  exit 1
fi

for pkg in xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-power xorg-x11-drv-nvidia-kmodsrc; do
  if ! grep -Fxq "${compatible_version}" <<< "$(get_versions "${pkg}")"; then
    echo "::error title=NVIDIA package mismatch::Missing ${pkg} ${compatible_version}" >&2
    exit 1
  fi
  echo "MATCH: ${pkg} ${compatible_version}"
done

# Validate that the graphics/codec repositories are populated as well.
for pkg in mesa-va-drivers-freeworld mesa-vulkan-drivers-freeworld ffmpeg; do
  if [[ -z "$(get_versions "${pkg}")" ]]; then
    echo "::error title=RPM Fusion package unavailable::Missing ${pkg}" >&2
    exit 1
  fi
  echo "AVAILABLE: ${pkg}"
done

echo "Preflight passed: kernel ${KERNEL_VERSION}, NVIDIA ${compatible_version}"
