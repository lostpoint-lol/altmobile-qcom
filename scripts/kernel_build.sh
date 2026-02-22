#!/bin/bash
# Copyright (c) 2024, Danila Tikhonov <danila@jiaxyga.com>
# Copyright (c) 2024, Victor Paul <vipollmail@gmail.com>

set -euo pipefail

SCRIPTS_DIR="$(readlink -f "$(dirname $0)")"
source "${SCRIPTS_DIR}/vars.sh"
source "${SCRIPTS_DIR}/funcs.sh"

echo
echo "Building the kernel packages..."

FOLDER_NAME="linux-${VENDOR}-${CODENAME}-git"
KERNEL_OUTPUT="${BUILD_DIR}/${FOLDER_NAME}-output"
MAKEPROPS="-j$(nproc) O=${KERNEL_OUTPUT} \
			ARCH=${ARCH} CROSS_COMPILE=aarch64-linux-gnu-"

# Clone the kernel source repository
mkdir -p "${CACHE_DIR}"
git_clone "KERNEL" "${CACHE_DIR}/${FOLDER_NAME}"

# Build the kernel using the specified defconfig
cd "${REPO_DIR}"
make ${MAKEPROPS} ${DEFCONFIG}
make ${MAKEPROPS}

# Make boot.img
make_boot_img "${KERNEL_OUTPUT}"

# Build and copy the RPM packages
rm -rf "${KERNEL_OUTPUT}/rpmbuild/RPMS/"
make ${MAKEPROPS} rpm-pkg

if [ -e "${PACKAGES_DIR}" ] && [ ! -d "${PACKAGES_DIR}" ]; then
	echo "Error: ${PACKAGES_DIR} exists and is not a directory."
	exit 1
fi
mkdir -p "${PACKAGES_DIR}"
echo "Removing old kernel packages from: ${PACKAGES_DIR}"
rm -f ${PACKAGES_DIR}/kernel-*.rpm
cp "${KERNEL_OUTPUT}/rpmbuild/RPMS/"*/*.rpm "${PACKAGES_DIR}"
echo "Kernel packages build done: ${PACKAGES_DIR}/kernel-*.rpm"
