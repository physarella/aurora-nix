#!/bin/bash
#
# Compiles the FaceTime HD camera driver for the base image's own kernel. Runs
# in the Containerfile's throwaway facetimehd stage, so kernel-devel never
# reaches the image; build.sh installs only what lands in /out.

set -ouex pipefail

# Pinned by commit and checksum, so updating is deliberate: bump a pair and let
# CI build it. If a new Aurora kernel breaks the driver, this stage fails and
# the last good image stays published until the pin is bumped.
FACETIMEHD_COMMIT=c5c7fac4e6da061ededd4c46545930ff7cdc0529
FACETIMEHD_SHA256=7d7fc4d343fd34123687bb7dc32f511afe19a4d44aed836a4cc5bc4e794fb6ce
FIRMWARE_TOOLS_COMMIT=60ee21228d9ca00a7bd84fdaefaff00a81f1db91
FIRMWARE_TOOLS_SHA256=8a991a516056c0733d81e3dd0979cac0a71b565209390d266df84b47679d38e4

# fetch <patjak repo> <commit> <sha256> <dest>
fetch() {
  curl -fsSL -o "/tmp/$1.tar.gz" "https://github.com/patjak/$1/archive/$2.tar.gz"
  echo "$3  /tmp/$1.tar.gz" | sha256sum -c -
  mkdir -p "$4"
  tar -xzf "/tmp/$1.tar.gz" -C "$4" --strip-components=1
}

kernel_version=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)
/ctx/fetch-akmods.sh "$kernel_version"
dnf5 install -y "/tmp/akmods/kernel-rpms/kernel-devel-${kernel_version}.rpm"

fetch facetimehd "$FACETIMEHD_COMMIT" "$FACETIMEHD_SHA256" /tmp/facetimehd
make -C "/usr/src/kernels/${kernel_version}" M=/tmp/facetimehd modules
install -Dm644 /tmp/facetimehd/facetimehd.ko /out/facetimehd.ko

# Upstream's GPL download-and-extract tooling, which facetimehd.service runs on
# the machine. The firmware itself never passes through this build.
fetch facetimehd-firmware "$FIRMWARE_TOOLS_COMMIT" "$FIRMWARE_TOOLS_SHA256" /tmp/facetimehd-firmware
install -Dm644 -t /out/firmware-tools /tmp/facetimehd-firmware/{Makefile,LICENSE}
install -Dm755 -t /out/firmware-tools /tmp/facetimehd-firmware/extract-firmware.sh
