#!/usr/bin/env bash
set -euo pipefail

# Validate the actual final image (and then the rechunked image), not the
# builder. The builder separately checks signatures cryptographically against
# its signing certificate; here we verify installed runtime module metadata.
kernel="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n')"
driver_version="$(rpm -q xorg-x11-drv-nvidia --qf '%{VERSION}')"
if [[ -z "$kernel" || "$kernel" == *$'\n'* || -z "$driver_version" ]]; then
    echo 'Expected exactly one installed kernel and NVIDIA driver version.' >&2
    exit 1
fi
rpm -q "kmod-nvidia-$kernel" >/dev/null
echo "Checking NVIDIA $driver_version for $kernel"

expected_signer="$(modinfo -k "$kernel" -F signer nvidia)"
if [[ -z "$expected_signer" ]]; then
    echo 'The installed NVIDIA module has no signing identity.' >&2
    exit 1
fi
# The runtime must contain the *same* public certificate that the builder
# used to verify the module signatures cryptographically. We copy it straight
# from nvidia-builder and check its identity against the installed modules.
# Full PKCS#7/CMS signature verification remains in build_files/build.sh.
certificate=/usr/share/atomic-hat/certs/nvidia-module-signing.der
if [[ ! -s "$certificate" ]]; then
    echo "Missing NVIDIA module public certificate: $certificate" >&2
    exit 1
fi
openssl x509 -inform DER -in "$certificate" -noout -checkend 0
subject="$(openssl x509 -inform DER -in "$certificate" -noout -subject -nameopt RFC2253)"
# Both release and CI certificates have a single, simple CN; refuse anything
# unexpected rather than accepting a mismatch in the certificate identity.
if [[ "$subject" != "subject=CN=$expected_signer" ]]; then
    echo "NVIDIA module signer differs from embedded certificate ($subject vs $expected_signer)" >&2
    exit 1
fi
if [[ -e /etc/pki/akmods/private/private_key.priv ]]; then
    echo 'Unexpected NVIDIA private signing key in runtime image' >&2
    exit 1
fi
echo "PASS: embedded NVIDIA public certificate matches module signer $expected_signer"

for module in nvidia nvidia_modeset nvidia_drm nvidia_uvm; do
    filename="$(modinfo -k "$kernel" -F filename "$module")"
    [[ -f "$filename" ]] || { echo "Missing module file: $module ($filename)" >&2; exit 1; }
    owner="$(rpm -qf --qf '%{NAME}' "$(readlink -f "$filename")")"
    [[ "$owner" == "kmod-nvidia-$kernel" ]] || {
        echo "Module $module is owned by unexpected RPM: $owner" >&2
        exit 1
    }
    [[ "$(modinfo -k "$kernel" -F version "$module")" == "$driver_version" ]] || {
        echo "Module $module does not match NVIDIA userspace $driver_version" >&2
        exit 1
    }
    [[ "$(modinfo -k "$kernel" -F vermagic "$module")" == "$kernel "* ]] || {
        echo "Module $module has unexpected vermagic" >&2
        exit 1
    }
    [[ "$(modinfo -k "$kernel" -F signer "$module")" == "$expected_signer" ]] || {
        echo "Module $module has a different signer" >&2
        exit 1
    }
    [[ -n "$(modinfo -k "$kernel" -F sig_key "$module")" ]] || {
        echo "Module $module has no signature key ID" >&2
        exit 1
    }
    [[ -n "$(modinfo -k "$kernel" -F sig_id "$module")" ]] || {
        echo "Module $module has no signature type" >&2
        exit 1
    }
    echo "PASS: $module matches kernel, driver and signer $expected_signer"
done

# Explicit runtime packages from applications.sh, codecs, and the desktop.
# DNF installs additional dependencies that are inventoried by CI.
required_packages=(
    bootc kernel-core plasma-workspace mesa-dri-drivers
    xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda
    xorg-x11-drv-nvidia-power xorg-x11-drv-nvidia-libs.i686
    ffmpeg ffmpeg-libs mesa-va-drivers-freeworld mesa-vulkan-drivers-freeworld
    steam steam-devices gamemode mangohud chromium zoom 1password
    distrobox libva-nvidia-driver libva-utils fuse fuse-libs
    fish fastfetch btop inxi meld ripgrep micro gamescope tmux
    qemu-kvm libvirt-daemon-kvm libvirt-client
    virt-manager virt-viewer virt-install edk2-ovmf swtpm
    passt virtiofsd freerdp Sunshine
)
for package in "${required_packages[@]}"; do
    if ! rpm -q "$package" >/dev/null 2>&1; then
        echo "Missing expected runtime package: $package" >&2
        exit 1
    fi
done
echo 'PASS: expected Atomic Hat applications and codecs are installed'

# Never ship the NVIDIA compilation toolchain in the clean final runtime.
for package in akmods akmod-nvidia kernel-devel kernel-devel-matched \
               gcc make rpm-build dwarves kmodtool xorg-x11-drv-nvidia-kmodsrc; do
    if rpm -q "$package" >/dev/null 2>&1; then
        echo "Unexpected NVIDIA build dependency in final image: $package" >&2
        exit 1
    fi
done
echo 'PASS: NVIDIA build dependencies are absent from final image'

# Verify that the signed RPM was installed, not retained as an archive.
# The temporary build mount and the builder's export must not be present in
# either the final runtime or its rechunked representation.
for archive_dir in \
    /usr/share/atomic-hat/build-artifacts/nvidia \
    /run/atomic-hat-nvidia-rpms; do
    if [[ -e "$archive_dir" ]]; then
        echo "Unexpected NVIDIA build artifact location in final image: $archive_dir" >&2
        exit 1
    fi
done
echo 'PASS: signed NVIDIA RPM archive and temporary build mount are absent'
