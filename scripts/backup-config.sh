#!/bin/bash
#
# Pi Gateway - Configuration Backup & Restore
# Comprehensive backup and restore system for Pi Gateway configurations
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/pi-gateway-backup.log"
readonly BACKUP_BASE_DIR="/var/backups/pi-gateway"
readonly BACKUP_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly BACKUP_DIR="$BACKUP_BASE_DIR/$BACKUP_TIMESTAMP"

# Backup configuration
readonly BACKUP_RETENTION_DAYS=30
readonly COMPRESSION_ENABLED=true
readonly BACKUP_VERIFICATION=true

# Files and directories to backup
declare -A BACKUP_ITEMS=(
    # SSH Configuration
    ["/etc/ssh/sshd_config"]="ssh/sshd_config"
    ["/etc/ssh/ssh_host_*"]="ssh/host_keys/"
    ["/home/pi/.ssh/"]="user/ssh/"

    # Firewall Configuration
    ["/etc/ufw/"]="firewall/ufw/"
    ["/etc/fail2ban/"]="firewall/fail2ban/"

    # VPN Configuration
    ["/etc/wireguard/"]="vpn/wireguard/"

    # Remote Desktop Configuration
    ["/etc/xrdp/"]="remote-desktop/xrdp/"
    ["/home/pi/.vnc/"]="remote-desktop/vnc/"

    # DDNS Configuration
    ["/etc/ddclient.conf"]="ddns/ddclient.conf"
    ["/var/cache/ddclient/"]="ddns/cache/"

    # System Configuration
    ["/etc/sysctl.conf"]="system/sysctl.conf"
    ["/etc/crontab"]="system/crontab"
    ["/etc/cron.d/"]="system/cron.d/"

    # Pi Gateway specific
    ["/etc/pi-gateway/"]="pi-gateway/"
    ["/var/log/pi-gateway/"]="logs/"
)

# Service configurations to backup
declare -A SERVICE_CONFIGS=(
    ["ssh"]="/etc/systemd/system/ssh.service.d/"
    ["wireguard"]="/etc/systemd/system/wg-quick@.service.d/"
    ["vncserver"]="/etc/systemd/system/vncserver@.service"
    ["ddclient"]="/etc/systemd/system/ddclient.service.d/"
)

# Command options
OPERATION=""
BACKUP_NAME=""
RESTORE_NAME=""
DRY_RUN=false
VERBOSE=false
INCLUDE_LOGS=false
INCLUDE_KEYS=true

# Status tracking
BACKUP_SIZE=0
BACKUP_FILE_COUNT=0
ERRORS_COUNT=0

# Logging functions
log() {
    local level="$1"
    shift
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $level: $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "  ${GREEN}✓${NC} $1"
    log "SUCCESS" "$1"
}

error() {
    echo -e "  ${RED}✗${NC} $1"
    log "ERROR" "$1"
    ((ERRORS_COUNT++))
}

warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    log "WARN" "$1"
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
    log "INFO" "$1"
}

debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "  ${PURPLE}🔍${NC} $1"
        log "DEBUG" "$1"
    fi
}

progress() {
    echo -e "  ${CYAN}⚡${NC} $1"
    log "PROGRESS" "$1"
}

# Display functions
print_header() {
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                ${WHITE}Pi Gateway Backup & Restore${NC}${BLUE}                ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo
}

print_backup_summary() {
    local backup_path="$1"
    local duration="$2"

    echo
    echo -e "${GREEN}📦 Backup Summary:${NC}"
    echo -e "  ${YELLOW}Backup Path:${NC} $backup_path"
    echo -e "  ${YELLOW}Files Backed Up:${NC} $BACKUP_FILE_COUNT"
    echo -e "  ${YELLOW}Total Size:${NC} $(du -h "$backup_path" 2>/dev/null | cut -f1 || echo "unknown")"
    echo -e "  ${YELLOW}Duration:${NC} ${duration}s"
    echo -e "  ${YELLOW}Errors:${NC} $ERRORS_COUNT"
    echo
}

