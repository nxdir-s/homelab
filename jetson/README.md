# Migrate Jetson to SSD

## Usage

### Step 1: CopyMake Partition Structure

Run `make_partitions.sh` to copy the partition structure:

```bash
sudo bash make_partitions.sh
```

### Step 2: Copy Partition Data

Run `copy_partitions.sh` to clone the data:

```bash
sudo  bash copy_partitions.sh
```

### Step 3: Configure SSD Boot

Run `configure_ssd_boot.sh` to modify the system configuration:

```bash
sudo bash configure_ssd_boot.sh
```
