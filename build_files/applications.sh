#!/bin/bash
set -euo pipefail

# Steam and gaming utilities
dnf5 install -y --setopt=install_weak_deps=False \
    steam \
    steam-devices \
    gamemode \
    mangohud \
    xorg-x11-drv-nvidia-libs.i686

# 1Password — create the reserved groups before RPM scriptlets execute.
# Persistent declarations are copied from system_files by build.sh.
sysusers_config=/usr/lib/sysusers.d/atomic-hat-1password.conf
test -s "${sysusers_config}"

# Refuse an unexpected existing name or GID, including either direction.
for spec in 'onepassword:1500' 'onepassword-cli:1600' 'onepassword-mcp:1700'; do
    name="${spec%%:*}"
    gid="${spec##*:}"
    by_name="$(getent group "${name}" || true)"
    by_gid="$(getent group "${gid}" || true)"
    if [[ -n "${by_name}" && "$(cut -d: -f3 <<< "${by_name}")" != "${gid}" ]] ||
       [[ -n "${by_gid}" && "${by_gid%%:*}" != "${name}" ]]; then
        echo "Conflicting group reservation: ${spec}" >&2
        exit 1
    fi
done
systemd-sysusers "${sysusers_config}"
for spec in 'onepassword:1500' 'onepassword-cli:1600' 'onepassword-mcp:1700'; do
    name="${spec%%:*}"
    gid="${spec##*:}"
    test "$(getent group "${name}" | cut -d: -f3)" = "${gid}"
done

# Let the official RPM configure the helpers and their permission bits.
rpm --import /etc/pki/rpm-gpg/1password.asc
dnf5 install -y 1password

# Verify the RPM's installed helper ownership/modes; do not modify them.
# KeyringHelper needs setuid+setgid, BrowserSupport needs setgid.
for helper in /opt/1Password/1Password-KeyringHelper /opt/1Password/1Password-BrowserSupport; do
    test -f "${helper}" && test -x "${helper}"
    test "$(stat -c %u "${helper}")" = 0
    test "$(stat -c %g "${helper}")" = 1500
    test -g "${helper}"
done
test -u /opt/1Password/1Password-KeyringHelper

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
