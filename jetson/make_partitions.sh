#!/bin/bash

# Default source and destination devices
SOURCE="/dev/mmcblk0"
DESTINATION="/dev/nvme0n1"

# Function to show help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Clone partition structure from one disk to another and replicate file systems."
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

# Confirm the operation with the user
echo "Source disk: $SOURCE"
echo "Destination disk: $DESTINATION"
read -p "Are you sure you want to clone the partition structure and file systems? This will overwrite $DESTINATION. (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Operation cancelled."
    exit 1
fi

# The GPT tables exist on the start and end of the drive. Make sure to erase all of the tables
echo "Clearing all partition and filesystem metadata from $DESTINATION..."
sgdisk --zap-all "$DESTINATION" || { echo "Failed to zap $DESTINATION."; exit 1; }

# Backup the GPT partition table from the source disk
echo "Backing up partition table from $SOURCE..."
sgdisk --backup=table.bak "$SOURCE" || { echo "Failed to backup partition table from $SOURCE."; exit 1; }

# Restore the partition table to the destination disk
echo "Restoring partition table to $DESTINATION..."
sgdisk --load-backup=table.bak "$DESTINATION" || { echo "Failed to restore partition table to $DESTINATION."; exit 1; }

# Modify PARTUUIDs on destination disk
echo "Randomizing GUIDs for $DESTINATION..."
sgdisk --randomize-guids "$DESTINATION" || { echo "Failed to randomize GUIDs on $DESTINATION."; exit 1; }

echo "Flushing disk writes..."
sync

# Inform the OS about the partition table changes
echo "Reloading partition table on $DESTINATION..."
partprobe "$DESTINATION" || {
    echo "partprobe failed, forcing partition table reread..."
    blockdev --rereadpt "$DESTINATION" || { echo "Failed to reread partition table."; exit 1; }
}

# Ensure system is aware of changes
udevadm settle

# Replicate file systems from source to destination
echo "Replicating file systems..."
for PART in $(lsblk -ln -o NAME -p "$DESTINATION" | grep -E "${DESTINATION}p?[0-9]+$"); do
    # Get the corresponding source partition
    PART_NUM=$(echo "$PART" | grep -oE '[0-9]+$')

    # Handle partition naming difference for source device
    if [[ "$SOURCE" == *"mmcblk"* || "$SOURCE" == *"nvme"* ]]; then
        SOURCE_PART="${SOURCE}p${PART_NUM}"
    else
        SOURCE_PART="${SOURCE}${PART_NUM}"
    fi

    # Echo the destination partition being processed
    echo "Processing destination partition: $PART"
    echo "Corresponding source partition: $SOURCE_PART"

    # Check if the source partition has a file system
    SRC_FSTYPE=$(blkid -o value -s TYPE "$SOURCE_PART")
    echo "Source partition: $SOURCE_PART, Detected filesystem: ${SRC_FSTYPE:-None}"

    if [[ -n "$SRC_FSTYPE" ]]; then
        case "$SRC_FSTYPE" in
            ext[234])
                echo "Creating ext4 filesystem on $PART..."
                mkfs.ext4 -F "$PART" && echo "ext4 filesystem created successfully on $PART."
                ;;
            vfat|fat32)
                echo "Creating FAT32 filesystem on $PART..."
                mkfs.vfat -F 32 "$PART" && echo "FAT32 filesystem created successfully on $PART."
                ;;
            swap)
                echo "Creating swap on $PART..."
                mkswap "$PART" && echo "Swap filesystem created successfully on $PART."
                ;;
            *)
                echo "Unsupported filesystem $SRC_FSTYPE on $SOURCE_PART. Skipping $PART..."
                ;;
        esac
    else
        echo "Source partition $SOURCE_PART has no filesystem. Leaving $PART empty."
    fi
done

# Ensure all filesystem changes are committed
echo "Flushing all writes before UUID adjustments..."
sync


# Adjust filesystem UUIDs
echo "Adjusting filesystem UUIDs..."
for PART in $(lsblk -ln -o NAME -p "$DESTINATION" | grep -E "${DESTINATION}p?[0-9]+$"); do
    FSTYPE=$(blkid -o value -s TYPE "$PART")
    PART_NUM=$(echo "$PART" | grep -oE '[0-9]+$')

    # Determine corresponding source partition
    if [[ "$SOURCE" == *"mmcblk"* || "$SOURCE" == *"nvme"* ]]; then
        SOURCE_PART="${SOURCE}p${PART_NUM}"
    else
        SOURCE_PART="${SOURCE}${PART_NUM}"
    fi

    echo "Processing destination partition: $PART (type: $FSTYPE)"
    echo "Corresponding source partition: $SOURCE_PART"

    if [[ -n "$FSTYPE" ]]; then
        case "$FSTYPE" in
            ext[234])
                echo "Checking filesystem on $PART..."
                e2fsck -f "$PART" && tune2fs -U random "$PART" && echo "Updated UUID for $PART."
                sync
                ;;
            swap)
                mkswap -U "$(uuidgen)" "$PART" && echo "Updated UUID for $PART."
                sync
                ;;
            vfat|fat32)
                # Fetch the source FAT32 label correctly now
                SRC_LABEL=$(blkid -o value -s LABEL "$SOURCE_PART")
                echo "Source FAT32 label for $SOURCE_PART: ${SRC_LABEL:-<none>}"

                if [[ -n "$SRC_LABEL" ]]; then
                    echo "Setting FAT32 label: $SRC_LABEL on $PART..."
                    if ! fatlabel "$PART" "$SRC_LABEL"; then
                        echo "Error: FAT32 label '$SRC_LABEL' failed to set on $PART."
                    else
                        echo "Updated label and UUID for $PART with label: $SRC_LABEL."
                    fi
                else
                    echo "Source FAT32 partition $SOURCE_PART has no label. Skipping label assignment."
                fi
                # Get the source partition label (PARTLABEL)
                SRC_PARTLABEL=$(blkid -o value -s PARTLABEL "$SOURCE_PART")
                echo "Source PARTLABEL for $SOURCE_PART: ${SRC_PARTLABEL:-<none>}"

                if [[ -n "$SRC_PARTLABEL" ]]; then
                    echo "Setting PARTLABEL: $SRC_PARTLABEL on $PART..."
                    sgdisk --change-name="${PART_NUM}:${SRC_PARTLABEL}" "$DESTINATION" && echo "Updated PARTLABEL for $PART to $SRC_PARTLABEL."
                else
                    echo "Source partition $SOURCE_PART has no PARTLABEL. Skipping PARTLABEL update."
                fi

                # Ensure partition table changes are recognized
                sync
                partprobe "$DESTINATION"
                udevadm settle
                ;;
            *)
                echo "Filesystem type $FSTYPE on $PART not supported for UUID adjustment."
                ;;
        esac
    else
        echo "Skipping $PART: No filesystem detected."
    fi
done

# Ensure UUID changes are properly recognized
echo "Forcing partition table reread after UUID updates..."
blockdev --rereadpt "$DESTINATION" || echo "Warning: Could not reread partition table."
udevadm settle
sync  # Final sync to make sure everything is written

# Clean up
rm -f table.bak

echo "Partition cloning, file system replication, and UUID adjustment complete."
