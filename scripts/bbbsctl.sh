#!/bin/bash

################################################################################
# BTRFS Base Backup System Control Tool (bbbsctl)
#
# 这是一个用于管理 Btrfs 快照备份的控制工具，提供以下功能：
# 1. 列出所有备份的子卷列表
# 2. 恢复指定的备份
# 3. 删除备份（支持按时间保留策略）
# 4. 传输备份到远程位置
#
# 作者: ShouChenICU
# 项目: btrfs-base-backup-script
################################################################################

# 启用严格模式：遇到错误立即退出
set -e

################################################################################
# 常量定义
################################################################################

# 配置文件路径（相对于脚本所在目录）
CONFIG_FILE=$(realpath $(dirname "$(readlink -f "$0")")/../config/btrfs-base-backup.conf)

# 日志颜色定义（用于终端输出）
RED='\033[0;31m'        # 红色 - 用于错误
GREEN='\033[0;32m'      # 绿色 - 用于信息
YELLOW='\033[1;33m'     # 黄色 - 用于警告
BLUE='\033[0;34m'       # 蓝色 - 用于提示
CYAN='\033[0;36m'       # 青色 - 用于时间戳
MAGENTA='\033[0;35m'    # 洋红色 - 用于高亮
WHITE='\033[1;37m'      # 白色 - 用于重要信息
LIGHT_GRAY='\033[0;37m' # 浅灰色 - 用于普通文本
DARK_RED='\033[0;91m'   # 深红色 - 用于严重错误
NC='\033[0m'            # 无颜色 - 重置颜色

# 检测语言环境
if [[ "$LANG" =~ ^zh ]]; then
	USE_CHINESE=true
else
	USE_CHINESE=false
fi

################################################################################
# 多语言支持函数
################################################################################

# 获取翻译文本
# 参数: $1 - 英文文本, $2 - 中文文本
tr() {
	if [ "$USE_CHINESE" = true ]; then
		echo "$2"
	else
		echo "$1"
	fi
}

################################################################################
# 日志函数
################################################################################

# 输出信息级别日志
# 参数: $1 - 日志消息
log_info() {
	echo -e "${GREEN}[INFO]${NC} ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC} ${LIGHT_GRAY}$1${NC}"
}

# 输出警告级别日志
# 参数: $1 - 日志消息
log_warn() {
	echo -e "${YELLOW}[WARN]${NC} ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC} ${WHITE}$1${NC}"
}

# 输出错误级别日志
# 参数: $1 - 日志消息
log_error() {
	echo -e "${RED}[ERROR]${NC} ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC} ${DARK_RED}$1${NC}" >&2
}

# 输出成功消息
# 参数: $1 - 日志消息
log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC} ${WHITE}$1${NC}"
}

################################################################################
# 工具函数
################################################################################

