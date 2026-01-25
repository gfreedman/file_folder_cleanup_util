#!/bin/bash
# ============================================================================
# FILE:        utils.sh
# PURPOSE:     Shared utility functions for the file cleanup utility
# DESCRIPTION: This file contains helper functions used across all phases
#              of the cleanup process. It handles logging, file operations,
#              and common validation tasks.
#
# USAGE:       Source this file in other scripts:
#              source "$(dirname "$0")/utils.sh"
#
# NOTE:        This script is designed for macOS and uses BSD versions of
#              common utilities (find, stat, md5, etc.)
# ============================================================================

set -u  # Exit on unset variable reference

# ============================================================================
# SECTION: COLOR DEFINITIONS
# PURPOSE: Define ANSI color codes for terminal output
# NOTE:    These make the output easier to read by highlighting different
#          types of messages (errors in red, success in green, etc.)
# ============================================================================

# Check if terminal supports colors (not redirected to file)
if [[ -t 1 ]]
then
    RED='\033[0;31m'      # Error messages
    GREEN='\033[0;32m'    # Success messages
    YELLOW='\033[1;33m'   # Warning messages
    BLUE='\033[0;34m'     # Info messages
    CYAN='\033[0;36m'     # Highlight/emphasis
    BOLD='\033[1m'        # Bold text
    NC='\033[0m'          # No Color (reset)
else
    # No colors if output is being redirected to a file
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
# PURPOSE: Set default values that can be overridden by environment variables
# ============================================================================

# Large file threshold in bytes (default: 100MB = 104857600 bytes)
# Files larger than this will be flagged during analysis
LARGE_FILE_THRESHOLD="${CLEANUP_LARGE_FILE_THRESHOLD:-104857600}"

# Dry run mode (default: enabled for safety)
# When set to 1, no actual file operations are performed
DRY_RUN="${CLEANUP_DRY_RUN:-1}"

# Create backup before making changes (default: enabled)
CREATE_BACKUP="${CLEANUP_CREATE_BACKUP:-1}"

# Output directory for manifest, scripts, and backups
OUTPUT_DIR="${CLEANUP_OUTPUT_DIR:-.}"

# ============================================================================
# SECTION: LOGGING FUNCTIONS
# PURPOSE: Provide consistent, formatted output across all scripts
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: log_info
# PURPOSE:  Print an informational message (neutral, for general updates)
# ARGS:     $1 = message to display
# EXAMPLE:  log_info "Processing folder: Documents"
# ----------------------------------------------------------------------------
log_info()
{
    echo -e "${BLUE}[INFO]${NC} $1"
}

# ----------------------------------------------------------------------------
# FUNCTION: log_success
# PURPOSE:  Print a success message (green, for completed operations)
# ARGS:     $1 = message to display
# EXAMPLE:  log_success "File moved successfully"
# ----------------------------------------------------------------------------
log_success()
{
    echo -e "${GREEN}[OK]${NC} $1"
}

