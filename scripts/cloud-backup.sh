#!/bin/bash
#
# Pi Gateway Cloud Backup Integration
# Secure backup to cloud storage providers
#

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_DIR="$PROJECT_ROOT/config"
readonly LOG_DIR="$PROJECT_ROOT/logs"
readonly STATE_DIR="$PROJECT_ROOT/state"
readonly BACKUP_CONFIG="$CONFIG_DIR/cloud-backup.conf"
readonly CLOUD_STATE="$STATE_DIR/cloud-backup.json"
readonly CLOUD_LOG="$LOG_DIR/cloud-backup.log"

# Backup directories
readonly LOCAL_BACKUP_DIR="$PROJECT_ROOT/backups"
readonly TEMP_DIR="/tmp/pi-gateway-cloud-backup"

# Logging functions
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$CLOUD_LOG"; }
success() { echo -e "  ${GREEN}✓${NC} $1" | tee -a "$CLOUD_LOG"; }
error() { echo -e "  ${RED}✗${NC} $1" | tee -a "$CLOUD_LOG"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $1" | tee -a "$CLOUD_LOG"; }
info() { echo -e "  ${BLUE}ℹ${NC} $1" | tee -a "$CLOUD_LOG"; }

# Initialize cloud backup
initialize_cloud_backup() {
    log "Initializing cloud backup system..."

    # Create required directories
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$STATE_DIR" "$LOCAL_BACKUP_DIR" "$TEMP_DIR"

    # Create default configuration if it doesn't exist
    if [[ ! -f "$BACKUP_CONFIG" ]]; then
        create_default_config
    fi

    # Initialize state file
    if [[ ! -f "$CLOUD_STATE" ]]; then
        echo '{"last_backup": "", "provider": "", "backup_history": []}' > "$CLOUD_STATE"
    fi

    success "Cloud backup system initialized"
}

# Create default cloud backup configuration
create_default_config() {
    cat > "$BACKUP_CONFIG" << 'EOF'
# Pi Gateway Cloud Backup Configuration

# Cloud Provider (s3, b2, gcs, azure)
CLOUD_PROVIDER="s3"

# Backup Settings
ENABLE_ENCRYPTION=true
COMPRESSION_LEVEL=6
RETENTION_DAYS=30
BACKUP_SCHEDULE="daily"

# AWS S3 Configuration
AWS_REGION="us-east-1"
AWS_BUCKET=""
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_STORAGE_CLASS="STANDARD_IA"

# Backblaze B2 Configuration
B2_BUCKET=""
B2_KEY_ID=""
B2_APPLICATION_KEY=""

# Google Cloud Storage Configuration
GCS_BUCKET=""
GCS_PROJECT_ID=""
GCS_SERVICE_ACCOUNT_KEY=""

# Azure Blob Storage Configuration
AZURE_ACCOUNT_NAME=""
AZURE_ACCOUNT_KEY=""
AZURE_CONTAINER=""

# Encryption Settings
ENCRYPTION_KEY_FILE="$CONFIG_DIR/backup-encryption.key"
ENCRYPTION_METHOD="age"  # age or gpg

# Notification Settings
ENABLE_NOTIFICATIONS=true
NOTIFICATION_EMAIL=""
WEBHOOK_URL=""
EOF

    success "Default cloud backup configuration created"
    warning "Please configure your cloud provider settings in: $BACKUP_CONFIG"
}

# Load configuration
load_config() {
    if [[ -f "$BACKUP_CONFIG" ]]; then
        # shellcheck source=/dev/null
        source "$BACKUP_CONFIG"
    else
        error "Cloud backup configuration not found: $BACKUP_CONFIG"
        return 1
    fi
}

# Install cloud provider tools
install_cloud_tools() {
    local provider="${1:-$CLOUD_PROVIDER}"

    info "Installing tools for cloud provider: $provider"

    case $provider in
        s3)
            install_aws_cli
            ;;
        b2)
            install_b2_cli
            ;;
        gcs)
            install_gcs_cli
            ;;
        azure)
            install_azure_cli
            ;;
        *)
            error "Unsupported cloud provider: $provider"
            return 1
            ;;
    esac
}