# Backup functions
check_prerequisites() {
    info "Checking backup prerequisites..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run with sudo privileges for full backup access"
        return 1
    fi

    # Check available disk space
    local available_space
    available_space=$(df "$BACKUP_BASE_DIR" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    local required_space=1048576  # 1GB in KB

    if [[ "$available_space" -lt "$required_space" ]]; then
        warning "Low disk space available for backup ($(($available_space / 1024))MB available)"
    fi

    # Create backup directory
    if mkdir -p "$BACKUP_DIR"; then
        success "Backup directory created: $BACKUP_DIR"
    else
        error "Failed to create backup directory: $BACKUP_DIR"
        return 1
    fi

    return 0
}

backup_item() {
    local source="$1"
    local dest_subdir="$2"
    local dest_path="$BACKUP_DIR/$dest_subdir"

    debug "Backing up: $source -> $dest_subdir"

    # Create destination directory
    mkdir -p "$(dirname "$dest_path")"

    # Handle different source types
    if [[ "$source" == *"*" ]]; then
        # Wildcard pattern
        local base_dir="${source%/*}"
        local pattern="${source##*/}"

        if [[ -d "$base_dir" ]]; then
            local found_files
            found_files=$(find "$base_dir" -maxdepth 1 -name "$pattern" 2>/dev/null || true)

            if [[ -n "$found_files" ]]; then
                while IFS= read -r file; do
                    if [[ -f "$file" ]]; then
                        cp "$file" "$dest_path/" 2>/dev/null || warning "Failed to backup: $file"
                        ((BACKUP_FILE_COUNT++))
                    fi
                done <<< "$found_files"
                success "Backed up pattern: $source"
            else
                warning "No files found matching pattern: $source"
            fi
        else
            warning "Source directory not found: $base_dir"
        fi

    elif [[ -f "$source" ]]; then
        # Regular file
        if cp "$source" "$dest_path" 2>/dev/null; then
            success "Backed up file: $source"
            ((BACKUP_FILE_COUNT++))
        else
            warning "Failed to backup file: $source"
        fi

    elif [[ -d "$source" ]]; then
        # Directory
        if cp -r "$source" "$dest_path" 2>/dev/null; then
            local file_count
            file_count=$(find "$dest_path" -type f | wc -l)
            success "Backed up directory: $source ($file_count files)"
            BACKUP_FILE_COUNT=$((BACKUP_FILE_COUNT + file_count))
        else
            warning "Failed to backup directory: $source"
        fi

    else
        debug "Source not found (may be optional): $source"
    fi
}

create_backup_manifest() {
    local manifest_file="$BACKUP_DIR/MANIFEST.txt"

    progress "Creating backup manifest..."

    cat > "$manifest_file" << EOF
Pi Gateway Backup Manifest
==========================

Backup Information:
- Timestamp: $BACKUP_TIMESTAMP
- Created: $(date)
- Hostname: $(hostname)
- Pi Gateway Version: $(git -C "$SCRIPT_DIR/.." describe --tags 2>/dev/null || echo "unknown")
- Backup Type: Configuration and Keys
- Total Files: $BACKUP_FILE_COUNT

System Information:
- OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "unknown")
- Kernel: $(uname -r)
- Hardware: $(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "unknown")
- IP Address: $(hostname -I | awk '{print $1}' || echo "unknown")

Included Components:
EOF

    # List backed up components
    for source in "${!BACKUP_ITEMS[@]}"; do
        local dest="${BACKUP_ITEMS[$source]}"
        if [[ -e "$BACKUP_DIR/$dest" ]]; then
            echo "- $source -> $dest" >> "$manifest_file"
        fi
    done

    cat >> "$manifest_file" << EOF

Service Configurations:
EOF

    for service in "${!SERVICE_CONFIGS[@]}"; do
        local config_path="${SERVICE_CONFIGS[$service]}"
        if [[ -e "$config_path" ]]; then
            echo "- $service: $config_path" >> "$manifest_file"
        fi
    done

    success "Backup manifest created"
}

