#!/bin/bash
# ============================================================================
# FILE:        utils.sh
# PURPOSE:     Shared utility functions for the file cleanup utility
# DESCRIPTION: Helper functions used across all phases of the cleanup process.
#              Handles logging, file operations, and common validation tasks.
#
# USAGE:       Source this file in other scripts:
#              source "$(dirname "$0")/utils.sh"
#
# NOTE:        Requires bash 4+. macOS ships 3.2; install via: brew install bash
# ============================================================================

# Require bash 4+ for associative arrays
if ((BASH_VERSINFO[0] < 4)); then
    echo "Error: Bash 4+ required. macOS ships 3.2; install via: brew install bash" >&2
    exit 1
fi

set -u          # Exit on unset variable reference
set -o pipefail # Propagate pipe failures

# ============================================================================
# SECTION: COLOR DEFINITIONS
# ============================================================================

# Check if terminal supports colors (not redirected to file)
if [[ -t 1 ]]
then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# ============================================================================
# SECTION: CONFIGURATION DEFAULTS
# ============================================================================

# Large file threshold in bytes (default: 100MB)
LARGE_FILE_THRESHOLD="${CLEANUP_LARGE_FILE_THRESHOLD:-104857600}"

# Dry run mode (default: enabled for safety)
DRY_RUN="${CLEANUP_DRY_RUN:-1}"

# Create backup before making changes (default: enabled)
CREATE_BACKUP="${CLEANUP_CREATE_BACKUP:-1}"

# Output directory for manifest, scripts, and backups
OUTPUT_DIR="${CLEANUP_OUTPUT_DIR:-.}"

# Shared find exclusions for macOS system files and common junk
FIND_EXCLUDES=(
    ! -name '.DS_Store'
    ! -name '.localized'
    ! -name '._*'
    ! -path '*/.git/*'
    ! -path '*/venv/*'
    ! -path '*/__pycache__/*'
)

# ============================================================================
# SECTION: LOGGING FUNCTIONS
# ============================================================================

# Print an informational message
log_info()
{
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Print a success message
log_success()
{
    echo -e "${GREEN}[OK]${NC} $1"
}

# Print a warning message
log_warn()
{
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Print an error message
log_error()
{
    echo -e "${RED}[ERROR]${NC} $1"
}

# Print a section header
log_header()
{
    echo ""
    echo -e "${BOLD}=============================================="
    echo -e "$1"
    echo -e "==============================================${NC}"
    echo ""
}

# Append a timestamped message to a log file
# Args: $1 = log file path, $2 = message
log_to_file()
{
    local log_file="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $message" >> "$log_file"
}

# ============================================================================
# SECTION: VALIDATION FUNCTIONS
# ============================================================================

# Check if a path exists and is a directory
# Returns: 0 if valid, 1 if not
validate_directory()
{
    local dir_path="$1"

    if [[ ! -e "$dir_path" ]]
    then
        log_error "Path does not exist: $dir_path"
        return 1
    fi

    if [[ ! -d "$dir_path" ]]
    then
        log_error "Path is not a directory: $dir_path"
        return 1
    fi

    return 0
}

# ----------------------------------------------------------------------------
# FUNCTION: validate_not_system_dir
# PURPOSE:  Prevent accidental operations on critical system directories
# ARGS:     $1 = path to check
# RETURNS:  0 if safe, 1 if system directory
# ----------------------------------------------------------------------------
validate_not_system_dir()
{
    local dir_path="$1"

    local abs_path
    abs_path=$(cd "$dir_path" 2>/dev/null && pwd)

    # Directories where both the dir itself AND its subdirs are off-limits
    local protected_trees=(
        "/System"
        "/Library"
        "/usr"
        "/bin"
        "/sbin"
        "/Applications"
        "$HOME/Library"
    )

    # Directories where only the exact path is off-limits (not subdirs).
    # /var and /private are excluded from tree-match because macOS temp
    # dirs live under /private/var/folders/ and must remain accessible.
    local protected_exact=(
        "/"
        "/var"
        "/private"
    )

    for protected in "${protected_trees[@]}"
    do
        if [[ "$abs_path" == "$protected" || "$abs_path" == "$protected/"* ]]
        then
            log_error "Cannot operate on system directory: $abs_path"
            return 1
        fi
    done

    for protected in "${protected_exact[@]}"
    do
        if [[ "$abs_path" == "$protected" ]]
        then
            log_error "Cannot operate on system directory: $abs_path"
            return 1
        fi
    done

    return 0
}

# ============================================================================
# SECTION: FILE INFORMATION FUNCTIONS
# ============================================================================

# Get the size of a file in bytes (macOS stat syntax)
get_file_size()
{
    local file_path="$1"
    stat -f "%z" "$file_path" 2>/dev/null || echo "0"
}

# ----------------------------------------------------------------------------
# FUNCTION: get_file_hash
# PURPOSE:  Calculate SHA-256 checksum of a file (for duplicate detection)
# ARGS:     $1 = file path
# OUTPUT:   Prints SHA-256 hash to stdout (64 character hex string)
# ----------------------------------------------------------------------------
get_file_hash()
{
    local file_path="$1"
    shasum -a 256 "$file_path" 2>/dev/null | cut -d' ' -f1
}

# Convert bytes to human-readable format using pure integer arithmetic
format_bytes()
{
    local bytes=$1
    if ((bytes >= 1073741824)); then echo "$((bytes / 1073741824)) GB"
    elif ((bytes >= 1048576)); then echo "$((bytes / 1048576)) MB"
    elif ((bytes >= 1024)); then echo "$((bytes / 1024)) KB"
    else echo "${bytes} bytes"
    fi
}

# ============================================================================
# SECTION: FILE OPERATION FUNCTIONS
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: safe_move
# PURPOSE:  Move a file with safety checks and logging.
#           Creates destination directory if needed. Respects DRY_RUN mode.
# ARGS:     $1 = source path, $2 = destination path, $3 = log file (optional)
# RETURNS:  0 on success, 1 on failure
# ----------------------------------------------------------------------------
safe_move()
{
    local source_path="$1"
    local dest_path="$2"
    local log_file="${3:-}"

    local dest_dir
    dest_dir=$(dirname "$dest_path")

    if [[ ! -e "$source_path" ]]
    then
        log_warn "Source does not exist: $source_path"
        return 1
    fi

    if [[ -e "$dest_path" ]]
    then
        log_warn "Destination exists, skipping: $dest_path"
        [[ -n "$log_file" ]] && log_to_file "$log_file" "SKIPPED | $source_path | $dest_path | Destination exists"
        return 1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]
    then
        echo "[DRY RUN] Would move: $(basename "$source_path")"
        echo "          From: $source_path"
        echo "          To:   $dest_path"
        return 0
    fi

    mkdir -p "$dest_dir"

    if mv "$source_path" "$dest_path"
    then
        log_success "Moved: $(basename "$source_path")"
        [[ -n "$log_file" ]] && log_to_file "$log_file" "MOVED | $source_path | $dest_path"
        return 0
    else
        log_error "Failed to move: $source_path"
        [[ -n "$log_file" ]] && log_to_file "$log_file" "FAILED | $source_path | $dest_path"
        return 1
    fi
}

# Move an entire directory with safety checks
# Args: $1 = source dir, $2 = dest dir, $3 = log file (optional)
safe_move_dir()
{
    local source_path="$1"
    local dest_path="$2"
    local log_file="${3:-}"

    if [[ ! -d "$source_path" ]]
    then
        log_warn "Source directory does not exist: $source_path"
        return 1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]
    then
        echo "[DRY RUN] Would move directory: $(basename "$source_path")"
        echo "          From: $source_path"
        echo "          To:   $dest_path"
        return 0
    fi

    mkdir -p "$(dirname "$dest_path")"

    if mv "$source_path" "$dest_path"
    then
        log_success "Moved directory: $(basename "$source_path")"
        [[ -n "$log_file" ]] && log_to_file "$log_file" "MOVED_DIR | $source_path | $dest_path"
        return 0
    else
        log_error "Failed to move directory: $source_path"
        [[ -n "$log_file" ]] && log_to_file "$log_file" "FAILED_DIR | $source_path | $dest_path"
        return 1
    fi
}