# Install AWS CLI
install_aws_cli() {
    if command -v aws >/dev/null 2>&1; then
        info "AWS CLI already installed"
        return
    fi

    info "Installing AWS CLI..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would install AWS CLI"
        return
    fi

    # Install AWS CLI v2
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o awscliv2.zip
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf aws/ awscliv2.zip

    success "AWS CLI installed"
}

# Install Backblaze B2 CLI
install_b2_cli() {
    if command -v b2 >/dev/null 2>&1; then
        info "B2 CLI already installed"
        return
    fi

    info "Installing Backblaze B2 CLI..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would install B2 CLI"
        return
    fi

    pip3 install --user b2

    success "B2 CLI installed"
}

# Install Google Cloud CLI
install_gcs_cli() {
    if command -v gsutil >/dev/null 2>&1; then
        info "Google Cloud CLI already installed"
        return
    fi

    info "Installing Google Cloud CLI..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would install Google Cloud CLI"
        return
    fi

    curl https://sdk.cloud.google.com | bash
    exec -l $SHELL

    success "Google Cloud CLI installed"
}

# Install Azure CLI
install_azure_cli() {
    if command -v az >/dev/null 2>&1; then
        info "Azure CLI already installed"
        return
    fi

    info "Installing Azure CLI..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would install Azure CLI"
        return
    fi

    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

    success "Azure CLI installed"
}

# Setup encryption
setup_encryption() {
    local method="${ENCRYPTION_METHOD:-age}"

    info "Setting up encryption with method: $method"

    case $method in
        age)
            setup_age_encryption
            ;;
        gpg)
            setup_gpg_encryption
            ;;
        *)
            error "Unsupported encryption method: $method"
            return 1
            ;;
    esac
}

# Setup Age encryption
setup_age_encryption() {
    if [[ ! -f "$ENCRYPTION_KEY_FILE" ]]; then
        info "Generating Age encryption key..."

        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            info "[DRY RUN] Would generate Age encryption key"
            return
        fi

        # Install age if not present
        if ! command -v age >/dev/null 2>&1; then
            apt-get update
            apt-get install -y age
        fi

        # Generate key pair
        age-keygen -o "$ENCRYPTION_KEY_FILE"
        chmod 600 "$ENCRYPTION_KEY_FILE"

        success "Age encryption key generated: $ENCRYPTION_KEY_FILE"
        warning "IMPORTANT: Back up this encryption key securely!"
    else
        info "Age encryption key already exists"
    fi
}

# Setup GPG encryption
setup_gpg_encryption() {
    info "Setting up GPG encryption..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would setup GPG encryption"
        return
    fi

    # Check if GPG key exists
    if ! gpg --list-secret-keys | grep -q "pi-gateway"; then
        # Generate GPG key non-interactively
        cat > /tmp/gpg-batch << EOF
%echo Generating Pi Gateway backup key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: Pi Gateway Backup
Name-Email: backup@pi-gateway.local
Expire-Date: 2y
Passphrase: $(openssl rand -base64 32)
%commit
%echo done
EOF

        gpg --batch --generate-key /tmp/gpg-batch
        rm /tmp/gpg-batch

        success "GPG key generated for backup encryption"
    else
        info "GPG key already exists"
    fi
}

# Create encrypted backup
create_encrypted_backup() {
    local backup_file="$1"
    local encrypted_file="$2"

    info "Encrypting backup: $(basename "$backup_file")"

    case "${ENCRYPTION_METHOD:-age}" in
        age)
            if [[ -f "$ENCRYPTION_KEY_FILE" ]]; then
                age -r "$(grep -o 'age1[a-z0-9]*' "$ENCRYPTION_KEY_FILE")" -o "$encrypted_file" "$backup_file"
            else
                error "Age encryption key not found: $ENCRYPTION_KEY_FILE"
                return 1
            fi
            ;;
        gpg)
            gpg --trust-model always --encrypt -r "pi-gateway" --output "$encrypted_file" "$backup_file"
            ;;
    esac

    success "Backup encrypted: $(basename "$encrypted_file")"
}

