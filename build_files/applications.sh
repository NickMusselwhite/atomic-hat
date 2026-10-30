#!/bin/bash
set -euo pipefail

# Steam and gaming utilities
dnf5 install -y --setopt=install_weak_deps=False \
    steam \
    steam-devices \
    gamemode \
    mangohud \
    xorg-x11-drv-nvidia-libs.i686

# Browsers — Fedora-maintained Chromium for PWAs and backup browsing.
dnf5 install -y --setopt=install_weak_deps=False chromium

# Zoom Workplace — official RPM, verified with Zoom's current signing key.
# Zoom changed signing keys in 2026. Never suppress RPM signature checks.
zoom_dir="$(mktemp -d)"
trap 'rm -rf "${zoom_dir}"' EXIT
curl -fL --retry 3 --output "${zoom_dir}/zoom.rpm" \
    https://zoom.us/client/latest/zoom_x86_64.rpm
curl -fL --retry 3 --output "${zoom_dir}/zoom.pub" \
    'https://zoom.us/linux/download/pubkey'
# GPG needs a writable home; the bootc build does not provide /root/.gnupg.
install -d -m 0700 "${zoom_dir}/gnupg"
zoom_fingerprint="$(gpg --homedir "${zoom_dir}/gnupg" --show-keys --with-colons "${zoom_dir}/zoom.pub" | awk -F: '$1 == "fpr" {print $10; exit}')"
test "${zoom_fingerprint}" = 84C365D6CC9A4886CA926BCC4F2197399706AC24
rpm --import "${zoom_dir}/zoom.pub"
rpm -K "${zoom_dir}/zoom.rpm" | tee "${zoom_dir}/verify.txt"
grep -Eq 'signatures OK|pgp .* OK' "${zoom_dir}/verify.txt"
test "$(rpm -qp --qf '%{ARCH}' "${zoom_dir}/zoom.rpm")" = x86_64
dnf5 install -y "${zoom_dir}/zoom.rpm"
rpm -q zoom
rm -rf "${zoom_dir}"
trap - EXIT

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

# Verify the official RPM's security-sensitive helper permissions.
# The RPM post-install script sets these; do not modify them here.
browser_helper=/opt/1Password/1Password-BrowserSupport
test -f "${browser_helper}" && test -x "${browser_helper}"
test "$(stat -c %u "${browser_helper}")" = 0
test "$(stat -c %g "${browser_helper}")" = 1500
test -g "${browser_helper}"

# MCP support is optional. Only validate the helper when the RPM includes it.
mcp_helper=/opt/1Password/1password-mcp
if [[ -e "${mcp_helper}" ]]; then
    test -f "${mcp_helper}" && test -x "${mcp_helper}"
    test "$(stat -c %u "${mcp_helper}")" = 0
    test "$(stat -c %g "${mcp_helper}")" = 1700
    test -g "${mcp_helper}"
fi

# Electron bundles its own Chromium sandbox; it requires setuid root.
sandbox=/opt/1Password/chrome-sandbox
test -f "${sandbox}" && test -x "${sandbox}"
test "$(stat -c %u "${sandbox}")" = 0
test "$(stat -c %a "${sandbox}")" = 4755

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
