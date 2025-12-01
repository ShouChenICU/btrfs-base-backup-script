# 📦 Btrfs Base Backup Script

<div align="center">

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-green.svg)
![Btrfs](https://img.shields.io/badge/filesystem-btrfs-orange.svg)

A robust and automated Btrfs snapshot backup solution with incremental transfer capabilities.

English | [简体中文](README_zh.md)

[Features](#-features) • [Installation](#-installation) • [Usage](#-usage) • [Configuration](#-configuration) • [License](#-license)

</div>

---

## 📋 Overview

**btrfs-base-backup-script** is a comprehensive backup solution designed for Btrfs filesystems. It provides automated snapshot creation and efficient incremental transfer capabilities, making it ideal for system administrators and power users who need reliable backup workflows.

The project consists of two main components:

- **Backup Script**: Creates read-only Btrfs snapshots with timestamp-based naming
- **Transfer Script**: Performs incremental or full transfers to external storage

## ✨ Features

- 🔄 **Automated Snapshots**: Create timestamped, read-only Btrfs snapshots
- 📊 **Incremental Transfers**: Efficient incremental backups using parent snapshots
- 🎨 **Colorful Logging**: Beautiful, color-coded output for easy monitoring
- ⚙️ **Systemd Integration**: Built-in timer and service units for automation
- 🛡️ **Error Handling**: Robust error checking and automatic cleanup
- 🔍 **Smart Detection**: Automatically detects devices and validates mount points
- 📦 **Flexible Configuration**: Easy-to-customize configuration file

## 🚀 Installation

### Prerequisites

- Linux system with Btrfs filesystem
- Bash shell
- Root or sudo access
- `btrfs-progs` package installed

### Quick Install

1. **Clone the repository**:

   ```bash
   git clone https://github.com/ShouChenICU/btrfs-base-backup-script.git
   cd btrfs-base-backup-script
   ```

2. **Make scripts executable**:

   ```bash
   chmod +x scripts/*.sh
   ```

3. **Configure backup settings**:

   ```bash
   sudo nano config/btrfs-base-backup.conf
   ```

4. **(Optional) Install systemd units**:
   ```bash
   sudo cp systemd/*.{service,timer} /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable btrfs-base-backup.timer
   sudo systemctl start btrfs-base-backup.timer
   ```

## 🎯 Usage

### Manual Backup

Create a snapshot manually:

```bash
sudo ./scripts/backup.sh
```

This will:

1. Detect your Btrfs device
2. Mount the Btrfs root if needed
3. Create a read-only snapshot with ISO 8601 timestamp
4. Unmount and cleanup

### Transfer Snapshots

Transfer snapshots to external storage:

```bash
sudo ./scripts/transfer.sh /path/to/destination
```

The script automatically:

- Detects the latest local snapshot
- Finds common parent snapshots
- Performs incremental transfer (or full if no parent exists)
- Shows transfer progress with `dd`

### Automated Backups with Systemd

View timer status:

```bash
systemctl status btrfs-base-backup.timer
```

Check recent backup logs:

```bash
journalctl -u btrfs-base-backup.service -n 50
```

Manually trigger a backup:

```bash
sudo systemctl start btrfs-base-backup.service
```

## ⚙️ Configuration

Edit `config/btrfs-base-backup.conf`:

```bash
# The source subvolume path to backup (e.g., / or /home)
SOURCE_PATH="/"

# The directory inside the btrfs root where snapshots will be stored
# This path is relative to the root of the Btrfs filesystem (subvol=/)
TARGET_DIR="backups"

# The mount point used for mounting the Btrfs root
MOUNT_POINT="/mnt/rootfs"
```

### Configuration Parameters

| Parameter     | Description                                         | Example        |
| ------------- | --------------------------------------------------- | -------------- |
| `SOURCE_PATH` | The subvolume to backup                             | `/` or `/home` |
| `TARGET_DIR`  | Snapshot storage directory (relative to Btrfs root) | `backups`      |
| `MOUNT_POINT` | Temporary mount point for Btrfs root                | `/mnt/rootfs`  |

## 📂 Project Structure

```
btrfs-base-backup-script/
├── README.md                          # This file
├── config/
│   └── btrfs-base-backup.conf        # Configuration file
├── scripts/
│   ├── backup.sh                      # Snapshot creation script
│   └── transfer.sh                    # Incremental transfer script
└── systemd/
    ├── btrfs-base-backup.service     # Systemd service unit
    └── btrfs-base-backup.timer       # Systemd timer unit
```

## 🔍 How It Works

### Backup Process

1. **Device Detection**: Identifies the Btrfs device containing the source path
2. **Root Mounting**: Mounts the Btrfs root (`subvol=/`) to a temporary mount point
3. **Snapshot Creation**: Creates a read-only snapshot with ISO 8601 timestamp
4. **Cleanup**: Unmounts the temporary mount point

### Transfer Process

1. **Mount Verification**: Ensures Btrfs root is accessible
2. **Snapshot Discovery**: Scans for available snapshots
3. **Parent Detection**: Identifies common parent for incremental transfer
4. **Transfer Execution**: Uses `btrfs send/receive` for efficient data transfer
5. **Automatic Cleanup**: Unmounts if mounted by the script

## 🛠️ Advanced Usage

### Custom Backup Schedule

Edit the systemd timer to customize backup frequency:

```bash
sudo systemctl edit btrfs-base-backup.timer
```

### Backup Multiple Subvolumes

Create multiple configuration files and service units for different subvolumes:

```bash
cp config/btrfs-base-backup.conf config/btrfs-base-backup-home.conf
cp systemd/btrfs-base-backup.service systemd/btrfs-base-backup-home.service
# Edit configurations and service files accordingly
```

### Remote Backups

Combine with SSH for remote backups:

```bash
sudo btrfs send /mnt/rootfs/backups/2025-12-01T10:00:00+08:00 | \
  ssh user@remote "btrfs receive /mnt/backup"
```

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📮 Contact & Support

- **Author**: ShouChen
- **Repository**: [https://github.com/ShouChenICU/btrfs-base-backup-script](https://github.com/ShouChenICU/btrfs-base-backup-script)
- **Issues**: [Report a bug or request a feature](https://github.com/ShouChenICU/btrfs-base-backup-script/issues)

## ⚠️ Disclaimer

Always test backup and restore procedures in a safe environment before relying on them for critical data. While this script includes error handling, no backup solution is perfect. Maintain multiple backup copies of important data.

---

<div align="center">

Made with ❤️ by [ShouChen](https://github.com/ShouChenICU)

⭐ Star this repository if you find it helpful!

</div>
