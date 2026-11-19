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

# Use the signed RPM exported by the NVIDIA builder through an ephemeral
# build-stage mount instead of COPY. DNF can install it, but the original RPM
# archive never enters a runtime image layer (or the final OCI image).
# Its kernel-uname-r requirement must match this clean Kinoite base.
RUN --mount=type=bind,from=nvidia-builder,source=/usr/share/atomic-hat/build-artifacts/nvidia,target=/mnt/atomic-hat-nvidia-rpms,ro \
    --mount=type=cache,dst=/var/cache \
    dnf5 install -y \
      https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-45.noarch.rpm \
      https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-45.noarch.rpm && \
    dnf5 install -y --exclude='kernel*' --setopt=install_weak_deps=False \
      /mnt/atomic-hat-nvidia-rpms/kmod-nvidia-*.rpm \
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

# Clean the actual runtime filesystem after the /var/log cache mount is gone.
# Removing /var/log/dnf5.log inside runtime-apps.sh only affects its cache
# mount, not a log created in the earlier NVIDIA RPM installation layer.
# DNF's per-repository countme files are ephemeral and rebuilt as needed.
# /run/setrans is a runtime-only directory; fail rather than discard content
# if a package unexpectedly populated it.
RUN set -eu; \
    rm -f -- /var/log/dnf5.log; \
    rm -rf -- /var/lib/dnf/repos; \
    if [ -d /run/setrans ]; then rmdir /run/setrans; fi; \
    test ! -e /var/log/dnf5.log; \
    test ! -e /var/lib/dnf/repos; \
    test ! -e /run/setrans

RUN bootc container lint

# Experimental final image is the clean runtime, not the NVIDIA builder.
# Pull request builds validate this stage without publishing to GHCR.
FROM runtime-test AS final