compress_backup() {
    if [[ "$COMPRESSION_ENABLED" != "true" ]]; then
        return 0
    fi

    progress "Compressing backup archive..."

    local archive_name="pi-gateway-backup-$BACKUP_TIMESTAMP.tar.gz"
    local archive_path="$BACKUP_BASE_DIR/$archive_name"

    if tar -czf "$archive_path" -C "$BACKUP_BASE_DIR" "$BACKUP_TIMESTAMP" 2>/dev/null; then
        local original_size
        local compressed_size
        original_size=$(du -sb "$BACKUP_DIR" | cut -f1)
        compressed_size=$(du -sb "$archive_path" | cut -f1)

        success "Backup compressed: $archive_name"
        info "Compression ratio: $(( (original_size - compressed_size) * 100 / original_size ))%"

        # Remove uncompressed directory
        rm -rf "$BACKUP_DIR"

        # Update backup path for summary
        BACKUP_DIR="$archive_path"
    else
        error "Failed to compress backup"
    fi
}

verify_backup() {
    if [[ "$BACKUP_VERIFICATION" != "true" ]]; then
        return 0
    fi

    progress "Verifying backup integrity..."

    if [[ "$COMPRESSION_ENABLED" == "true" ]]; then
        # Verify compressed archive
        if tar -tzf "$BACKUP_DIR" >/dev/null 2>&1; then
            success "Backup archive verification passed"
        else
            error "Backup archive verification failed"
            return 1
        fi
    else
        # Verify directory structure
        if [[ -f "$BACKUP_DIR/MANIFEST.txt" ]]; then
            success "Backup directory verification passed"
        else
            error "Backup directory verification failed"
            return 1
        fi
    fi
}

cleanup_old_backups() {
    progress "Cleaning up old backups (retention: $BACKUP_RETENTION_DAYS days)..."

    local cleaned_count=0

    # Find and remove old backups
    find "$BACKUP_BASE_DIR" -type f -name "pi-gateway-backup-*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
    find "$BACKUP_BASE_DIR" -type d -name "20*_*" -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

    success "Old backup cleanup completed"
}

# Restore functions
list_available_backups() {
    echo -e "${CYAN}📋 Available Backups:${NC}"
    echo

    local backup_count=0

    # List compressed backups
    if find "$BACKUP_BASE_DIR" -name "pi-gateway-backup-*.tar.gz" -type f >/dev/null 2>&1; then
        while IFS= read -r backup_file; do
            if [[ -f "$backup_file" ]]; then
                local backup_name
                backup_name=$(basename "$backup_file" .tar.gz)
                local backup_date
                backup_date=$(echo "$backup_name" | sed 's/pi-gateway-backup-//' | sed 's/_/ /')
                local backup_size
                backup_size=$(du -h "$backup_file" | cut -f1)
                local backup_age
                backup_age=$(stat -c '%Y' "$backup_file" 2>/dev/null | xargs -I {} date -d '@{}' '+%Y-%m-%d %H:%M:%S' || echo "unknown")

                echo -e "  ${YELLOW}${backup_count}.${NC} $backup_name"
                echo -e "     Date: $backup_date"
                echo -e "     Size: $backup_size"
                echo -e "     Created: $backup_age"
                echo

                ((backup_count++))
            fi
        done < <(find "$BACKUP_BASE_DIR" -name "pi-gateway-backup-*.tar.gz" -type f | sort -r)
    fi

    # List directory backups
    if find "$BACKUP_BASE_DIR" -name "20*_*" -type d >/dev/null 2>&1; then
        while IFS= read -r backup_dir; do
            if [[ -d "$backup_dir" ]]; then
                local backup_name
                backup_name=$(basename "$backup_dir")
                local backup_date
                backup_date=$(echo "$backup_name" | sed 's/_/ /')
                local backup_size
                backup_size=$(du -sh "$backup_dir" | cut -f1)
                local backup_age
                backup_age=$(stat -c '%Y' "$backup_dir" 2>/dev/null | xargs -I {} date -d '@{}' '+%Y-%m-%d %H:%M:%S' || echo "unknown")

                echo -e "  ${YELLOW}${backup_count}.${NC} $backup_name (uncompressed)"
                echo -e "     Date: $backup_date"
                echo -e "     Size: $backup_size"
                echo -e "     Created: $backup_age"
                echo

                ((backup_count++))
            fi
        done < <(find "$BACKUP_BASE_DIR" -name "20*_*" -type d | sort -r)
    fi

    if [[ $backup_count -eq 0 ]]; then
        warning "No backups found in $BACKUP_BASE_DIR"
    fi
}