# Upload to cloud provider
upload_to_cloud() {
    local local_file="$1"
    local remote_path="$2"
    local provider="${CLOUD_PROVIDER:-s3}"

    info "Uploading to $provider: $(basename "$local_file")"

    case $provider in
        s3)
            upload_to_s3 "$local_file" "$remote_path"
            ;;
        b2)
            upload_to_b2 "$local_file" "$remote_path"
            ;;
        gcs)
            upload_to_gcs "$local_file" "$remote_path"
            ;;
        azure)
            upload_to_azure "$local_file" "$remote_path"
            ;;
        *)
            error "Unsupported cloud provider: $provider"
            return 1
            ;;
    esac
}

# Upload to AWS S3
upload_to_s3() {
    local local_file="$1"
    local remote_path="$2"

    # Configure AWS credentials
    export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
    export AWS_DEFAULT_REGION="$AWS_REGION"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would upload to S3: s3://$AWS_BUCKET/$remote_path"
        return
    fi

    aws s3 cp "$local_file" "s3://$AWS_BUCKET/$remote_path" \
        --storage-class "$AWS_STORAGE_CLASS" \
        --server-side-encryption AES256

    success "Uploaded to S3: s3://$AWS_BUCKET/$remote_path"
}

# Upload to Backblaze B2
upload_to_b2() {
    local local_file="$1"
    local remote_path="$2"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would upload to B2: $B2_BUCKET/$remote_path"
        return
    fi

    # Authorize B2 account
    b2 authorize-account "$B2_KEY_ID" "$B2_APPLICATION_KEY"

    # Upload file
    b2 upload-file "$B2_BUCKET" "$local_file" "$remote_path"

    success "Uploaded to B2: $B2_BUCKET/$remote_path"
}

# Cleanup old backups
cleanup_old_backups() {
    local provider="${CLOUD_PROVIDER:-s3}"
    local retention_days="${RETENTION_DAYS:-30}"

    info "Cleaning up backups older than $retention_days days"

    case $provider in
        s3)
            cleanup_s3_backups "$retention_days"
            ;;
        b2)
            cleanup_b2_backups "$retention_days"
            ;;
        *)
            warning "Cleanup not implemented for provider: $provider"
            ;;
    esac
}

# Cleanup S3 backups
cleanup_s3_backups() {
    local retention_days="$1"
    local cutoff_date
    cutoff_date=$(date -d "$retention_days days ago" '+%Y-%m-%d')

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would cleanup S3 backups older than $cutoff_date"
        return
    fi

    aws s3 ls "s3://$AWS_BUCKET/pi-gateway-backups/" --recursive | \
    while read -r line; do
        local file_date
        file_date=$(echo "$line" | awk '{print $1}')
        local file_path
        file_path=$(echo "$line" | awk '{print $4}')

        if [[ "$file_date" < "$cutoff_date" ]]; then
            info "Deleting old backup: $file_path"
            aws s3 rm "s3://$AWS_BUCKET/$file_path"
        fi
    done

    success "Old backups cleaned up"
}

# Send notification
send_notification() {
    local status="$1"
    local message="$2"

    if [[ "${ENABLE_NOTIFICATIONS:-false}" != "true" ]]; then
        return
    fi

    # Email notification
    if [[ -n "${NOTIFICATION_EMAIL:-}" ]] && command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "Pi Gateway Backup $status" "$NOTIFICATION_EMAIL"
    fi

    # Webhook notification
    if [[ -n "${WEBHOOK_URL:-}" ]] && command -v curl >/dev/null 2>&1; then
        curl -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"status\": \"$status\", \"message\": \"$message\"}"
    fi
}

