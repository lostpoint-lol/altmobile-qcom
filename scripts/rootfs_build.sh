#!/bin/bash
# Copyright (c) 2024, Danila Tikhonov <danila@jiaxyga.com>

set -euo pipefail

SCRIPTS_DIR="$(readlink -f "$(dirname $0)")"
source "${SCRIPTS_DIR}/vars.sh"
source "${SCRIPTS_DIR}/funcs.sh"

echo
echo "Building the rootfs image..."

# Download, unpack and remove the EFI partition
get_alt_image

# Prepare root directory
ROOTDIR="${CACHE_DIR}/rootdir"
mkdir -p "${ROOTDIR}"

cleanup() {
	if mountpoint -q "${ROOTDIR}"; then
		sudo umount "${ROOTDIR}"
	fi
}
trap cleanup EXIT

# Mount the image
sudo umount "${ROOTDIR}" > /dev/null 2>&1 || true
if ! sudo mount -o loop "${WORK_DIR}/${EXTRACTED_IMAGE}" "${ROOTDIR}"; then
	echo "Error: Failed to mount ${EXTRACTED_IMAGE} image."
	exit 1
fi

if ! mountpoint -q "${ROOTDIR}"; then
	echo "Error: ${ROOTDIR} is not mounted; aborting to avoid modifying host files."
	exit 1
fi

if [ ! -d "${ROOTDIR}/etc" ]; then
	echo "Error: Mounted image does not look like a Linux rootfs (${ROOTDIR}/etc is missing)."
	exit 1
fi

# Replace fstab
PARTLABEL="${PARTLABEL}" envsubst < "${SRC_DIR}/fstab" \
			| sudo tee "${ROOTDIR}/etc/fstab" > /dev/null \
			|| { echo "Error: Failed to replace /etc/fstab"; exit 1; }

# Install a custom ALSA Use Case Manager configuration
FOLDER_NAME="alsa-${VENDOR}-${CODENAME}-git"
git_clone "ALSAUCM" "${CACHE_DIR}/${FOLDER_NAME}"

sudo mkdir -p "${ROOTDIR}/usr/share/alsa"
sudo cp -r "${CACHE_DIR}/${FOLDER_NAME}"/{ucm,ucm2} "${ROOTDIR}/usr/share/alsa"

# Install packages
if ls "${PACKAGES_DIR}"/*.rpm 1> /dev/null 2>&1; then
	sudo rpm -Uvh --noscripts --replacepkgs --root "${ROOTDIR}"	\
	--ignorearch --nodeps -i "${PACKAGES_DIR}"/*.rpm ||		\
	(echo "Error installing packages" && exit 1)
else
	echo "Error: No RPM packages found in ${PACKAGES_DIR}."
	exit 1
fi

echo "Unmounting the rootfs..."
# Unmount the image
sudo umount "${ROOTDIR}"
trap - EXIT
echo "Rootfs build done: $(ls -d "${WORK_DIR}/${EXTRACTED_IMAGE}")"