# 显示帮助信息
show_help() {
	echo -e "${WHITE}BTRFS Base Backup System Control Tool (bbbsctl)${NC}"
	echo ""
	echo -e "${CYAN}$(tr 'Usage' '用法'):${NC}"
	echo "  $0 <command> [options]"
	echo ""
	echo -e "${CYAN}$(tr 'Commands' '命令'):${NC}"
	echo -e "  ${GREEN}list${NC}                           $(tr 'List all backup snapshots' '列出所有备份快照')"
	echo -e "  ${GREEN}size${NC} <snapshot>                $(tr 'Calculate snapshot size' '计算快照大小')"
	echo -e "  ${GREEN}restore${NC} <snapshot> <target>    $(tr 'Restore a snapshot' '恢复指定的备份快照')"
	echo -e "  ${GREEN}delete${NC} [options]                $(tr 'Delete backup snapshots' '删除备份快照')"
	echo -e "  ${GREEN}transfer${NC} <destination>          $(tr 'Transfer backups to destination' '传输备份到指定目录')"
	echo -e "  ${GREEN}help${NC}                            $(tr 'Show this help message' '显示此帮助信息')"
	echo ""
	echo -e "${CYAN}list $(tr 'command' '命令'):${NC}"
	echo "  $(tr 'List all snapshots in the backup directory' '列出所有存储在备份目录中的快照')"
	echo "  "
	echo "  $(tr 'Example' '示例'):"
	echo "    $0 list"
	echo ""
	echo -e "${CYAN}size $(tr 'command' '命令'):${NC}"
	echo "  $(tr 'Calculate and display the size of a specific snapshot' '计算并显示指定快照的大小')"
	echo "  "
	echo "  $(tr 'Parameters' '参数'):"
	echo "    <snapshot>  - $(tr 'Snapshot name (use list command to view)' '快照名称（使用 list 命令查看）')"
	echo "  "
	echo "  $(tr 'Example' '示例'):"
	echo "    $0 size 2025-12-01T10:30:00+08:00"
	echo ""
	echo -e "${CYAN}restore $(tr 'command' '命令'):${NC}"
	echo "  $(tr 'Restore a snapshot to a target location' '将指定的快照恢复到目标位置')"
	echo "  "
	echo "  $(tr 'Parameters' '参数'):"
	echo "    <snapshot>  - $(tr 'Snapshot name (use list command to view)' '快照名称（使用 list 命令查看可用快照）')"
	echo "    <target>    - $(tr 'Target path (must not exist)' '恢复目标路径（必须是一个不存在的路径）')"
	echo "  "
	echo "  $(tr 'Example' '示例'):"
	echo "    $0 restore 2025-12-01T10:30:00+08:00 /mnt/restored"
	echo ""
	echo -e "${CYAN}delete $(tr 'command' '命令'):${NC}"
	echo "  $(tr 'Delete backup snapshots with various strategies' '删除备份快照，支持多种删除策略')"
	echo "  "
	echo "  $(tr 'Options' '选项'):"
	echo "    --snapshot <name>     $(tr 'Delete a specific snapshot' '删除指定名称的快照')"
	echo "    --keep-days <days>    $(tr 'Keep snapshots within N days' '保留最近 N 天的快照，删除更早的')"
	echo "    --keep-count <count>  $(tr 'Keep the newest N snapshots' '保留最新的 N 个快照，删除更早的')"
	echo "    --all                 $(tr 'Delete all snapshots (confirmation required)' '删除所有快照（需要确认）')"
	echo "  "
	echo "  $(tr 'Example' '示例'):"
	echo "    $0 delete --snapshot 2025-12-01T10:30:00+08:00"
	echo "    $0 delete --keep-days 30"
	echo "    $0 delete --keep-count 10"
	echo ""
	echo -e "${CYAN}transfer $(tr 'command' '命令'):${NC}"
	echo "  $(tr 'Transfer local snapshots to remote storage' '将本地快照传输到远程或外部存储位置')"
	echo "  $(tr 'Supports incremental transfer' '支持增量传输以节省时间和空间')"
	echo "  "
	echo "  $(tr 'Parameters' '参数'):"
	echo "    <destination>  - $(tr 'Destination directory (must exist)' '目标目录路径（必须存在且可访问）')"
	echo "  "
	echo "  $(tr 'Example' '示例'):"
	echo "    $0 transfer /mnt/external/backups"
	echo "    $0 transfer /media/usb/backups"
	echo ""
	echo -e "${CYAN}$(tr 'Configuration file' '配置文件'):${NC}"
	echo "  $CONFIG_FILE"
	echo ""
	echo -e "${CYAN}$(tr 'Notes' '注意事项'):${NC}"
	echo "  • $(tr 'Requires root privileges for most operations' '需要 root 权限执行大部分操作')"
	echo "  • $(tr 'Ensure Btrfs filesystem is properly configured' '确保 Btrfs 文件系统已正确配置')"
	echo "  • $(tr 'Delete operations are irreversible' '删除操作不可恢复，请谨慎使用')"
	echo "  • $(tr 'Transfer operations may take time' '传输操作可能需要较长时间，请耐心等待')"
	echo ""
}

# 加载配置文件
# 从配置文件中读取必要的变量
load_config() {
	if [ -f "$CONFIG_FILE" ]; then
		log_info "$(tr "Loading configuration from" "正在加载配置文件"): $CONFIG_FILE"
		source "$CONFIG_FILE"
	else
		log_error "$(tr "Configuration file not found" "配置文件未找到"): $CONFIG_FILE"
		exit 1
	fi

	# 检查必需的配置变量
	if [ -z "$SOURCE_PATH" ]; then
		log_error "$(tr "Configuration error: SOURCE_PATH not set" "配置错误: SOURCE_PATH 未设置")"
		exit 1
	fi

	if [ -z "$TARGET_DIR" ]; then
		log_error "$(tr "Configuration error: TARGET_DIR not set" "配置错误: TARGET_DIR 未设置")"
		exit 1
	fi

	if [ -z "$MOUNT_POINT" ]; then
		log_error "$(tr "Configuration error: MOUNT_POINT not set" "配置错误: MOUNT_POINT 未设置")"
		exit 1
	fi

	log_info "$(tr "Configuration loaded successfully" "配置加载成功")"
	log_info "  $(tr "Source path" "源路径"): $SOURCE_PATH"
	log_info "  $(tr "Backup directory" "备份目录"): $TARGET_DIR"
	log_info "  $(tr "Mount point" "挂载点"): $MOUNT_POINT"
}

