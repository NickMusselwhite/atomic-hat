#!/bin/bash
set -euo pipefail

# Steam and gaming utilities
dnf5 install -y --setopt=install_weak_deps=False \
    steam \
    steam-devices \
    gamemode \
    mangohud \
    xorg-x11-drv-nvidia-libs.i686

# 1Password — stable GIDs for browser integration and future CLI use.
# In a bootc image, /etc/group is recreated on the installed system.
# Reserve the numeric groups in /usr so the installed IDs match the image.
install -d -m 0755 /usr/lib/sysusers.d
cat > /usr/lib/sysusers.d/atomic-hat-1password.conf <<'EOF'
g onepassword 1500
g onepassword-cli 1600
EOF

# Initialize the same GIDs during the build before the RPM scriptlets run.
# Refuse conflicts rather than silently assigning the wrong numeric owner.
for spec in 'onepassword:1500' 'onepassword-cli:1600'; do
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
systemd-sysusers /usr/lib/sysusers.d/atomic-hat-1password.conf

# Install 1Password from its official signed RPM repository.
rpm --import /etc/pki/rpm-gpg/1password.asc
dnf5 install -y 1password

# Preserve the permissions set by 1Password's RPM scripts. Only ensure that
# the browser helper's numeric GID matches the group recreated on first boot.
browser_helper=/opt/1Password/1Password-BrowserSupport
test -f "${browser_helper}"
test "$(stat -c %u "${browser_helper}")" = 0
test -g "${browser_helper}"
chgrp 1500 "${browser_helper}"
test "$(stat -c %g "${browser_helper}")" = 1500

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
