#!/bin/bash

# Enable strict mode
set -e

# Configuration file path
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

# Check arguments
DEST_DIR="$1"
if [ -z "$DEST_DIR" ]; then
	log_error "Usage: $0 <destination_directory>"
	exit 1
fi

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

# Check destination directory
if [ ! -d "$DEST_DIR" ]; then
	log_error "Destination directory does not exist: $DEST_DIR"
	exit 1
fi

# 1. Mount Logic (Copied from backup.sh to ensure access to snapshots)
log_info "Identifying device for source path: $SOURCE_PATH"
SOURCE_DEVICE_RAW=$(findmnt -n -o SOURCE --target "$SOURCE_PATH")

if [ -z "$SOURCE_DEVICE_RAW" ]; then
	log_error "Could not find device for $SOURCE_PATH"
	exit 1
fi

SOURCE_DEVICE=$(echo "$SOURCE_DEVICE_RAW" | sed 's/\[.*\]//')
log_info "Found source device: $SOURCE_DEVICE"

log_info "Checking mount point: $MOUNT_POINT"
MOUNT_NEEDED=false

if mountpoint -q "$MOUNT_POINT"; then
	log_info "$MOUNT_POINT is already mounted. Verifying..."
	MOUNTED_DEVICE_RAW=$(findmnt -n -o SOURCE --target "$MOUNT_POINT")
	MOUNTED_DEVICE=$(echo "$MOUNTED_DEVICE_RAW" | sed 's/\[.*\]//')

	if [ "$MOUNTED_DEVICE" != "$SOURCE_DEVICE" ]; then
		log_error "Mount point $MOUNT_POINT is mounted to $MOUNTED_DEVICE, expected $SOURCE_DEVICE"
		exit 1
	fi

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
	MOUNT_NEEDED=true
	log_info "Mounted $SOURCE_DEVICE (subvol=/) to $MOUNT_POINT"
fi

# Ensure cleanup on exit if we mounted it
cleanup() {
	if [ "$MOUNT_NEEDED" = true ]; then
		log_info "Unmounting $MOUNT_POINT..."
		umount "$MOUNT_POINT"
		log_info "Unmounted successfully."
	fi
}
trap cleanup EXIT

# 2. Find Snapshots
FULL_TARGET_DIR="$MOUNT_POINT/$TARGET_DIR"
if [ ! -d "$FULL_TARGET_DIR" ]; then
	log_error "Snapshot directory $FULL_TARGET_DIR does not exist."
	exit 1
fi

log_info "Scanning for snapshots in $FULL_TARGET_DIR..."

# Get latest local snapshot
LATEST_LOCAL=$(ls -1 "$FULL_TARGET_DIR" | sort | tail -n 1)

if [ -z "$LATEST_LOCAL" ]; then
	log_warn "No snapshots found in $FULL_TARGET_DIR. Nothing to transfer."
	exit 0
fi

log_info "Latest local snapshot: $LATEST_LOCAL"

# Find common parent
COMMON_PARENT=""
# List local snapshots in reverse order (newest first) to find the most recent common one
for snap in $(ls -1 "$FULL_TARGET_DIR" | sort -r); do
	if [ -d "$DEST_DIR/$snap" ]; then
		COMMON_PARENT="$snap"
		break
	fi
done

# 3. Execute Transfer
if [ -z "$COMMON_PARENT" ]; then
	log_info "No common parent found. Performing FULL transfer of $LATEST_LOCAL..."

	if btrfs send "$FULL_TARGET_DIR/$LATEST_LOCAL" | dd bs=1MiB status=progress | btrfs receive "$DEST_DIR"; then
		log_info "Full transfer of $LATEST_LOCAL completed successfully."
	else
		log_error "Transfer failed."
		exit 1
	fi
elif [ "$COMMON_PARENT" == "$LATEST_LOCAL" ]; then
	log_info "Destination is already up to date (Latest: $LATEST_LOCAL). No transfer needed."
else
	log_info "Found common parent: $COMMON_PARENT"
	log_info "Performing INCREMENTAL transfer from $COMMON_PARENT to $LATEST_LOCAL..."

	if btrfs send -p "$FULL_TARGET_DIR/$COMMON_PARENT" "$FULL_TARGET_DIR/$LATEST_LOCAL" | dd bs=1MiB status=progress | btrfs receive "$DEST_DIR"; then
		log_info "Incremental transfer completed successfully."
	else
		log_error "Transfer failed."
		exit 1
	fi
fi

log_info "Transfer process completed."