# 挂载 Btrfs 根文件系统
# 如果已经挂载则验证是否正确，否则执行挂载操作
# 返回: 设置全局变量 MOUNT_NEEDED（true/false）
mount_btrfs_root() {
	log_info "$(tr "Identifying device for source path" "正在识别源路径的设备"): $SOURCE_PATH"

	# 获取源路径的设备信息
	SOURCE_DEVICE_RAW=$(findmnt -n -o SOURCE --target "$SOURCE_PATH")

	if [ -z "$SOURCE_DEVICE_RAW" ]; then
		log_error "$(tr "Unable to find device for source path" "无法找到源路径的设备"): $SOURCE_PATH"
		exit 1
	fi

	# 去除子卷信息，获取块设备路径（如 /dev/sda1）
	SOURCE_DEVICE=$(echo "$SOURCE_DEVICE_RAW" | sed 's/\[.*\]//')
	log_info "$(tr "Found source device" "找到源设备"): $SOURCE_DEVICE"

	# 检查挂载点状态
	log_info "$(tr "Checking mount point" "检查挂载点"): $MOUNT_POINT"
	MOUNT_NEEDED=false

	if mountpoint -q "$MOUNT_POINT"; then
		# 挂载点已存在，验证是否正确
		log_info "$(tr "Mount point already mounted, verifying" "已挂载，正在验证")... ($MOUNT_POINT)"

		MOUNTED_DEVICE_RAW=$(findmnt -n -o SOURCE --target "$MOUNT_POINT")
		MOUNTED_DEVICE=$(echo "$MOUNTED_DEVICE_RAW" | sed 's/\[.*\]//')

		# 验证设备是否匹配
		if [ "$MOUNTED_DEVICE" != "$SOURCE_DEVICE" ]; then
			log_error "$(tr "Mount point is mounted to wrong device" "挂载点已挂载到错误的设备"): $MOUNT_POINT -> $MOUNTED_DEVICE ($(tr "expected" "期望"): $SOURCE_DEVICE)"
			exit 1
		fi

		# 验证是否挂载为 Btrfs 根（subvol=/）
		FSROOT=$(findmnt -n -o FSROOT --target "$MOUNT_POINT")
		if [ "$FSROOT" != "/" ]; then
			log_error "$(tr "Mount point is not mounted as Btrfs root" "挂载点未挂载为 Btrfs 根") (subvol=/), $(tr "current fsroot" "当前 fsroot"): $FSROOT"
			exit 1
		fi

		log_info "$(tr "Mount point is correctly mounted" "挂载点已正确挂载"): $MOUNT_POINT"
	else
		# 挂载点不存在，执行挂载
		log_info "$(tr "Mount point not mounted, mounting" "未挂载，正在挂载")... ($MOUNT_POINT)"
		mkdir -p "$MOUNT_POINT"
		mount -t btrfs -o subvol=/ "$SOURCE_DEVICE" "$MOUNT_POINT"
		MOUNT_NEEDED=true
		log_success "$(tr "Successfully mounted device to mount point" "已将设备挂载到挂载点"): $SOURCE_DEVICE (subvol=/) -> $MOUNT_POINT"
	fi
}

# 卸载 Btrfs 根文件系统
# 仅当由本脚本挂载时才执行卸载
unmount_btrfs_root() {
	if [ "$MOUNT_NEEDED" = true ]; then
		log_info "$(tr "Unmounting mount point" "正在卸载挂载点")... ($MOUNT_POINT)"
		umount "$MOUNT_POINT"
		log_success "$(tr "Successfully unmounted" "卸载成功")"
	fi
}

# 清理函数
# 在脚本退出时自动执行，确保资源正确释放
cleanup() {
	unmount_btrfs_root
}

# 获取快照的完整路径
# 参数: $1 - 快照名称
# 返回: 快照的完整路径
get_snapshot_path() {
	echo "$MOUNT_POINT/$TARGET_DIR/$1"
}

################################################################################
# 功能命令实现
################################################################################

# 命令: 列出所有备份快照
cmd_list() {
	log_info "$(tr "Listing all backup snapshots..." "正在列出所有备份快照...")"

	mount_btrfs_root

	FULL_TARGET_DIR="$MOUNT_POINT/$TARGET_DIR"

	# 检查备份目录是否存在
	if [ ! -d "$FULL_TARGET_DIR" ]; then
		log_warn "$(tr "Backup directory does not exist" "备份目录不存在"): $FULL_TARGET_DIR"
		log_info "$(tr "No backups have been created yet" "还没有创建任何备份")"
		return 0
	fi

	# 获取快照列表
	SNAPSHOTS=$(ls -1 "$FULL_TARGET_DIR" 2>/dev/null | sort)

	if [ -z "$SNAPSHOTS" ]; then
		log_info "$(tr "No snapshots found in backup directory" "备份目录中没有快照")"
		return 0
	fi

	# 计算快照数量
	SNAPSHOT_COUNT=$(echo "$SNAPSHOTS" | wc -l)

	echo ""
	echo -e "${WHITE}==================== $(tr "Backup Snapshot List" "备份快照列表") ====================${NC}"
	echo -e "${CYAN}$(tr "Backup directory" "备份目录"):${NC} $FULL_TARGET_DIR"
	echo -e "${CYAN}$(tr "Total snapshots" "快照总数"):${NC} $SNAPSHOT_COUNT"
	echo ""
	echo -e "${WHITE}$(tr "No." "序号")  $(tr "Snapshot Name" "快照名称")${NC}                              ${WHITE}$(tr "Creation Time" "创建时间")${NC}"
	echo "-------------------------------------------------------------"

	# 遍历并显示每个快照的信息
	INDEX=1
	for snapshot in $SNAPSHOTS; do
		SNAPSHOT_PATH="$FULL_TARGET_DIR/$snapshot"

		# 获取创建时间
		CREATE_TIME=$(stat -c %y "$SNAPSHOT_PATH" | cut -d. -f1)

		# 显示快照信息
		echo -e "$(printf "${GREEN}%-5d${NC} %-40s ${CYAN}%s${NC}" \
			"$INDEX" "$snapshot" "$CREATE_TIME")"

		INDEX=$((INDEX + 1))
	done

	echo ""
	log_success "$(tr "List display completed" "列表显示完成")"
}

