#!/bin/bash
set -euo pipefail

# Steam and gaming utilities
dnf5 install -y --setopt=install_weak_deps=False \
    steam \
    steam-devices \
    gamemode \
    mangohud \
    xorg-x11-drv-nvidia-libs.i686

# 1Password — stable group IDs for privileged Linux integrations.
# GIDs 1500 and 1600 follow Universal Blue's browser/CLI convention.
# The MCP group uses our own reserved GID 1700. The CLI package is not
# installed here, but reserving its group allows a future image-managed install.
# Keep declarations in /usr so new bootc installations recreate them at boot.
install -d -m 0755 /usr/lib/sysusers.d
cat > /usr/lib/sysusers.d/atomic-hat-1password.conf <<'EOF'
g onepassword 1500
g onepassword-cli 1600
g onepassword-mcp 1700
EOF

# Fail the image build if any reserved name or GID already belongs to
# something else. Do not attempt to migrate groups from an existing install.
for spec in 'onepassword:1500' 'onepassword-cli:1600' 'onepassword-mcp:1700'; do
    name="${spec%%:*}"
    gid="${spec##*:}"
    existing_by_name="$(getent group "${name}" || true)"
    existing_by_gid="$(getent group "${gid}" || true)"
    if [[ -n "${existing_by_name}" && "$(cut -d: -f3 <<< "${existing_by_name}")" != "${gid}" ]]; then
        echo "Group ${name} has an unexpected GID: ${existing_by_name}" >&2
        exit 1
    fi
    if [[ -n "${existing_by_gid}" && "${existing_by_gid%%:*}" != "${name}" ]]; then
        echo "GID ${gid} already belongs to ${existing_by_gid%%:*}" >&2
        exit 1
    fi
done
systemd-sysusers /usr/lib/sysusers.d/atomic-hat-1password.conf
for spec in 'onepassword:1500' 'onepassword-cli:1600' 'onepassword-mcp:1700'; do
    name="${spec%%:*}"
    gid="${spec##*:}"
    test "$(getent group "${name}" | cut -d: -f3)" = "${gid}"
done

# Official signed RPM repository (key provided in system_files).
rpm --import /etc/pki/rpm-gpg/1password.asc
dnf5 install -y 1password

# Set group ownership on the two helpers bundled with the desktop RPM.
# Verify they are root-owned package binaries before enabling setgid.
# The separate op CLI binary is not installed or modified by this image.
for helper_spec in \
    '/opt/1Password/1Password-BrowserSupport:1500' \
    '/opt/1Password/1password-mcp:1700'; do
    helper="${helper_spec%:*}"
    gid="${helper_spec##*:}"
    test -f "${helper}" && test -x "${helper}"
    test "$(stat -c %u "${helper}")" = 0
    rpm -qf "${helper}" >/dev/null
    chgrp "${gid}" "${helper}"
    chmod g+s "${helper}"
    test "$(stat -c %g "${helper}")" = "${gid}"
    test -g "${helper}"
done

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
