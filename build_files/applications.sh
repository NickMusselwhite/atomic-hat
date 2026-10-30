#!/bin/bash
set -euo pipefail

# Steam and gaming utilities
dnf5 install -y --setopt=install_weak_deps=False \
    steam \
    steam-devices \
    gamemode \
    mangohud \
    xorg-x11-drv-nvidia-libs.i686

# 1Password — reserve stable helper GIDs before installing the RPM.
# These numeric IDs match Universal Blue's convention. The declarations
# recreate the groups on first boot, when /etc is initialized.
install -d -m 0755 /usr/lib/sysusers.d
cat > /usr/lib/sysusers.d/atomic-hat-1password.conf <<'EOF'
g onepassword 1500
g onepassword-cli 1600
EOF

# Refuse to reuse an ID already assigned to an unrelated build-time group.
for spec in 'onepassword:1500' 'onepassword-cli:1600'; do
    name="${spec%%:*}"
    gid="${spec##*:}"
    existing="$(getent group "${gid}" || true)"
    if [[ -n "${existing}" && "${existing%%:*}" != "${name}" ]]; then
        echo "GID ${gid} is already assigned: ${existing}" >&2
        exit 1
    fi
done
systemd-sysusers /usr/lib/sysusers.d/atomic-hat-1password.conf
test "$(getent group onepassword | cut -d: -f3)" = 1500
test "$(getent group onepassword-cli | cut -d: -f3)" = 1600

# Official signed RPM repository (key provided in system_files).
rpm --import /etc/pki/rpm-gpg/1password.asc
dnf5 install -y 1password

# The browser helper must belong to the persistent 1Password group.
# Preserve its packaged setgid bit, while fixing the numeric group owner.
browser_helper=/opt/1Password/1Password-BrowserSupport
test -f "${browser_helper}"
chgrp 1500 "${browser_helper}"
chmod g+s "${browser_helper}"
test "$(stat -c %g "${browser_helper}")" = 1500
test -g "${browser_helper}"

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