restore_configuration() {
    local backup_name="$1"

    progress "Restoring configuration from backup: $backup_name"

    # Find backup file or directory
    local backup_path=""
    if [[ -f "$BACKUP_BASE_DIR/pi-gateway-backup-$backup_name.tar.gz" ]]; then
        backup_path="$BACKUP_BASE_DIR/pi-gateway-backup-$backup_name.tar.gz"
    elif [[ -d "$BACKUP_BASE_DIR/$backup_name" ]]; then
        backup_path="$BACKUP_BASE_DIR/$backup_name"
    else
        error "Backup not found: $backup_name"
        return 1
    fi

    # Create temporary restore directory
    local restore_temp_dir="/tmp/pi-gateway-restore-$$"
    mkdir -p "$restore_temp_dir"

    # Extract backup
    if [[ -f "$backup_path" ]]; then
        if tar -xzf "$backup_path" -C "$restore_temp_dir" 2>/dev/null; then
            success "Backup archive extracted"
        else
            error "Failed to extract backup archive"
            rm -rf "$restore_temp_dir"
            return 1
        fi
        backup_path="$restore_temp_dir/$(basename "$backup_name" .tar.gz | sed 's/pi-gateway-backup-//')"
    fi

    # Verify backup structure
    if [[ ! -f "$backup_path/MANIFEST.txt" ]]; then
        error "Invalid backup: missing manifest file"
        rm -rf "$restore_temp_dir"
        return 1
    fi

    progress "Restoring configuration files..."

    local restored_count=0

    # Restore each component
    for source in "${!BACKUP_ITEMS[@]}"; do
        local dest_subdir="${BACKUP_ITEMS[$source]}"
        local backup_item_path="$backup_path/$dest_subdir"

        if [[ -e "$backup_item_path" ]]; then
            # Create backup of current configuration
            local current_backup_path="/tmp/pi-gateway-current-backup-$$"
            mkdir -p "$current_backup_path"

            if [[ -e "$source" ]]; then
                cp -r "$source" "$current_backup_path/" 2>/dev/null || true
            fi

            # Restore from backup
            if cp -r "$backup_item_path" "$source" 2>/dev/null; then
                success "Restored: $source"
                ((restored_count++))
            else
                error "Failed to restore: $source"
            fi
        else
            debug "Backup item not found (may be optional): $dest_subdir"
        fi
    done

    # Clean up
    rm -rf "$restore_temp_dir"

    success "Configuration restore completed ($restored_count items)"

    echo
    warning "Important: Restart Pi Gateway services after restore:"
    echo -e "  ${CYAN}sudo systemctl restart ssh${NC}"
    echo -e "  ${CYAN}sudo systemctl restart wg-quick@wg0${NC}"
    echo -e "  ${CYAN}sudo systemctl restart fail2ban${NC}"
    echo -e "  ${CYAN}sudo systemctl restart ddclient${NC}"
}

