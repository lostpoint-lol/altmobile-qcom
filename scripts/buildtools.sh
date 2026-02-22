#!/bin/bash

set -euo pipefail

log() {
    echo "[*] $1"
}

# Install the necessary tools first
sudo apt update && sudo apt install 7zip kmod cpio binutils wget dpkg unzip build-essential bash coreutils git tar sed sudo make gcc rpm gcc-aarch64-linux-gnu bc flex bison libssl-dev libelf-dev libncurses-dev libudev-dev libpci-dev libiberty-dev autoconf fastboot

# On Ubuntu 24.04, the mkbootimg package is broken with the infamous error "no module named gki"
# We need to use the LineageOS prebuilt version

# Remove the package if it exists (ignore error if it doesn't)
log "Removing mkbootimg package (if installed)..."
sudo apt purge -y mkbootimg || echo "Package mkbootimg not found, skipping."

# Clone the LineageOS mkbootimg into $HOME if not already present
if [ ! -d "$HOME/mkbootimg" ]; then
    log "Cloning mkbootimg repository into \$HOME..."
    git clone https://github.com/LineageOS/android_system_tools_mkbootimg.git "$HOME/mkbootimg"
else
    log "Directory \$HOME/mkbootimg already exists, skipping..."
fi

# Symlink the scripts to /usr/bin if they don't already exist
declare -A symlinks=(
    ["$HOME/mkbootimg/mkbootimg/mkbootimg.py"]="/usr/bin/mkbootimg"
    ["$HOME/mkbootimg/repack_bootimg.py"]="/usr/bin/repack_bootimg"
    ["$HOME/mkbootimg/unpack_bootimg.py"]="/usr/bin/unpack_bootimg"
)

for src in "${!symlinks[@]}"; do
    dest="${symlinks[$src]}"
    if [ -L "$dest" ]; then
        current_target=$(readlink -f "$dest" || true)
        desired_target=$(readlink -f "$src" || true)
        if [ "$current_target" = "$desired_target" ]; then
            log "Symlink $dest already points to $src, skipping."
            continue
        fi
    elif [ -e "$dest" ]; then
        log "File $dest already exists and is not a symlink, skipping."
        continue
    fi

    log "Creating/updating symlink: $dest -> $src"
    sudo ln -sfn "$src" "$dest"
done