# 命令: 计算快照大小
# 参数: $1 - 快照名称
cmd_size() {
	local SNAPSHOT_NAME="$1"

	# 检查参数
	if [ -z "$SNAPSHOT_NAME" ]; then
		log_error "$(tr "Missing parameter: snapshot name" "缺少参数: 快照名称")"
		echo "$(tr "Usage" "用法"): $0 size <snapshot>"
		exit 1
	fi

	log_info "$(tr "Calculating snapshot size..." "正在计算快照大小...")"

	mount_btrfs_root

	SNAPSHOT_PATH=$(get_snapshot_path "$SNAPSHOT_NAME")

	# 检查快照是否存在
	if [ ! -d "$SNAPSHOT_PATH" ]; then
		log_error "$(tr "Snapshot does not exist" "快照不存在"): $SNAPSHOT_NAME"
		log_info "$(tr "Use 'list' command to view available snapshots" "使用 'list' 命令查看可用的快照")"
		exit 1
	fi

	log_info "$(tr "Analyzing snapshot" "正在分析快照"): $SNAPSHOT_NAME"

	# 计算快照大小
	SIZE=$(du -sb "$SNAPSHOT_PATH" 2>/dev/null | awk '{print $1}')

	if [ -z "$SIZE" ]; then
		log_error "$(tr "Failed to calculate snapshot size" "无法计算快照大小")"
		exit 1
	fi

	# 转换为人类可读格式
	SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B "$SIZE" 2>/dev/null || echo "$SIZE bytes")

	echo ""
	echo -e "${WHITE}==================== $(tr "Snapshot Size" "快照大小") ====================${NC}"
	echo -e "${CYAN}$(tr "Snapshot" "快照"):${NC} $SNAPSHOT_NAME"
	echo -e "${CYAN}$(tr "Size (bytes)" "大小（字节）"):${NC} $SIZE"
	echo -e "${CYAN}$(tr "Size (human-readable)" "大小（可读格式）"):${NC} $SIZE_HUMAN"
	echo ""

	log_success "$(tr "Size calculation completed" "大小计算完成")"
}

# 命令: 恢复指定的备份快照
# 参数: $1 - 快照名称
#       $2 - 目标路径
cmd_restore() {
	local SNAPSHOT_NAME="$1"
	local TARGET_PATH="$2"

	# 检查参数
	if [ -z "$SNAPSHOT_NAME" ]; then
		log_error "$(tr "Missing parameter: snapshot name" "缺少参数: 快照名称")"
		echo "$(tr "Usage" "用法"): $0 restore <snapshot> <target>"
		exit 1
	fi

	if [ -z "$TARGET_PATH" ]; then
		log_error "$(tr "Missing parameter: target path" "缺少参数: 目标路径")"
		echo "$(tr "Usage" "用法"): $0 restore <snapshot> <target>"
		exit 1
	fi

	# 检查目标路径是否已存在
	if [ -e "$TARGET_PATH" ]; then
		log_error "$(tr "Target path already exists" "目标路径已存在"): $TARGET_PATH"
		log_error "$(tr "Please choose a non-existent path or delete the existing path first" "请选择一个不存在的路径或先删除现有路径")"
		exit 1
	fi

	log_info "$(tr "Preparing to restore snapshot..." "准备恢复快照...")"
	log_info "  $(tr "Snapshot name" "快照名称"): $SNAPSHOT_NAME"
	log_info "  $(tr "Target path" "目标路径"): $TARGET_PATH"

	mount_btrfs_root

	SNAPSHOT_PATH=$(get_snapshot_path "$SNAPSHOT_NAME")

	# 检查快照是否存在
	if [ ! -d "$SNAPSHOT_PATH" ]; then
		log_error "$(tr "Snapshot does not exist" "快照不存在"): $SNAPSHOT_PATH"
		log_info "$(tr "Use 'list' command to view available snapshots" "使用 'list' 命令查看可用的快照")"
		exit 1
	fi

	log_info "$(tr "Creating writable copy of snapshot..." "正在创建快照的可写副本...")"

	# 创建目标路径的父目录（如果不存在）
	TARGET_PARENT=$(dirname "$TARGET_PATH")
	if [ ! -d "$TARGET_PARENT" ]; then
		log_info "$(tr "Creating parent directory" "创建父目录"): $TARGET_PARENT"
		mkdir -p "$TARGET_PARENT"
	fi

	# 使用 btrfs snapshot 命令创建可写副本
	if btrfs subvolume snapshot "$SNAPSHOT_PATH" "$TARGET_PATH"; then
		log_success "$(tr "Snapshot restored successfully" "快照恢复成功")"
		log_info "$(tr "Restore location" "恢复位置"): $TARGET_PATH"

		# 显示恢复后的信息
		echo ""
		echo -e "${WHITE}==================== $(tr "Restore Information" "恢复信息") ====================${NC}"
		echo -e "${CYAN}$(tr "Source snapshot" "源快照"):${NC}   $SNAPSHOT_NAME"
		echo -e "${CYAN}$(tr "Target location" "目标位置"):${NC} $TARGET_PATH"
		echo -e "${CYAN}$(tr "Snapshot type" "快照类型"):${NC} $(tr "Writable subvolume" "可写子卷")"
		echo ""
		log_info "$(tr "You can now access and modify the restored data" "您现在可以访问和修改恢复的数据")"
	else
		log_error "$(tr "Failed to restore snapshot" "快照恢复失败")"
		exit 1
	fi
}

# 命令: 删除备份快照
# 支持多种删除策略
cmd_delete() {
	local DELETE_MODE=""
	local SNAPSHOT_NAME=""
	local KEEP_DAYS=""
	local KEEP_COUNT=""
	local DELETE_ALL=false

	# 解析参数
	while [ $# -gt 0 ]; do
		case "$1" in
		--snapshot)
			DELETE_MODE="snapshot"
			SNAPSHOT_NAME="$2"
			shift 2
			;;
		--keep-days)
			DELETE_MODE="keep-days"
			KEEP_DAYS="$2"
			shift 2
			;;
		--keep-count)
			DELETE_MODE="keep-count"
			KEEP_COUNT="$2"
			shift 2
			;;
		--all)
			DELETE_MODE="all"
			DELETE_ALL=true
			shift
			;;
		*)
			log_error "$(tr "Unknown option" "未知选项"): $1"
			echo "$(tr "Use 'help' command to view help" "使用 'help' 命令查看帮助")"
			exit 1
			;;
		esac
	done

	# 检查删除模式是否指定
	if [ -z "$DELETE_MODE" ]; then
		log_error "$(tr "Please specify delete mode" "请指定删除模式")"
		echo "$(tr "Use 'help' command to view help" "使用 'help' 命令查看帮助")"
		exit 1
	fi

	mount_btrfs_root

	FULL_TARGET_DIR="$MOUNT_POINT/$TARGET_DIR"

	# 检查备份目录是否存在
	if [ ! -d "$FULL_TARGET_DIR" ]; then
		log_warn "$(tr "Backup directory does not exist" "备份目录不存在"): $FULL_TARGET_DIR"
		return 0
	fi

	case "$DELETE_MODE" in
	snapshot)
		delete_single_snapshot "$SNAPSHOT_NAME" "$FULL_TARGET_DIR"
		;;
	keep-days)
		delete_by_days "$KEEP_DAYS" "$FULL_TARGET_DIR"
		;;
	keep-count)
		delete_by_count "$KEEP_COUNT" "$FULL_TARGET_DIR"
		;;
	all)
		delete_all_snapshots "$FULL_TARGET_DIR"
		;;
	esac
}

# 删除单个快照
# 参数: $1 - 快照名称
#       $2 - 备份目录路径
delete_single_snapshot() {
	local SNAPSHOT_NAME="$1"
	local BACKUP_DIR="$2"

	if [ -z "$SNAPSHOT_NAME" ]; then
		log_error "$(tr "Snapshot name cannot be empty" "快照名称不能为空")"
		exit 1
	fi

	local SNAPSHOT_PATH="$BACKUP_DIR/$SNAPSHOT_NAME"

	if [ ! -d "$SNAPSHOT_PATH" ]; then
		log_error "$(tr "Snapshot does not exist" "快照不存在"): $SNAPSHOT_NAME"
		exit 1
	fi

	log_warn "$(tr "Preparing to delete snapshot" "准备删除快照"): $SNAPSHOT_NAME"

	# 请求确认
	read -p "$(echo -e ${YELLOW}$(tr "Confirm deletion? [y/N]: " "确认删除? [y/N]: ")${NC})" -n 1 -r
	echo

	if [[ $REPLY =~ ^[Yy]$ ]]; then
		log_info "$(tr "Deleting snapshot..." "正在删除快照...")"
		if btrfs subvolume delete "$SNAPSHOT_PATH"; then
			log_success "$(tr "Snapshot deleted" "快照已删除"): $SNAPSHOT_NAME"
		else
			log_error "$(tr "Failed to delete snapshot" "删除快照失败")"
			exit 1
		fi
	else
		log_info "$(tr "Operation cancelled" "操作已取消")"
	fi
}

# 按保留天数删除快照
# 参数: $1 - 保留天数
#       $2 - 备份目录路径
delete_by_days() {
	local KEEP_DAYS="$1"
	local BACKUP_DIR="$2"

	if [ -z "$KEEP_DAYS" ] || ! [[ "$KEEP_DAYS" =~ ^[0-9]+$ ]]; then
		log_error "$(tr "Keep days must be a positive integer" "保留天数必须是正整数")"
		exit 1
	fi

	log_info "$(tr "Preparing to delete snapshots older than N days" "准备删除 N 天之前的快照")..."
	log_info "  $(tr "Keep days" "保留天数"): $KEEP_DAYS"

	# 计算截止时间（秒）
	CUTOFF_TIME=$(date -d "$KEEP_DAYS days ago" +%s)

	# 获取所有快照
	SNAPSHOTS=$(ls -1 "$BACKUP_DIR" 2>/dev/null | sort)

	if [ -z "$SNAPSHOTS" ]; then
		log_info "$(tr "No snapshots found" "没有找到快照")"
		return 0
	fi

	# 收集要删除的快照
	TO_DELETE=()
	for snapshot in $SNAPSHOTS; do
		SNAPSHOT_PATH="$BACKUP_DIR/$snapshot"
		SNAPSHOT_TIME=$(stat -c %Y "$SNAPSHOT_PATH")

		if [ "$SNAPSHOT_TIME" -lt "$CUTOFF_TIME" ]; then
			TO_DELETE+=("$snapshot")
		fi
	done

	# 检查是否有需要删除的快照
	if [ ${#TO_DELETE[@]} -eq 0 ]; then
		log_info "$(tr "No snapshots to delete" "没有需要删除的快照")"
		return 0
	fi

	# 显示将要删除的快照
	echo ""
	echo -e "${YELLOW}$(tr "The following snapshots will be deleted" "以下快照将被删除") ($(tr "total" "共") ${#TO_DELETE[@]} $(tr "items" "个")):${NC}"
	for snapshot in "${TO_DELETE[@]}"; do
		echo "  - $snapshot"
	done
	echo ""

	# 请求确认
	read -p "$(echo -e ${YELLOW}$(tr "Confirm deletion? [y/N]: " "确认删除? [y/N]: ")${NC})" -n 1 -r
	echo

	if [[ $REPLY =~ ^[Yy]$ ]]; then
		log_info "$(tr "Deleting snapshots..." "正在删除快照...")"
		local DELETED_COUNT=0
		for snapshot in "${TO_DELETE[@]}"; do
			SNAPSHOT_PATH="$BACKUP_DIR/$snapshot"
			if btrfs subvolume delete "$SNAPSHOT_PATH" >/dev/null 2>&1; then
				log_info "$(tr "Deleted" "已删除"): $snapshot"
				DELETED_COUNT=$((DELETED_COUNT + 1))
			else
				log_error "$(tr "Failed to delete" "删除失败"): $snapshot"
			fi
		done
		log_success "$(tr "Deletion completed, total deleted" "删除完成，共删除") $DELETED_COUNT $(tr "snapshots" "个快照")"
	else
		log_info "$(tr "Operation cancelled" "操作已取消")"
	fi
}

# 按保留数量删除快照
# 参数: $1 - 保留数量
#       $2 - 备份目录路径
delete_by_count() {
	local KEEP_COUNT="$1"
	local BACKUP_DIR="$2"

	if [ -z "$KEEP_COUNT" ] || ! [[ "$KEEP_COUNT" =~ ^[0-9]+$ ]]; then
		log_error "$(tr "Keep count must be a positive integer" "保留数量必须是正整数")"
		exit 1
	fi

	log_info "$(tr "Preparing to keep the newest N snapshots and delete the rest" "准备保留最新的 N 个快照，删除其余的")..."
	log_info "  $(tr "Keep count" "保留数量"): $KEEP_COUNT"

	# 获取所有快照（按时间排序）
	SNAPSHOTS=$(ls -1t "$BACKUP_DIR" 2>/dev/null)

	if [ -z "$SNAPSHOTS" ]; then
		log_info "$(tr "No snapshots found" "没有找到快照")"
		return 0
	fi

	# 计算快照总数
	TOTAL_COUNT=$(echo "$SNAPSHOTS" | wc -l)

	if [ "$TOTAL_COUNT" -le "$KEEP_COUNT" ]; then
		log_info "$(tr "Current snapshot count does not exceed keep count, no deletion needed" "当前快照数量未超过保留数量，无需删除") ($TOTAL_COUNT <= $KEEP_COUNT)"
		return 0
	fi

	# 收集要删除的快照（跳过前 N 个最新的）
	TO_DELETE=()
	INDEX=0
	for snapshot in $SNAPSHOTS; do
		INDEX=$((INDEX + 1))
		if [ $INDEX -gt $KEEP_COUNT ]; then
			TO_DELETE+=("$snapshot")
		fi
	done

	# 显示将要删除的快照
	echo ""
	echo -e "${YELLOW}$(tr "The following snapshots will be deleted" "以下快照将被删除") ($(tr "total" "共") ${#TO_DELETE[@]} $(tr "items" "个")):${NC}"
	for snapshot in "${TO_DELETE[@]}"; do
		echo "  - $snapshot"
	done
	echo ""

	# 请求确认
	read -p "$(echo -e ${YELLOW}$(tr "Confirm deletion? [y/N]: " "确认删除? [y/N]: ")${NC})" -n 1 -r
	echo

	if [[ $REPLY =~ ^[Yy]$ ]]; then
		log_info "$(tr "Deleting snapshots..." "正在删除快照...")"
		local DELETED_COUNT=0
		for snapshot in "${TO_DELETE[@]}"; do
			SNAPSHOT_PATH="$BACKUP_DIR/$snapshot"
			if btrfs subvolume delete "$SNAPSHOT_PATH" >/dev/null 2>&1; then
				log_info "$(tr "Deleted" "已删除"): $snapshot"
				DELETED_COUNT=$((DELETED_COUNT + 1))
			else
				log_error "$(tr "Failed to delete" "删除失败"): $snapshot"
			fi
		done
		log_success "$(tr "Deletion completed, total deleted" "删除完成，共删除") $DELETED_COUNT $(tr "snapshots" "个快照")"
	else
		log_info "$(tr "Operation cancelled" "操作已取消")"
	fi
}

# 删除所有快照
# 参数: $1 - 备份目录路径
delete_all_snapshots() {
	local BACKUP_DIR="$1"

	log_warn "$(tr "Preparing to delete all snapshots..." "准备删除所有快照...")"

	# 获取所有快照
	SNAPSHOTS=$(ls -1 "$BACKUP_DIR" 2>/dev/null)

	if [ -z "$SNAPSHOTS" ]; then
		log_info "$(tr "No snapshots found" "没有找到快照")"
		return 0
	fi

	# 计算快照数量
	SNAPSHOT_COUNT=$(echo "$SNAPSHOTS" | wc -l)

	echo ""
	echo -e "${RED}$(tr "WARNING: This operation will delete all N snapshots!" "警告: 此操作将删除所有 N 个快照！") ($SNAPSHOT_COUNT)${NC}"
	echo -e "${RED}$(tr "This operation is irreversible!" "此操作不可恢复！")${NC}"
	echo ""

	# 请求双重确认
	read -p "$(echo -e ${YELLOW}$(tr "Confirm deleting all snapshots? Type 'yes' to continue: " "确认删除所有快照? 输入 'yes' 继续: ")${NC})" -r
	echo

	if [ "$REPLY" = "yes" ]; then
		log_info "$(tr "Deleting all snapshots..." "正在删除所有快照...")"
		local DELETED_COUNT=0
		for snapshot in $SNAPSHOTS; do
			SNAPSHOT_PATH="$BACKUP_DIR/$snapshot"
			if btrfs subvolume delete "$SNAPSHOT_PATH" >/dev/null 2>&1; then
				log_info "$(tr "Deleted" "已删除"): $snapshot"
				DELETED_COUNT=$((DELETED_COUNT + 1))
			else
				log_error "$(tr "Failed to delete" "删除失败"): $snapshot"
			fi
		done
		log_success "$(tr "Deletion completed, total deleted" "删除完成，共删除") $DELETED_COUNT $(tr "snapshots" "个快照")"
	else
		log_info "$(tr "Operation cancelled" "操作已取消")"
	fi
}

# 命令: 传输快照到指定目录
# 参数: $1 - 目标目录
cmd_transfer() {
	local DEST_DIR="$1"

	# 检查参数
	if [ -z "$DEST_DIR" ]; then
		log_error "$(tr "Missing parameter: destination directory" "缺少参数: 目标目录")"
		echo "$(tr "Usage" "用法"): $0 transfer <destination>"
		exit 1
	fi

	# 检查目标目录是否存在
	if [ ! -d "$DEST_DIR" ]; then
		log_error "$(tr "Destination directory does not exist" "目标目录不存在"): $DEST_DIR"
		exit 1
	fi

	log_info "$(tr "Preparing to transfer snapshots to destination..." "准备传输快照到目标目录...")"
	log_info "  $(tr "Destination directory" "目标目录"): $DEST_DIR"

	mount_btrfs_root

	FULL_TARGET_DIR="$MOUNT_POINT/$TARGET_DIR"

	# 检查源备份目录是否存在
	if [ ! -d "$FULL_TARGET_DIR" ]; then
		log_error "$(tr "Source backup directory does not exist" "源备份目录不存在"): $FULL_TARGET_DIR"
		exit 1
	fi

	log_info "$(tr "Scanning snapshots..." "正在扫描快照...")"

	# 获取最新的本地快照
	LATEST_LOCAL=$(ls -1 "$FULL_TARGET_DIR" 2>/dev/null | sort | tail -n 1)

	if [ -z "$LATEST_LOCAL" ]; then
		log_warn "$(tr "No snapshots in source backup directory, no transfer needed" "源备份目录中没有快照，无需传输")"
		return 0
	fi

	log_info "$(tr "Latest local snapshot" "最新本地快照"): $LATEST_LOCAL"

	# 查找共同的父快照
	COMMON_PARENT=""
	# 按时间倒序遍历本地快照，找到最近的共同快照
	for snap in $(ls -1 "$FULL_TARGET_DIR" 2>/dev/null | sort -r); do
		if [ -d "$DEST_DIR/$snap" ]; then
			COMMON_PARENT="$snap"
			break
		fi
	done

	# 根据是否找到共同父快照，选择传输方式
	if [ -z "$COMMON_PARENT" ]; then
		# 没有找到共同父快照，执行完全传输
		log_info "$(tr "No common parent snapshot found, performing full transfer..." "未找到共同父快照，将执行完全传输...")"
		log_info "$(tr "Transferring" "正在传输"): $LATEST_LOCAL"

		echo ""
		echo -e "${WHITE}==================== $(tr "Transfer Progress" "传输进度") ====================${NC}"

		if btrfs send "$FULL_TARGET_DIR/$LATEST_LOCAL" | dd bs=1MiB status=progress | btrfs receive "$DEST_DIR"; then
			echo ""
			log_success "$(tr "Full transfer completed" "完全传输完成")"
			log_info "$(tr "Transferred snapshot" "已传输快照"): $LATEST_LOCAL"
		else
			echo ""
			log_error "$(tr "Transfer failed" "传输失败")"
			exit 1
		fi
	elif [ "$COMMON_PARENT" = "$LATEST_LOCAL" ]; then
		# 目标已是最新状态
		log_info "$(tr "Destination directory is already up to date" "目标目录已是最新状态") ($(tr "latest snapshot" "最新快照"): $LATEST_LOCAL)"
		log_info "$(tr "No transfer needed" "无需传输")"
	else
		# 找到共同父快照，执行增量传输
		log_info "$(tr "Common parent snapshot found" "找到共同父快照"): $COMMON_PARENT"
		log_info "$(tr "Performing incremental transfer" "将执行增量传输"): $COMMON_PARENT -> $LATEST_LOCAL"

		echo ""
		echo -e "${WHITE}==================== $(tr "Transfer Progress" "传输进度") ====================${NC}"

		if btrfs send -p "$FULL_TARGET_DIR/$COMMON_PARENT" "$FULL_TARGET_DIR/$LATEST_LOCAL" | dd bs=1MiB status=progress | btrfs receive "$DEST_DIR"; then
			echo ""
			log_success "$(tr "Incremental transfer completed" "增量传输完成")"
			log_info "$(tr "Base snapshot" "基准快照"): $COMMON_PARENT"
			log_info "$(tr "Transferred snapshot" "已传输快照"): $LATEST_LOCAL"
		else
			echo ""
			log_error "$(tr "Transfer failed" "传输失败")"
			exit 1
		fi
	fi

	echo ""
	echo -e "${WHITE}==================== $(tr "Transfer Summary" "传输摘要") ====================${NC}"
	echo -e "${CYAN}$(tr "Source directory" "源目录"):${NC}   $FULL_TARGET_DIR"
	echo -e "${CYAN}$(tr "Destination directory" "目标目录"):${NC} $DEST_DIR"
	echo -e "${CYAN}$(tr "Latest snapshot" "最新快照"):${NC} $LATEST_LOCAL"
	echo ""

	log_success "$(tr "Transfer process completed" "传输过程完成")"
}

################################################################################
# 主程序入口
################################################################################

# 设置清理陷阱，确保脚本退出时执行清理
trap cleanup EXIT

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
	log_error "$(tr "This script requires root privileges" "此脚本需要 root 权限运行")"
	echo "$(tr "Please run this script with sudo" "请使用 sudo 运行此脚本")"
	exit 1
fi

# 检查命令行参数
if [ $# -eq 0 ]; then
	log_error "$(tr "Missing command parameter" "缺少命令参数")"
	echo ""
	show_help
	exit 1
fi

# 获取命令
COMMAND="$1"
shift

# 加载配置文件
load_config

# 根据命令执行相应的操作
case "$COMMAND" in
list)
	cmd_list
	;;
size)
	cmd_size "$@"
	;;
restore)
	cmd_restore "$@"
	;;
delete)
	cmd_delete "$@"
	;;
transfer)
	cmd_transfer "$@"
	;;
help | --help | -h)
	show_help
	;;
*)
	log_error "$(tr "Unknown command" "未知命令"): $COMMAND"
	echo ""
	show_help
	exit 1
	;;
esac

exit 0