# Main operations
perform_backup() {
    print_header
    echo -e "${CYAN}🔒 Creating Pi Gateway Backup${NC}"
    echo

    local start_time
    start_time=$(date +%s)

    if ! check_prerequisites; then
        error "Prerequisites check failed"
        return 1
    fi

    progress "Starting backup process..."

    # Backup configuration items
    for source in "${!BACKUP_ITEMS[@]}"; do
        local dest="${BACKUP_ITEMS[$source]}"
        backup_item "$source" "$dest"
    done

    # Backup service configurations
    for service in "${!SERVICE_CONFIGS[@]}"; do
        local config_path="${SERVICE_CONFIGS[$service]}"
        backup_item "$config_path" "services/$service/"
    done

    # Create manifest and compress
    create_backup_manifest
    compress_backup
    verify_backup
    cleanup_old_backups

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    print_backup_summary "$BACKUP_DIR" "$duration"

    if [[ $ERRORS_COUNT -eq 0 ]]; then
        success "Backup completed successfully!"
        return 0
    else
        warning "Backup completed with $ERRORS_COUNT errors"
        return 1
    fi
}

perform_restore() {
    print_header
    echo -e "${CYAN}🔄 Restoring Pi Gateway Configuration${NC}"
    echo

    if [[ -z "$RESTORE_NAME" ]]; then
        list_available_backups
        echo
        read -r -p "Enter backup name to restore: " RESTORE_NAME
    fi

    if [[ -z "$RESTORE_NAME" ]]; then
        error "No backup name specified"
        return 1
    fi

    progress "Starting restore process..."
    restore_configuration "$RESTORE_NAME"
}

perform_list() {
    print_header
    list_available_backups
}

# Help and usage
show_help() {
    echo "Pi Gateway Backup & Restore Tool"
    echo
    echo "Usage: $SCRIPT_NAME OPERATION [OPTIONS]"
    echo
    echo "Operations:"
    echo "  backup                    Create a new backup"
    echo "  restore [backup-name]     Restore from backup"
    echo "  list                      List available backups"
    echo
    echo "Options:"
    echo "  -h, --help               Show this help message"
    echo "  -v, --verbose            Enable verbose output"
    echo "  -d, --dry-run            Show what would be backed up (backup only)"
    echo "  --include-logs           Include log files in backup"
    echo "  --no-compression         Disable backup compression"
    echo "  --no-verification        Skip backup verification"
    echo
    echo "Examples:"
    echo "  $SCRIPT_NAME backup                    # Create backup"
    echo "  $SCRIPT_NAME restore 20240916_143022   # Restore specific backup"
    echo "  $SCRIPT_NAME list                      # Show available backups"
    echo
}

# Argument parsing
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            backup)
                OPERATION="backup"
                shift
                ;;
            restore)
                OPERATION="restore"
                if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                    RESTORE_NAME="$2"
                    shift
                fi
                shift
                ;;
            list)
                OPERATION="list"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --include-logs)
                INCLUDE_LOGS=true
                shift
                ;;
            --no-compression)
                COMPRESSION_ENABLED=false
                shift
                ;;
            --no-verification)
                BACKUP_VERIFICATION=false
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main execution
main() {
    log "INFO" "Starting Pi Gateway backup/restore tool"

    # Parse arguments
    parse_arguments "$@"

    # Validate operation
    if [[ -z "$OPERATION" ]]; then
        error "No operation specified"
        show_help
        exit 1
    fi

    # Create backup base directory
    mkdir -p "$BACKUP_BASE_DIR"

    # Execute operation
    case "$OPERATION" in
        "backup")
            perform_backup
            ;;
        "restore")
            perform_restore
            ;;
        "list")
            perform_list
            ;;
        *)
            error "Invalid operation: $OPERATION"
            exit 1
            ;;
    esac
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi