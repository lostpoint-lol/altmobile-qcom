#!/bin/bash
# Copyright (c) 2024, Danila Tikhonov <danila@jiaxyga.com>
# Copyright (c) 2024, Victor Paul <vipollmail@gmail.com>

SCRIPTS_DIR="$(readlink -f "$(dirname $0)")"
source "${SCRIPTS_DIR}/vars.sh"

# Remove EFI partition
remove_efi_part() {
	echo "Trying to remove EFI partition from the image..."

	local IMAGE_PATH="$1"

	echo "Root is needed to create loop devices"
	if ! sudo -n true 2>/dev/null; then
		echo "Requesting sudo access..."
		sudo -v || {
			echo "Error: sudo authentication is required to create loop devices."
			return 1
		}
	fi

	# Create loop devices and capture output
	local kpartx_output
	if ! kpartx_output=$(sudo kpartx -asv "${IMAGE_PATH}"); then
		echo "Error: Failed to create loop devices with kpartx."
		return 1
	fi

	# Parse the loop device names
	local loop_devices=()
	while IFS= read -r line; do
		if [[ $line =~ add\ map\ ([^[:space:]]+) ]]; then
			loop_devices+=("/dev/mapper/${BASH_REMATCH[1]}")
		fi
	done <<< "${kpartx_output}"

	if [ "${#loop_devices[@]}" -lt 2 ]; then
		echo "EFI partition has already been deleted or not found."
		sudo kpartx -dv "${IMAGE_PATH}"
		return 0
	fi

	local ROOTFS_PARTITION_LOOP="${loop_devices[$((${#loop_devices[@]} - 1))]}"
	echo "Using rootfs partition: ${ROOTFS_PARTITION_LOOP}"

	# Temporary file for the rootfs image
	local TEMP_IMAGE_PATH="${IMAGE_PATH%.img}-rootfs.img"

	# Copy the root partition to this temporary file
	if [ -b "${ROOTFS_PARTITION_LOOP}" ]; then
		sudo dd if="${ROOTFS_PARTITION_LOOP}" \
				of="${TEMP_IMAGE_PATH}" bs=1M status=progress
		sudo kpartx -dv "${IMAGE_PATH}"
	else
		echo "Error: Could not remove EFI partition. Device ${ROOTFS_PARTITION_LOOP} not found."
		sudo kpartx -dv "${IMAGE_PATH}"
		return 1
	fi

	# Replace the original image with the rootfs image
	mv "${TEMP_IMAGE_PATH}" "${IMAGE_PATH}"
	echo "EFI partition removed. Image saved as '${IMAGE_PATH}'"
}

# Get ALT image function
get_alt_image() {
	local LATEST_IMAGE=$(curl -s "${ALT_URL}" | grep -oP	\
	'alt-mobile-phosh-def-(latest|\d{8})-aarch64\.img\.xz'	\
	| sort -r | head -n 1)
	EXTRACTED_IMAGE="${LATEST_IMAGE%.xz}"

	# Check if the extracted image already exists
	if [ -f "${WORK_DIR}/${EXTRACTED_IMAGE}" ]; then
		echo "Extracted file '${EXTRACTED_IMAGE}' already exists."
		echo "Remove it manually if you want to overwrite."
	else
		# Check if compressed image exists
		if [ -f "${WORK_DIR}/${LATEST_IMAGE}" ]; then
			echo "File '${LATEST_IMAGE}' is already downloaded."
		else
			# Download the image if it does not exist
			echo "Downloading latest image: ${ALT_URL}${LATEST_IMAGE}"
			curl -f -o "${WORK_DIR}/${LATEST_IMAGE}"	\
				"${ALT_URL}${LATEST_IMAGE}" ||		\
				{ echo "Download failed"; exit 1; }
		fi
		# Extract the image
		extract_image "${WORK_DIR}/${LATEST_IMAGE}"
	fi

	# Try to remove the EFI partition
	remove_efi_part "${WORK_DIR}/${EXTRACTED_IMAGE}"
}

extract_image() {
	echo "Starting extraction: '$1'"
	unxz "$1" || { echo "Extraction failed"; exit 1; }
	echo "Extraction completed: ${LATEST_IMAGE%.xz}"
}

# Make boot.img func
make_boot_img() {
	echo
	echo "Building boot.img for aboot..."
	local IMAGE_PATH DTB_PATH
	IMAGE_PATH="$1/arch/arm64/boot/Image.gz"
	DTB_PATH="$1/arch/arm64/boot/dts/qcom/${SOC}-${VENDOR}-${CODENAME}.dtb"
	OUTPUT="${WORK_DIR}/boot.img"

	mkbootimg \
		--kernel "${IMAGE_PATH}"	\
		--dtb "${DTB_PATH}"		\
		--cmdline "${CMDLINE}"		\
		--base 0x0			\
		--kernel_offset 0x8000		\
		--ramdisk_offset 0x1000000	\
		--tags_offset 0x100		\
		--pagesize 4096			\
		--header_version 2		\
		-o "${OUTPUT}"	\
		|| echo "Failed to make boot.img"

	echo "bootimg for android bootloader build done: ${WORK_DIR}/boot.img"
}

# Git clone func
git_clone() {
	local REPO_URL BRANCH
	REPO_URL=$(echo "${REPOS[$1]}" | cut -d' ' -f1)
	BRANCH=$(echo "${REPOS[$1]}" | cut -d' ' -f2)
	REPO_DIR="$2"

	# Check if directory exists
	if [ -d "$REPO_DIR" ]; then
		echo "Directory '${REPO_DIR}' already exists."
		echo "Remove it manually to re-clone."
	else
		git clone -b "${BRANCH}" "${REPO_URL}" "${REPO_DIR}" \
			--depth 1 || { echo "Failed to clone $1"; exit 1; }
	fi
}
