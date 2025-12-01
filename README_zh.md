# 📦 基于 Btrfs 的备份脚本

<div align="center">

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-green.svg)
![Btrfs](https://img.shields.io/badge/filesystem-btrfs-orange.svg)

一个强大且自动化的 Btrfs 快照备份解决方案，提供完整的快照管理功能。

[English](README.md) | 简体中文

[特性](#-特性) • [安装](#-安装) • [使用](#-使用) • [配置](#-配置) • [许可证](#-许可证)

</div>

---

## 📋 概述

**btrfs-base-backup-script** 是专为 Btrfs 文件系统设计的综合备份解决方案。它提供自动化快照创建、列表查看、恢复、删除和增量传输等完整的备份管理功能，非常适合需要可靠备份工作流的系统管理员和高级用户。

该项目包含两个主要组件：

- **备份脚本** (`backup.sh`)：自动创建带有时间戳命名的只读 Btrfs 快照
- **控制工具** (`bbbsctl.sh`)：提供快照的列表、大小计算、恢复、删除和传输等管理功能

## ✨ 特性

- 🔄 **自动化快照**：创建带 ISO 8601 时间戳的只读 Btrfs 快照
- 📋 **快照管理**：列出、查看大小、恢复和删除快照
- 📊 **增量传输**：使用父快照进行高效的增量备份传输
- 🗑️ **灵活删除**：支持按天数、数量或指定快照删除
- 🌍 **多语言支持**：根据系统语言环境自动切换中英文界面
- 🎨 **彩色日志**：美观的彩色输出，便于监控
- ⚙️ **Systemd 集成**：内置定时器和服务单元以实现自动化
- 🛡️ **错误处理**：健壮的错误检查和自动清理
- 🔍 **智能检测**：自动检测设备并验证挂载点
- 📦 **灵活配置**：易于自定义的配置文件

## 🚀 安装

### 前置要求

- 使用 Btrfs 文件系统的 Linux 系统
- Bash shell
- Root 或 sudo 权限
- 已安装 `btrfs-progs` 软件包

### 快速安装

1. **克隆仓库**（推荐安装到 `/opt` 目录）：

   ```bash
   sudo git clone https://github.com/ShouChenICU/btrfs-base-backup-script.git /opt/btrfs-base-backup-script
   cd /opt/btrfs-base-backup-script
   ```

2. **设置脚本可执行权限**：

   ```bash
   sudo chmod +x scripts/*.sh
   ```

3. **配置备份设置**：

   ```bash
   sudo nano config/btrfs-base-backup.conf
   ```

4. **（可选）安装 systemd 单元**：
   ```bash
   sudo cp systemd/*.{service,timer} /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable btrfs-base-backup.timer
   sudo systemctl start btrfs-base-backup.timer
   ```

## 🎯 使用

### 创建快照

使用 `backup.sh` 手动创建快照：

```bash
sudo /opt/btrfs-base-backup-script/scripts/backup.sh
```

脚本将会：

1. 检测您的 Btrfs 设备
2. 必要时挂载 Btrfs 根目录
3. 创建带有 ISO 8601 时间戳的只读快照
4. 卸载并清理

### 管理快照

使用 `bbbsctl.sh` 控制工具管理快照：

**查看帮助信息**：

```bash
sudo /opt/btrfs-base-backup-script/scripts/bbbsctl.sh help
```

**列出所有快照**：

```bash
sudo /opt/btrfs-base-backup-script/scripts/bbbsctl.sh list
```

**计算快照大小**：

```bash
sudo /opt/btrfs-base-backup-script/scripts/bbbsctl.sh size 2025-12-01T10:30:00+08:00
```

**恢复快照**：

```bash
sudo /opt/btrfs-base-backup-script/scripts/bbbsctl.sh restore 2025-12-01T10:30:00+08:00 /mnt/restored
```

**删除快照**：

```bash
# 删除指定快照
sudo /opt/btrfs-base-backup-script/scripts/bbbsctl.sh delete --snapshot 2025-12-01T10:30:00+08:00

# 保留最近 30 天的快照，删除更早的
sudo /opt/btrfs-base-backup-script/scripts/bbbsctl.sh delete --keep-days 30

# 保留最新的 10 个快照，删除更早的
sudo /opt/btrfs-base-backup-script/scripts/bbbsctl.sh delete --keep-count 10

# 删除所有快照（需要确认）
sudo /opt/btrfs-base-backup-script/scripts/bbbsctl.sh delete --all
```

**传输快照**：

```bash
# 将快照传输到外部存储
sudo /opt/btrfs-base-backup-script/scripts/bbbsctl.sh transfer /mnt/external/backups
```

脚本会自动：

- 检测最新的本地快照
- 查找共同的父快照
- 执行增量传输（如果没有父快照则执行完整传输）
- 使用 `dd` 显示传输进度

### 使用 Systemd 自动备份

查看定时器状态：

```bash
systemctl status btrfs-base-backup.timer
```

查看最近的备份日志：

```bash
journalctl -u btrfs-base-backup.service -n 50
```

手动触发备份：

```bash
sudo systemctl start btrfs-base-backup.service
```

## ⚙️ 配置

编辑 `config/btrfs-base-backup.conf`：

```bash
# 要备份的源子卷路径（例如 / 或 /home）
SOURCE_PATH="/"

# 在 btrfs 根目录中存储快照的目录
# 此路径相对于 Btrfs 文件系统的根目录（subvol=/）
TARGET_DIR="backups"

# 用于挂载 Btrfs 根目录的挂载点
MOUNT_POINT="/mnt/rootfs"
```

### 配置参数

| 参数          | 描述                                | 示例           |
| ------------- | ----------------------------------- | -------------- |
| `SOURCE_PATH` | 要备份的子卷                        | `/` 或 `/home` |
| `TARGET_DIR`  | 快照存储目录（相对于 Btrfs 根目录） | `backups`      |
| `MOUNT_POINT` | Btrfs 根目录的临时挂载点            | `/mnt/rootfs`  |

## 📂 项目结构

```
btrfs-base-backup-script/
├── README.md                          # 英文说明文档
├── README_zh.md                       # 中文说明文档
├── LICENSE                            # MIT 许可证
├── config/
│   └── btrfs-base-backup.conf        # 配置文件
├── scripts/
│   ├── backup.sh                      # 快照创建脚本
│   └── bbbsctl.sh                     # 快照管理控制工具
└── systemd/
    ├── btrfs-base-backup.service     # Systemd 服务单元
    └── btrfs-base-backup.timer       # Systemd 定时器单元
```

## 🔍 工作原理

### 快照创建过程 (`backup.sh`)

1. **设备检测**：识别包含源路径的 Btrfs 设备
2. **根目录挂载**：将 Btrfs 根目录（`subvol=/`）挂载到临时挂载点
3. **快照创建**：创建带有 ISO 8601 时间戳的只读快照
4. **清理**：卸载临时挂载点

### 快照管理过程 (`bbbsctl.sh`)

- **列出快照**：扫描备份目录中的所有快照并显示快照信息
- **计算大小**：计算指定快照占用的磁盘空间
- **恢复快照**：将快照恢复到指定位置
- **删除快照**：根据各种条件删除快照（天数、数量、指定快照或全部）
- **传输快照**：执行增量或完整传输到外部存储

## 🛠️ 高级用法

### 自定义备份计划

编辑 systemd 定时器以自定义备份频率：

```bash
sudo systemctl edit btrfs-base-backup.timer
```

### 备份多个子卷

为不同的子卷创建多个配置文件和服务单元：

```bash
sudo cp config/btrfs-base-backup.conf config/btrfs-base-backup-home.conf
sudo cp systemd/btrfs-base-backup.service systemd/btrfs-base-backup-home.service
# 相应地编辑配置和服务文件
```

### 远程备份

结合 SSH 进行远程备份：

```bash
# 方法 1: 直接使用 btrfs send/receive 通过 SSH
sudo btrfs send /mnt/rootfs/backups/2025-12-01T10:00:00+08:00 | \
  ssh user@remote "btrfs receive /mnt/backup"

# 方法 2: 先挂载远程目录，然后使用 bbbsctl 传输
sudo sshfs user@remote:/mnt/backup /mnt/remote
sudo /opt/btrfs-base-backup-script/scripts/bbbsctl.sh transfer /mnt/remote
```

### 定期清理旧快照

创建定期清理任务，保留最近 30 天的快照：

```bash
# 创建清理脚本
echo '#!/bin/bash' | sudo tee /opt/btrfs-base-backup-script/scripts/cleanup.sh
echo '/opt/btrfs-base-backup-script/scripts/bbbsctl.sh delete --keep-days 30' | sudo tee -a /opt/btrfs-base-backup-script/scripts/cleanup.sh
sudo chmod +x /opt/btrfs-base-backup-script/scripts/cleanup.sh

# 添加到 crontab（每周日凌晨 3 点执行）
(sudo crontab -l 2>/dev/null; echo "0 3 * * 0 /opt/btrfs-base-backup-script/scripts/cleanup.sh") | sudo crontab -
```

## 🤝 贡献

欢迎贡献！以下是您可以提供帮助的方式：

1. Fork 本仓库
2. 创建特性分支（`git checkout -b feature/amazing-feature`）
3. 提交您的更改（`git commit -m 'Add some amazing feature'`）
4. 推送到分支（`git push origin feature/amazing-feature`）
5. 开启 Pull Request

## 📝 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。

## 📮 联系与支持

- **作者**：ShouChen
- **仓库**：[https://github.com/ShouChenICU/btrfs-base-backup-script](https://github.com/ShouChenICU/btrfs-base-backup-script)
- **问题反馈**：[报告 bug 或请求新功能](https://github.com/ShouChenICU/btrfs-base-backup-script/issues)

## ⚠️ 免责声明

在依赖备份和恢复程序处理关键数据之前，请始终在安全环境中进行测试。虽然此脚本包含错误处理，但没有任何备份解决方案是完美的。请维护重要数据的多个备份副本。

---

<div align="center">

由 [ShouChen](https://github.com/ShouChenICU) 用 ❤️ 制作

⭐ 如果这个项目对您有帮助，请给个 Star！

</div>
