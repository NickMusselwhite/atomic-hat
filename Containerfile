# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Base Image
FROM quay.io/fedora/fedora-kinoite:45 AS nvidia-builder
## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:testing
# FROM ghcr.io/ublue-os/aurora:stable
# FROM ghcr.io/ublue-os/bluefin-nvidia-open:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:44
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### Image-managed /opt
# Allow third-party RPMs such as 1Password to install into /opt.
RUN if [ -L /opt ]; then rm /opt; fi && mkdir -p /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=secret,id=module_signing_key \
    --mount=type=secret,id=module_signing_cert \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint

# Experimental installation test: do not publish this stage.
# Use a fresh Kinoite base so NVIDIA cannot rely on the builder's toolchain.
FROM quay.io/fedora/fedora-kinoite:45 AS runtime-test

# Copy the RPM signed and exported by the existing NVIDIA builder stage.
COPY --from=nvidia-builder /usr/share/atomic-hat/build-artifacts/nvidia/ /usr/share/atomic-hat/build-artifacts/nvidia/

# Install the same RPM Fusion repos and NVIDIA userspace packages as build.sh.
# Install the local kmod RPM in the same DNF transaction. Its kernel-uname-r
# requirement must be satisfied by the kernel in this clean Kinoite image.
RUN --mount=type=cache,dst=/var/cache \
    dnf5 install -y \
      https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-45.noarch.rpm \
      https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-45.noarch.rpm && \
    dnf5 install -y --exclude='kernel*' --setopt=install_weak_deps=False \
      /usr/share/atomic-hat/build-artifacts/nvidia/kmod-nvidia-*.rpm \
      xorg-x11-drv-nvidia \
      xorg-x11-drv-nvidia-cuda \
      xorg-x11-drv-nvidia-power

# Confirm that NVIDIA installed and the compilation toolchain did not.
# Check absent packages individually: rpm -q with multiple arguments returns
# failure even if only ONE package is absent, which would give a false pass.
RUN set -eu; \
    test -n "$(rpm -qa 'kmod-nvidia-*')"; \
    rpm -q xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-power; \
    for pkg in akmods akmod-nvidia kernel-devel kernel-devel-matched gcc make rpm-build dwarves xorg-x11-drv-nvidia-kmodsrc; do \
      if rpm -q "$pkg" >/dev/null 2>&1; then \
        echo "Unexpected build-only package in runtime-test: $pkg" >&2; \
        exit 1; \
      fi; \
    done; \
    bootc container lint

# Install the full Atomic Hat desktop application set into the clean runtime.
# Use the same installer as the existing builder; do not duplicate its list.
# Keep this separate from the NVIDIA-only check so failures are easy to locate.
# Also make /opt image-managed, as the working image does for 1Password.
RUN if [ -L /opt ]; then rm /opt; fi && mkdir -p /opt
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/runtime-apps.sh
RUN bootc container lint

# Experimental handoff: keep the runtime identical to the validated builder.
# Later we will replace this inheritance with a clean Fedora runtime stage.
FROM nvidia-builder AS final
