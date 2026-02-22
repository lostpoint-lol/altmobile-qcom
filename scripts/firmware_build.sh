#!/bin/bash
# Copyright (c) 2024, Danila Tikhonov <danila@jiaxyga.com>
# Copyright (c) 2024, Victor Paul <vipollmail@gmail.com>

set -euo pipefail

SCRIPTS_DIR="$(readlink -f "$(dirname $0)")"
source "${SCRIPTS_DIR}/vars.sh"
source "${SCRIPTS_DIR}/funcs.sh"

echo
echo "Building the firmware package..."

PKG_NAME="firmware-${VENDOR}-${CODENAME}"
PKG_VERSION="1.0"
FIRMWARE_DIR="${CACHE_DIR}/${PKG_NAME}"


# Clone the firmware repository
mkdir -p "${CACHE_DIR}"
git_clone "FIRMWARE" "${FIRMWARE_DIR}"

# Clean the build directory
rm -rf "${FIRMWARE_PKG_DIR}"
mkdir -p "${FIRMWARE_PKG_DIR}/"{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# Create the spec file
cat << EOF > "${FIRMWARE_PKG_DIR}/SPECS/${PKG_NAME}.spec"
Name: ${PKG_NAME}
Version: ${PKG_VERSION}
Release: alt1
Summary: Firmware for ${DEVICE_NAME}
License: Distributable
Source: %{name}-%{version}.tar.gz

%description
%summary

%install
mkdir -p %{buildroot}/lib/firmware
tar xf %SOURCE0 -C %{buildroot}

%files
/

%changelog
* $(LANG=C date +"%a %b %d %Y") ${MAINTAINER} - ${PKG_VERSION}-alt1
- Initial package
EOF

# Check if the files exist and copy them
if [ -d "${FIRMWARE_DIR}/lib" ]; then
	cp -r "${FIRMWARE_DIR}/"* "${FIRMWARE_PKG_DIR}/SOURCES/"
else
	echo "Firmware not found in ${FIRMWARE_DIR}"
	exit 1
fi

cd "${FIRMWARE_PKG_DIR}/SOURCES"
tar -czf "${PKG_NAME}-${PKG_VERSION}.tar.gz" *

cd "${FIRMWARE_PKG_DIR}"

rpmbuild --target "${ARCH}" --define "_topdir ${FIRMWARE_PKG_DIR}" \
			-bb "${FIRMWARE_PKG_DIR}/SPECS/${PKG_NAME}.spec"

if [ -e "${PACKAGES_DIR}" ] && [ ! -d "${PACKAGES_DIR}" ]; then
	echo "Error: ${PACKAGES_DIR} exists and is not a directory."
	exit 1
fi
mkdir -p "${PACKAGES_DIR}"

rm -f ${PACKAGES_DIR}/firmware-*.arm64.rpm
cp "${FIRMWARE_PKG_DIR}/RPMS/"*/*.rpm "${PACKAGES_DIR}"
echo "Firmware package build done: ${PACKAGES_DIR}/firmware-*.rpm"
