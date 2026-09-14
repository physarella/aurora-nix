#!/bin/bash
#
# Unpacks ublue-os/akmods for kernel $1 into /tmp/akmods: prebuilt kmods under
# rpms/, and that kernel's own packages -- kernel-devel included -- under
# kernel-rpms/. Used by build.sh and build-facetimehd.sh.
#
# A kmod is compiled for exactly one kernel (kmod-wl Requires kernel-uname-r =
# that version), so it has to come from the akmods build for the kernel the
# base already ships. Aurora itself builds from
# ghcr.io/ublue-os/akmods:coreos-stable-<fedora>-<kernel>, so that tag exists
# for every kernel aurora:stable can have.
#
# Never swap the kernel to fit a kmod instead. That was tried: the floating
# akmods:main-44 tag tracks Fedora's newest kernel, not the base's, so dnf
# quietly pulled a different kernel-core from the Fedora repos to satisfy
# kmod-wl. It came without kernel-modules (so not even the cfg80211 that wl
# needs), and without an initramfs, because rpm-ostree's kernel-install hook
# fails inside the build while the dnf transaction still reports success. The
# image panicked on boot.

set -ouex pipefail

kernel_version=$1

skopeo copy --retry-times 3 \
  "docker://ghcr.io/ublue-os/akmods:coreos-stable-$(rpm -E %fedora)-${kernel_version}" \
  dir:/tmp/akmods
for layer in $(jq -r '.layers[].digest | ltrimstr("sha256:")' /tmp/akmods/manifest.json); do
  tar -xf "/tmp/akmods/${layer}" -C /tmp/akmods
done
