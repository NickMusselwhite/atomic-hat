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

**Trusted NVIDIA module signing is not configured by this change.** The
template's Cosign `SIGNING_SECRET` signs the OCI image, not kernel modules.
Fedora's signed kernel does not automatically trust a locally built module.

Before using this image with Secure Boot enabled, supply a persistent
module-signing key through build secret mounts, sign every NVIDIA module,
and enroll the public certificate on the target machine. Never commit a
private key, copy it into an image layer, or generate a new trust key for
each build. The build removes akmods' default private-key file before its
layer is committed. This branch does not change firmware security settings.

## Verification

Build using the pull-request workflow or `just build`. Pull-request builds
do not publish to GHCR. Checks cover installed packages, NVIDIA module
flavor/version/kernel, FFmpeg x264/NVENC encoder availability, and
`bootc container lint`. These checks do not exercise GPU hardware.

After addressing module signing where required and booting on the target:

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
