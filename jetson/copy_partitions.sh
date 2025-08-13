#!/bin/bash

# Default source and destination devices
SOURCE="/dev/mmcblk0"
DESTINATION="/dev/nvme0n1"

# Function to show help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Copy contents of partitions from source disk to destination disk."
    echo
    echo "Options:"
    echo "  -s, --source      Source disk (default: /dev/mmcblk0)"
    echo "  -d, --destination Destination disk (default: /dev/nvme0n1)"
    echo "  -h, --help        Show this help message and exit"
    echo
    exit 0
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -s|--source)
            SOURCE="$2"
            shift 2
            ;;
        -d|--destination)
            DESTINATION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Confirm the operation with the user
echo "Source disk: $SOURCE"
echo "Destination disk: $DESTINATION"
read -p "Are you sure you want to copy contents from $SOURCE to $DESTINATION? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Operation cancelled."
    exit 1
fi

# Ensure source and destination exist
if [[ ! -b "$SOURCE" || ! -b "$DESTINATION" ]]; then
    echo "Error: Source or destination disk does not exist."
    exit 1
fi

# Step 1: Enumerate partitions
echo "Enumerating partitions..."
SOURCE_PARTS=$(lsblk -ln -o NAME,MOUNTPOINT -p "$SOURCE" | grep -E "${SOURCE}p?[0-9]+" | awk '{print $1}')
DEST_PARTS=$(lsblk -ln -o NAME -p "$DESTINATION" | grep -E "${DESTINATION}p?[0-9]+$")

if [[ -z "$SOURCE_PARTS" || -z "$DEST_PARTS" ]]; then
    echo "Error: Failed to enumerate partitions on $SOURCE or $DESTINATION."
    exit 1
fi

# Step 2: Copy contents of each partition
for SOURCE_PART in $SOURCE_PARTS; do
    PART_NUM=$(echo "$SOURCE_PART" | grep -oE '[0-9]+$')

    # Match the corresponding destination partition
    if [[ "$SOURCE" == *"mmcblk"* || "$SOURCE" == *"nvme"* ]]; then
        DEST_PART="${DESTINATION}p${PART_NUM}"
    else
        DEST_PART="${DESTINATION}${PART_NUM}"
    fi

    # Check if destination partition exists
    if [[ ! -b "$DEST_PART" ]]; then
        echo "Warning: Destination partition $DEST_PART does not exist. Skipping..."
        continue
    fi

    # Identify the file system on the source and destination partitions
    SRC_FSTYPE=$(blkid -o value -s TYPE "$SOURCE_PART")
    DEST_FSTYPE=$(blkid -o value -s TYPE "$DEST_PART" || echo "")

    echo "Checking filesystem compatibility from $SOURCE_PART ($SRC_FSTYPE) to $DEST_PART ($DEST_FSTYPE)..."

    # Handle partitions without a filesystem (raw partitions)
    if [[ -z "$SRC_FSTYPE" ]]; then
        echo "Source partition $SOURCE_PART has no filesystem. Performing raw copy using dd..."
        dd if="$SOURCE_PART" of="$DEST_PART" bs=4M status=progress conv=fsync || {
            echo "Error: Failed to copy raw data from $SOURCE_PART to $DEST_PART."
            continue
        }
        sync
        echo "Raw copy from $SOURCE_PART to $DEST_PART completed."
        continue
    fi

    if [[ -z "$DEST_FSTYPE" ]]; then
        echo "Warning: Destination partition $DEST_PART has no filesystem. Skipping copy for safety."
        continue
    fi

    SRC_MOUNTPOINT=$(lsblk -ln -o MOUNTPOINT "$SOURCE_PART")
    echo "Copying from $SOURCE_PART to $DEST_PART (type: ${SRC_FSTYPE:-Unknown}, mount: ${SRC_MOUNTPOINT:-<not mounted>})..."

    # If the source is mounted, use its existing mount point
    if [[ -n "$SRC_MOUNTPOINT" ]]; then
        echo "Source partition $SOURCE_PART is already mounted at $SRC_MOUNTPOINT."
        SRC_MOUNT="$SRC_MOUNTPOINT"
    else
        # Mount the source partition read-only
        SRC_MOUNT="/mnt/source_$PART_NUM"
        mkdir -p "$SRC_MOUNT"
        mount -o ro "$SOURCE_PART" "$SRC_MOUNT" || {
            echo "Error: Failed to mount $SOURCE_PART. Skipping..."
            continue
        }
    fi

    # Mount the destination partition
    DEST_MOUNT="/mnt/destination_$PART_NUM"
    mkdir -p "$DEST_MOUNT"
    mount "$DEST_PART" "$DEST_MOUNT" || {
        echo "Error: Failed to mount $DEST_PART. Skipping..."
        umount "$SRC_MOUNT" &>/dev/null
        continue
    }

    # Check if the partition is rootfs (ext4) and copy only specific directories
    if [[ "$SRC_FSTYPE" == "ext4" && "$SRC_MOUNT" == "/" ]]; then
        echo "Detected root filesystem. Copying only system directories."
        rsync -aAXv --progress \
            --exclude="/dev/" \
            --exclude="/proc/" \
            --exclude="/sys/" \
            --exclude="/run/" \
            --exclude="/tmp/" \
            --exclude="/mnt/" \
            --exclude="/media/" \
            --exclude="/var/tmp/" \
            "$SRC_MOUNT/" "$DEST_MOUNT/" || {
            echo "Error: Failed to sync root filesystem directories from $SOURCE_PART to $DEST_PART."
        }
        sync
    elif [[ "$SRC_MOUNT" == "/boot" ]]; then
        echo "Detected boot partition. Copying all boot files."
        rsync -aAXv --progress "$SRC_MOUNT/" "$DEST_MOUNT/" || {
            echo "Error: Failed to sync boot partition from $SOURCE_PART to $DEST_PART."
        }
        sync
    else
        # General rsync for non-root partitions
        rsync -aAXv --progress "$SRC_MOUNT/" "$DEST_MOUNT/" || {
            echo "Error: Failed to sync $SOURCE_PART to $DEST_PART."
        }
        sync
    fi

    # Unmount destination and source (only if the source was mounted by the script)
    umount "$DEST_MOUNT"
    rmdir "$DEST_MOUNT"
    if [[ -z "$SRC_MOUNTPOINT" ]]; then
        umount "$SRC_MOUNT"
        rmdir "$SRC_MOUNT"
    fi

done

echo "Flushing disk caches..."
sync
blockdev --flushbufs "$DESTINATION"
udevadm settle


echo "Partition content copy complete."
