# RPM Fusion graphics and multimedia

Atomic Hat builds from `quay.io/fedora/fedora-kinoite:44` on x86_64.
Custom graphics and multimedia packages use RPM Fusion's stable Free and
Nonfree repositories. The rest of the operating system comes from Fedora.

| Component | Image contents |
| --- | --- |
| NVIDIA | `akmod-nvidia`, explicitly compiled as the open kernel module, plus `xorg-x11-drv-nvidia` and its power-management package |
| CUDA driver support | `xorg-x11-drv-nvidia-cuda` and its driver libraries, including `libcuda` and `nvidia-smi` |
| Mesa | Fedora's Mesa stack, `mesa-va-drivers-freeworld`, and `mesa-vulkan-drivers-freeworld` |
| FFmpeg | Full `ffmpeg` and `ffmpeg-libs`, replacing conflicting Fedora Free packages |

## CUDA scope

This includes **driver support**, as selected for this image. It does not
install NVIDIA's CUDA toolkit, `nvcc`, `libcudart`, cuBLAS, or cuDNN. Supply
these through the application environment or a CUDA container as needed.
A program missing `libcudart.so.12` or `libcublas.so.12` still needs those
runtime libraries. The CUDA version shown by `nvidia-smi` describes driver
capability, not an installed toolkit. The NVIDIA Container Toolkit is also
a separate addition if GPU containers will be used.

## NVIDIA build

The RPM macro in `system_files/etc/rpm/macros.nvidia-open` selects the open
kernel implementation from RPM Fusion's `akmod-nvidia` source. This targets
Turing and newer GPUs, including the RTX 5070 Ti. Older GPUs requiring a
legacy proprietary kernel module are outside this image's scope. NVIDIA's
user-space graphics and CUDA driver libraries remain proprietary.

The build reads the kernel version from the image's RPM database, installs
matching development packages, compiles as the `akmods` user, installs the
resulting kmod RPM, and runs `depmod`. The package's automatic OSTree hook
is temporarily deferred because it attempts to compile as root; the
original hook is restored after installation. It checks all four modules against
the image kernel and user-space driver version. Missing or mismatched
modules fail the build. The CI runner needs no NVIDIA GPU.

Bootc kernel arguments blacklist Nouveau and Nova in the existing initramfs.
RPM Fusion's default of loading NVIDIA after the initramfs is preserved;
this customization does not regenerate Fedora's initramfs. These arguments
apply during bootc installation and updates. An initial transition using a
different deployment tool may need the same arguments added through that
tool.

## Mesa and FFmpeg

Fedora 44's base VA-API implementation is part of `mesa-dri-drivers`.
Freeworld VA-API installs alongside it. Freeworld Vulkan replaces
`mesa-vulkan-drivers`. Do not remove `mesa-dri-drivers` or follow old
instructions to install `mesa-vdpau-drivers-freeworld`.

Freeworld restores codec features where the hardware supports them. Mesa
also serves AMD/Intel devices in a mixed-GPU system. Flatpaks and containers
manage their own userspace runtimes. This image adds 64-bit packages;
32-bit gaming libraries can be added separately when adding Steam.

Mesa Freeworld must match Fedora's Mesa version. Temporary repository skew
should fail the build instead of publishing an inconsistent image. Retry
after the repositories catch up. The same applies if development packages
for the base image's kernel are unavailable.

## Secure Boot

Default-branch release builds use the `MODULE_SIGNING_KEY` GitHub Actions
repository secret and the public `atomic-hat.der` certificate in the repo
root. The secret contains the entire unencrypted PEM private key. These
are separate from the template's Cosign `SIGNING_SECRET`, which signs the
OCI image rather than kernel modules.

Podman mounts the signing files as build secrets. The build checks that
the key matches the certificate, signs through RPM's existing hook before
module compression, and cryptographically verifies every packaged NVIDIA
module against that certificate. A signing failure stops the build.
The private key is used only on temporary mounts; the image retains the
public certificate at `/etc/pki/akmods/certs/public_key.der`.

PRs and builds from non-default branches generate a temporary test key to
exercise the same signing checks without using the release key. They do
not publish an image. Do not enroll their temporary test certificates.

On the target machine, enroll the **release** certificate once:

```sh
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```

Choose a temporary enrollment password, reboot through Fedora's signed
shim, and select **Enroll MOK** in the MOK manager. Confirm the certificate
and enter that password. This is a password you choose, not `universalblue`.
You can also import the repo's `atomic-hat.der` before installing the image
from a Linux system with `mokutil` and a working shim/MOK enrollment flow.
After enrollment and reboot, confirm:

```sh
mokutil --sb-state
mokutil --test-key /etc/pki/akmods/certs/public_key.der
modinfo -F signer nvidia
```

The signer should be `Atomic Hat module signing`. Keep the same key for
future builds; replacing it requires enrolling the new certificate.

## Verification

Build using the pull-request workflow, or locally from the repo directory:

```sh
env MODULE_SIGNING_KEY_FILE="$HOME/.local/share/atomic-hat-signing/atomic-hat.key" just build
```

The public certificate defaults to `atomic-hat.der`; set
`MODULE_SIGNING_CERT_FILE` to use another matching certificate. Keep the
private key outside the repository.

Checks cover installed packages, NVIDIA module flavor/version/kernel and
signatures, FFmpeg x264/NVENC encoder availability, and `bootc container
lint`. CI does not test firmware enrollment or GPU hardware. The first
release build also checks that the GitHub secret matches `atomic-hat.der`.

After enrolling the release certificate where required and booting on the target:

```sh
bootc status
uname -r
modinfo -F license nvidia
modinfo -F version nvidia
modinfo -F signer nvidia
nvidia-smi
ffmpeg -hide_banner -encoders | grep -E 'libx264|nvenc'
```

Confirm KDE Wayland display output, suspend/resume, and an actual hardware
encode/decode workload before everyday use. An encoder listing alone does
not prove GPU operation.

## Upstream references

- [RPM Fusion NVIDIA](https://rpmfusion.org/Howto/NVIDIA)
- [RPM Fusion CUDA](https://rpmfusion.org/Howto/CUDA)
- [RPM Fusion multimedia](https://rpmfusion.org/Howto/Multimedia)
- [Fedora 44 NVIDIA packaging](https://github.com/rpmfusion/nvidia-kmod/blob/f44/nvidia-kmod.spec)
- [Fedora 44 Mesa packaging](https://github.com/rpmfusion/mesa-freeworld/blob/f44/mesa-freeworld.spec)
- [Bootc kernel arguments](https://github.com/bootc-dev/bootc/blob/main/docs/src/building/bootc-kernel-arguments.7.md)
