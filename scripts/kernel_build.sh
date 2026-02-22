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

read -r -a DEFCONFIG_TOKENS <<< "${DEFCONFIG}"
BASE_DEFCONFIG="${DEFCONFIG_TOKENS[0]:-}"

if [ -z "${BASE_DEFCONFIG}" ]; then
	echo "Error: DEFCONFIG is empty in deviceinfo."
	exit 1
fi

find_defconfig() {
	local CANDIDATE="$1"
	[ -f "${REPO_DIR}/arch/${ARCH}/configs/${CANDIDATE}" ]
}

# Clone the kernel source repository
mkdir -p "${CACHE_DIR}"
git_clone "KERNEL" "${CACHE_DIR}/${FOLDER_NAME}"

# Build the kernel using the specified defconfig
cd "${REPO_DIR}"
if ! find_defconfig "${BASE_DEFCONFIG}"; then
	SOC_DEFCONFIG="${SOC}_defconfig"
	if find_defconfig "${SOC_DEFCONFIG}"; then
		echo "Warning: ${BASE_DEFCONFIG} not found; using ${SOC_DEFCONFIG}."
		BASE_DEFCONFIG="${SOC_DEFCONFIG}"
	else
		echo "Warning: can't find '${BASE_DEFCONFIG}' or '${SOC_DEFCONFIG}' in arch/${ARCH}/configs/."
		echo "Warning: falling back to generic defconfig; adjust DEFCONFIG in deviceinfo for ${DEVICE_NAME}."
		BASE_DEFCONFIG="defconfig"
	fi
fi

make ${MAKEPROPS} "${BASE_DEFCONFIG}"

for CONFIG_FRAGMENT in "${DEFCONFIG_TOKENS[@]:1}"; do
	if [ -f "${REPO_DIR}/${CONFIG_FRAGMENT}" ]; then
		echo "Applying config fragment: ${CONFIG_FRAGMENT}"
		"${REPO_DIR}/scripts/kconfig/merge_config.sh" -m -O "${KERNEL_OUTPUT}" \
			"${KERNEL_OUTPUT}/.config" "${REPO_DIR}/${CONFIG_FRAGMENT}"
		make ${MAKEPROPS} olddefconfig
	else
		echo "Warning: config fragment '${CONFIG_FRAGMENT}' not found in kernel repo, skipping."
	fi
done

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