# ----------------------------------------------------------------------------
# FUNCTION: log_warn
# PURPOSE:  Print a warning message (yellow, for non-fatal issues)
# ARGS:     $1 = message to display
# EXAMPLE:  log_warn "Duplicate file found, will keep newer version"
# ----------------------------------------------------------------------------
log_warn()
{
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# ----------------------------------------------------------------------------
# FUNCTION: log_error
# PURPOSE:  Print an error message (red, for failures)
# ARGS:     $1 = message to display
# EXAMPLE:  log_error "Source file does not exist"
# ----------------------------------------------------------------------------
log_error()
{
    echo -e "${RED}[ERROR]${NC} $1"
}

# ----------------------------------------------------------------------------
# FUNCTION: log_header
# PURPOSE:  Print a section header (bold, for major phases)
# ARGS:     $1 = header text
# EXAMPLE:  log_header "Phase 1: Analysis"
# ----------------------------------------------------------------------------
log_header()
{
    echo ""
    echo -e "${BOLD}=============================================="
    echo -e "$1"
    echo -e "==============================================${NC}"
    echo ""
}

# ----------------------------------------------------------------------------
# FUNCTION: log_to_file
# PURPOSE:  Append a message to the manifest/log file
# ARGS:     $1 = log file path, $2 = message
# EXAMPLE:  log_to_file "$MANIFEST_FILE" "MOVED | /old/path | /new/path"
# ----------------------------------------------------------------------------
log_to_file()
{
    local log_file="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $message" >> "$log_file"
}

# ============================================================================
# SECTION: VALIDATION FUNCTIONS
# PURPOSE: Check preconditions before performing operations
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: validate_directory
# PURPOSE:  Check if a path exists and is a directory
# ARGS:     $1 = path to check
# RETURNS:  0 if valid directory, 1 if not
# EXAMPLE:  if validate_directory "$source_dir"; then ...
# ----------------------------------------------------------------------------
validate_directory()
{
    local dir_path="$1"

    # Check if path exists
    if [[ ! -e "$dir_path" ]]
    then
        log_error "Path does not exist: $dir_path"
        return 1
    fi

    # Check if it's a directory (not a file)
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
# EXAMPLE:  if validate_not_system_dir "$target"; then ...
# ----------------------------------------------------------------------------
validate_not_system_dir()
{
    local dir_path="$1"

    # Resolve to absolute path
    local abs_path
    abs_path=$(cd "$dir_path" 2>/dev/null && pwd)

    # List of protected directories that should never be modified
    local protected_dirs=(
        "/"
        "/System"
        "/Library"
        "/usr"
        "/bin"
        "/sbin"
        "/var"
        "/private"
        "/Applications"
        "$HOME/Library"
    )

    # Check if the path matches any protected directory
    for protected in "${protected_dirs[@]}"
    do
        if [[ "$abs_path" == "$protected" || "$abs_path" == "$protected/"* ]]
        then
            log_error "Cannot operate on system directory: $abs_path"
            return 1
        fi
    done

    return 0
}

# ============================================================================
# SECTION: FILE INFORMATION FUNCTIONS
# PURPOSE: Extract metadata about files (size, checksum, etc.)
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: get_file_size
# PURPOSE:  Get the size of a file in bytes
# ARGS:     $1 = file path
# OUTPUT:   Prints size in bytes to stdout
# NOTE:     Uses macOS 'stat' syntax (different from Linux)
# EXAMPLE:  size=$(get_file_size "/path/to/file")
# ----------------------------------------------------------------------------
get_file_size()
{
    local file_path="$1"

    # macOS stat uses -f "%z" for size (Linux uses -c "%s")
    stat -f "%z" "$file_path" 2>/dev/null || echo "0"
}

# ----------------------------------------------------------------------------
# FUNCTION: get_file_md5
# PURPOSE:  Calculate MD5 checksum of a file (for duplicate detection)
# ARGS:     $1 = file path
# OUTPUT:   Prints MD5 hash to stdout (32 character hex string)
# NOTE:     Uses macOS 'md5' command (Linux uses 'md5sum')
# EXAMPLE:  hash=$(get_file_md5 "/path/to/file")
# ----------------------------------------------------------------------------
get_file_md5()
{
    local file_path="$1"

    # macOS md5 outputs: MD5 (filename) = hash
    # We extract just the hash part using awk
    md5 -q "$file_path" 2>/dev/null || echo ""
}

# ----------------------------------------------------------------------------
# FUNCTION: format_bytes
# PURPOSE:  Convert bytes to human-readable format (KB, MB, GB)
# ARGS:     $1 = size in bytes
# OUTPUT:   Prints formatted size string
# EXAMPLE:  format_bytes 1048576  # outputs "1.0 MB"
# ----------------------------------------------------------------------------
format_bytes()
{
    local bytes="$1"

    # Define thresholds
    local kb=1024
    local mb=$((1024 * 1024))
    local gb=$((1024 * 1024 * 1024))

    # Choose appropriate unit
    if [[ $bytes -ge $gb ]]
    then
        # Use awk for floating point division (bash only does integers)
        awk "BEGIN {printf \"%.1f GB\", $bytes / $gb}"
    elif [[ $bytes -ge $mb ]]
    then
        awk "BEGIN {printf \"%.1f MB\", $bytes / $mb}"
    elif [[ $bytes -ge $kb ]]
    then
        awk "BEGIN {printf \"%.1f KB\", $bytes / $kb}"
    else
        echo "${bytes} bytes"
    fi
}

# ============================================================================
# SECTION: FILE OPERATION FUNCTIONS
# PURPOSE: Safe file move/copy operations with logging
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: safe_move
# PURPOSE:  Move a file with safety checks and logging
# ARGS:     $1 = source path
#           $2 = destination path
#           $3 = log file path (optional)
# RETURNS:  0 on success, 1 on failure
# NOTE:     Creates destination directory if it doesn't exist
#           Respects DRY_RUN mode
# ----------------------------------------------------------------------------
safe_move()
{
    local source_path="$1"
    local dest_path="$2"
    local log_file="${3:-}"

    # Get the directory part of the destination path
    local dest_dir
    dest_dir=$(dirname "$dest_path")

    # Validate source exists
    if [[ ! -e "$source_path" ]]
    then
        log_warn "Source does not exist: $source_path"
        return 1
    fi

    # Check if destination already exists
    if [[ -e "$dest_path" ]]
    then
        log_warn "Destination exists, skipping: $dest_path"
        [[ -n "$log_file" ]] && log_to_file "$log_file" "SKIPPED | $source_path | $dest_path | Destination exists"
        return 1
    fi

    # In dry-run mode, just report what would happen
    if [[ "$DRY_RUN" -eq 1 ]]
    then
        echo "[DRY RUN] Would move: $(basename "$source_path")"
        echo "          From: $source_path"
        echo "          To:   $dest_path"
        return 0
    fi

    # Create destination directory if needed
    mkdir -p "$dest_dir"

    # Perform the move
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

# ----------------------------------------------------------------------------
# FUNCTION: safe_move_dir
# PURPOSE:  Move an entire directory with safety checks
# ARGS:     $1 = source directory path
#           $2 = destination directory path
#           $3 = log file path (optional)
# RETURNS:  0 on success, 1 on failure
# ----------------------------------------------------------------------------
safe_move_dir()
{
    local source_path="$1"
    local dest_path="$2"
    local log_file="${3:-}"

    # Validate source is a directory
    if [[ ! -d "$source_path" ]]
    then
        log_warn "Source directory does not exist: $source_path"
        return 1
    fi

    # In dry-run mode, just report what would happen
    if [[ "$DRY_RUN" -eq 1 ]]
    then
        echo "[DRY RUN] Would move directory: $(basename "$source_path")"
        echo "          From: $source_path"
        echo "          To:   $dest_path"
        return 0
    fi

    # Create parent directory of destination if needed
    mkdir -p "$(dirname "$dest_path")"

    # Perform the move
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
# PURPOSE: Post-operation cleanup tasks
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: remove_empty_dirs
# PURPOSE:  Recursively remove empty directories
# ARGS:     $1 = root directory to clean
# NOTE:     Only removes empty directories, never files
#           Respects DRY_RUN mode
# ----------------------------------------------------------------------------
remove_empty_dirs()
{
    local root_dir="$1"

    if [[ "$DRY_RUN" -eq 1 ]]
    then
        echo "[DRY RUN] Would clean up empty directories in: $root_dir"
        # Show what would be removed
        find "$root_dir" -type d -empty 2>/dev/null | while read -r dir
        do
            echo "          Would remove: $dir"
        done
        return 0
    fi

    # Find and remove empty directories
    # We run this multiple times because removing a directory might make its parent empty
    local removed=1
    while [[ $removed -eq 1 ]]
    do
        removed=0
        while IFS= read -r -d '' dir
        do
            if rmdir "$dir" 2>/dev/null
            then
                log_info "Removed empty directory: $dir"
                removed=1
            fi
        done < <(find "$root_dir" -type d -empty -print0 2>/dev/null)
    done
}

# ============================================================================
# SECTION: BACKUP FUNCTIONS
# PURPOSE: Create and manage backups
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: create_backup
# PURPOSE:  Create a tar.gz backup of specified directories
# ARGS:     $1 = backup filename (without extension)
#           $2... = directories to backup
# OUTPUT:   Creates backup file, prints path to stdout
# NOTE:     Excludes .DS_Store and other system files
# ----------------------------------------------------------------------------
create_backup()
{
    local backup_name="$1"
    shift  # Remove first argument, rest are directories
    local dirs=("$@")

    local backup_file="${OUTPUT_DIR}/${backup_name}.tar.gz"

    if [[ "$DRY_RUN" -eq 1 ]]
    then
        echo "[DRY RUN] Would create backup: $backup_file"
        echo "          Including directories: ${dirs[*]}"
        return 0
    fi

    log_info "Creating backup: $backup_file"

    # Create the backup
    # --exclude patterns remove macOS system files
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
# PURPOSE: Helper functions for working with arrays and lists
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: array_contains
# PURPOSE:  Check if an array contains a specific value
# ARGS:     $1 = value to search for
#           $2... = array elements
# RETURNS:  0 if found, 1 if not found
# EXAMPLE:  if array_contains "apple" "${fruits[@]}"; then ...
# ----------------------------------------------------------------------------
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
# PURPOSE: Generate timestamps for filenames and logging
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: get_timestamp
# PURPOSE:  Get current timestamp in a filename-safe format
# OUTPUT:   Prints timestamp string (e.g., "2026-01-16_14-30-45")
# ----------------------------------------------------------------------------
get_timestamp()
{
    date '+%Y-%m-%d_%H-%M-%S'
}

# ----------------------------------------------------------------------------
# FUNCTION: get_date
# PURPOSE:  Get current date in ISO format
# OUTPUT:   Prints date string (e.g., "2026-01-16")
# ----------------------------------------------------------------------------
get_date()
{
    date '+%Y-%m-%d'
}

# ============================================================================
# END OF UTILS.SH
# ============================================================================