# Main backup function
run_cloud_backup() {
    local backup_type="${1:-full}"

    log "Starting cloud backup: $backup_type"

    initialize_cloud_backup
    load_config

    # Install required tools
    install_cloud_tools

    # Setup encryption if enabled
    if [[ "${ENABLE_ENCRYPTION:-true}" == "true" ]]; then
        setup_encryption
    fi

    # Create local backup first
    local backup_name="pi-gateway-backup-$(date +%Y%m%d-%H%M%S)"
    local local_backup="$LOCAL_BACKUP_DIR/$backup_name.tar.gz"

    info "Creating local backup..."
    if ! "$SCRIPT_DIR/backup-config.sh" create "$backup_name"; then
        error "Failed to create local backup"
        send_notification "FAILED" "Local backup creation failed"
        return 1
    fi

    # Encrypt backup if enabled
    local upload_file="$local_backup"
    if [[ "${ENABLE_ENCRYPTION:-true}" == "true" ]]; then
        local encrypted_backup="$LOCAL_BACKUP_DIR/$backup_name.tar.gz.enc"
        if ! create_encrypted_backup "$local_backup" "$encrypted_backup"; then
            error "Failed to encrypt backup"
            send_notification "FAILED" "Backup encryption failed"
            return 1
        fi
        upload_file="$encrypted_backup"
    fi

    # Upload to cloud
    local remote_path="pi-gateway-backups/$(basename "$upload_file")"
    if ! upload_to_cloud "$upload_file" "$remote_path"; then
        error "Failed to upload backup to cloud"
        send_notification "FAILED" "Cloud upload failed"
        return 1
    fi

    # Cleanup old backups
    cleanup_old_backups

    # Update state
    local timestamp
    timestamp=$(date -Iseconds)
    echo "{\"last_backup\": \"$timestamp\", \"provider\": \"$CLOUD_PROVIDER\", \"file\": \"$remote_path\"}" > "$CLOUD_STATE"

    # Cleanup temporary files
    rm -f "$upload_file"
    if [[ "$upload_file" != "$local_backup" ]]; then
        rm -f "$local_backup"
    fi
    rm -rf "$TEMP_DIR"

    success "Cloud backup completed successfully"
    send_notification "SUCCESS" "Cloud backup completed: $remote_path"
    log "Cloud backup completed: $remote_path"
}

# Show backup status
show_backup_status() {
    echo -e "${CYAN}☁️  Cloud Backup Status${NC}"
    echo

    if [[ ! -f "$CLOUD_STATE" ]]; then
        warning "Cloud backup not configured"
        return 1
    fi

    local last_backup provider
    if command -v jq >/dev/null 2>&1; then
        last_backup=$(jq -r '.last_backup' "$CLOUD_STATE")
        provider=$(jq -r '.provider' "$CLOUD_STATE")
    else
        last_backup="unknown"
        provider="unknown"
    fi

    info "Provider: $provider"
    info "Last backup: $last_backup"

    # Check provider status
    case $provider in
        s3)
            if command -v aws >/dev/null 2>&1; then
                success "AWS CLI available"
            else
                warning "AWS CLI not installed"
            fi
            ;;
        b2)
            if command -v b2 >/dev/null 2>&1; then
                success "B2 CLI available"
            else
                warning "B2 CLI not installed"
            fi
            ;;
    esac
}

# Show help
show_help() {
    echo "Pi Gateway Cloud Backup System"
    echo
    echo "Usage: $(basename "$0") <command> [options]"
    echo
    echo "Commands:"
    echo "  setup [provider]     Setup cloud backup (s3, b2, gcs, azure)"
    echo "  backup [type]        Run cloud backup (full, incremental)"
    echo "  status               Show backup status"
    echo "  test                 Test cloud connectivity"
    echo "  cleanup              Clean old backups"
    echo "  help                 Show this help message"
    echo
    echo "Options:"
    echo "  --dry-run           Show what would be done without making changes"
    echo "  --encrypt           Force encryption (overrides config)"
    echo "  --no-encrypt        Skip encryption (overrides config)"
    echo
    echo "Examples:"
    echo "  $(basename "$0") setup s3"
    echo "  $(basename "$0") backup full"
    echo "  $(basename "$0") status"
    echo
}

# Main execution
main() {
    local command="${1:-}"

    # Handle global options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                export DRY_RUN=true
                shift
                ;;
            --encrypt)
                export ENABLE_ENCRYPTION=true
                shift
                ;;
            --no-encrypt)
                export ENABLE_ENCRYPTION=false
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    case $command in
        setup)
            local provider="${2:-s3}"
            initialize_cloud_backup
            install_cloud_tools "$provider"
            setup_encryption
            ;;
        backup)
            local backup_type="${2:-full}"
            run_cloud_backup "$backup_type"
            ;;
        status)
            show_backup_status
            ;;
        test)
            load_config
            info "Testing cloud connectivity..."
            # Add connectivity tests for each provider
            ;;
        cleanup)
            load_config
            cleanup_old_backups
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [[ -n "$command" ]]; then
                error "Unknown command: $command"
            else
                error "No command specified"
            fi
            echo "Use '$(basename "$0") help' for available commands"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
