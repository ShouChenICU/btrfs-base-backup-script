#!/bin/bash

# Enable strict mode
set -e

# Configuration file path
# Assuming script is in scripts/ and config is in config/
CONFIG_FILE="$(dirname "$(readlink -f "$0")")/../config/btrfs-base-backup.conf"

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
LIGHT_GRAY='\033[0;37m'
DARK_RED='\033[0;91m'
NC='\033[0m' # No Color

log_info() {
	echo -e "${GREEN}[INFO]${NC} ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC} ${LIGHT_GRAY}$1${NC}"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC} ${WHITE}$1${NC}"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC} ${DARK_RED}$1${NC}" >&2
}

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
	log_info "Loading configuration from $CONFIG_FILE"
	source "$CONFIG_FILE"
else
	log_error "Configuration file not found at $CONFIG_FILE"
	exit 1
fi

# Check required variables
if [ -z "$SOURCE_PATH" ] || [ -z "$TARGET_DIR" ] || [ -z "$MOUNT_POINT" ]; then
	log_error "Missing required configuration variables (SOURCE_PATH, TARGET_DIR, MOUNT_POINT)"
	exit 1
fi

# 1. Get source device
log_info "Identifying device for source path: $SOURCE_PATH"
# findmnt -n -o SOURCE returns device path, possibly with subvol info like /dev/sda1[/home]
SOURCE_DEVICE_RAW=$(findmnt -n -o SOURCE --target "$SOURCE_PATH")

if [ -z "$SOURCE_DEVICE_RAW" ]; then
	log_error "Could not find device for $SOURCE_PATH"
	exit 1
fi

# Strip subvol info to get the block device (e.g., /dev/sda1)
SOURCE_DEVICE=$(echo "$SOURCE_DEVICE_RAW" | sed 's/\[.*\]//')
log_info "Found source device: $SOURCE_DEVICE (from $SOURCE_DEVICE_RAW)"

# 2. Check mount point
log_info "Checking mount point: $MOUNT_POINT"
if mountpoint -q "$MOUNT_POINT"; then
	log_info "$MOUNT_POINT is already mounted. Verifying..."

	MOUNTED_DEVICE_RAW=$(findmnt -n -o SOURCE --target "$MOUNT_POINT")
	MOUNTED_DEVICE=$(echo "$MOUNTED_DEVICE_RAW" | sed 's/\[.*\]//')

	# Check if it is the correct device
	if [ "$MOUNTED_DEVICE" != "$SOURCE_DEVICE" ]; then
		log_error "Mount point $MOUNT_POINT is mounted to $MOUNTED_DEVICE, expected $SOURCE_DEVICE"
		exit 1
	fi

	# Check if it is subvol=/ (root)
	FSROOT=$(findmnt -n -o FSROOT --target "$MOUNT_POINT")
	if [ "$FSROOT" != "/" ]; then
		log_error "Mount point $MOUNT_POINT is not mounted as btrfs root (subvol=/). Current fsroot: $FSROOT"
		exit 1
	fi

	log_info "$MOUNT_POINT is correctly mounted."
else
	log_info "$MOUNT_POINT is not mounted. Mounting..."
	mkdir -p "$MOUNT_POINT"

	mount -t btrfs -o subvol=/ "$SOURCE_DEVICE" "$MOUNT_POINT"
	log_info "Mounted $SOURCE_DEVICE (subvol=/) to $MOUNT_POINT"
fi

# 3. Perform Backup
SNAPSHOT_NAME=$(date -Is)
FULL_TARGET_DIR="$MOUNT_POINT/$TARGET_DIR"
SNAPSHOT_PATH="$FULL_TARGET_DIR/$SNAPSHOT_NAME"

log_info "Preparing to snapshot to $SNAPSHOT_PATH"

if [ ! -d "$FULL_TARGET_DIR" ]; then
	log_info "Creating target directory: $FULL_TARGET_DIR"
	mkdir -p "$FULL_TARGET_DIR"
fi

log_info "Creating read-only snapshot..."
# Snapshot the source path to the target path
if btrfs subvolume snapshot -r "$SOURCE_PATH" "$SNAPSHOT_PATH"; then
	log_info "Snapshot created successfully at $SNAPSHOT_PATH"
else
	log_error "Failed to create snapshot"
	# Attempt to unmount before exiting
	umount "$MOUNT_POINT"
	exit 1
fi

# 4. Cleanup
log_info "Unmounting $MOUNT_POINT..."
umount "$MOUNT_POINT"
log_info "Unmounted successfully."

log_info "Backup process completed."