# ============================================================================
# SECTION: CLEANUP FUNCTIONS
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: remove_empty_dirs
# PURPOSE:  Recursively remove empty directories. Uses find -depth for
#           single-pass bottom-up removal. Respects DRY_RUN mode.
# ARGS:     $1 = root directory to clean
# ----------------------------------------------------------------------------
remove_empty_dirs()
{
    local root_dir="$1"

    if [[ "$DRY_RUN" -eq 1 ]]
    then
        echo "[DRY RUN] Would clean up empty directories in: $root_dir"
        find "$root_dir" -type d -empty 2>/dev/null | while read -r dir
        do
            echo "          Would remove: $dir"
        done
        return 0
    fi

    find "$root_dir" -depth -type d -empty -delete 2>/dev/null
}

# ============================================================================
# SECTION: BACKUP FUNCTIONS
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: create_backup
# PURPOSE:  Create a tar.gz backup of specified directories.
#           Excludes .DS_Store and other system files. Respects DRY_RUN mode.
# ARGS:     $1 = backup filename (without extension), $2... = directories
# OUTPUT:   Prints backup file path to stdout on success
# ----------------------------------------------------------------------------
create_backup()
{
    local backup_name="$1"
    shift
    local dirs=("$@")

    local backup_file="${OUTPUT_DIR}/${backup_name}.tar.gz"

    if [[ "$DRY_RUN" -eq 1 ]]
    then
        echo "[DRY RUN] Would create backup: $backup_file"
        echo "          Including directories: ${dirs[*]}"
        return 0
    fi

    log_info "Creating backup: $backup_file"

    if tar -czf "$backup_file" \
        --exclude='.DS_Store' \
        --exclude='.localized' \
        --exclude='._*' \
        "${dirs[@]}" 2>/dev/null
    then
        local backup_size
        backup_size=$(format_bytes "$(get_file_size "$backup_file")")
        log_success "Backup created: $backup_file ($backup_size)"
        echo "$backup_file"
        return 0
    else
        log_error "Failed to create backup"
        return 1
    fi
}

# ============================================================================
# SECTION: ARRAY/LIST UTILITIES
# ============================================================================

# Check if an array contains a specific value
# Args: $1 = value to search for, $2... = array elements
# Returns: 0 if found, 1 if not
array_contains()
{
    local search="$1"
    shift
    local element
    for element in "$@"
    do
        if [[ "$element" == "$search" ]]
        then
            return 0
        fi
    done
    return 1
}

# ============================================================================
# SECTION: DATE/TIME UTILITIES
# ============================================================================

# Get current timestamp in filename-safe format (e.g., "2026-01-16_14-30-45")
get_timestamp()
{
    date '+%Y-%m-%d_%H-%M-%S'
}

# Get current date in ISO format (e.g., "2026-01-16")
get_date()
{
    date '+%Y-%m-%d'
}

# ============================================================================
# END OF UTILS.SH
# ============================================================================
