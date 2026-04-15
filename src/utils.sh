#!/bin/bash
# Shared utility functions: logging, validation, file ops.
# Source this file in other scripts: source "$(dirname "$0")/utils.sh"

if ((BASH_VERSINFO[0] < 4)); then
    echo "Error: Bash 4+ required. macOS ships 3.2; install via: brew install bash" >&2
    exit 1
fi

set -u          # Exit on unset variable reference
set -o pipefail # Propagate pipe failures

# Disable colors when stdout is redirected to a file.
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

LARGE_FILE_THRESHOLD="${CLEANUP_LARGE_FILE_THRESHOLD:-104857600}"  # 100MB
DRY_RUN="${CLEANUP_DRY_RUN:-1}"          # default on for safety
CREATE_BACKUP="${CLEANUP_CREATE_BACKUP:-1}"
OUTPUT_DIR="${CLEANUP_OUTPUT_DIR:-.}"

FIND_EXCLUDES=(
    ! -name '.DS_Store'
    ! -name '.localized'
    ! -name '._*'
    ! -path '*/.git/*'
    ! -path '*/venv/*'
    ! -path '*/__pycache__/*'
)

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

log_header()
{
    echo ""
    echo -e "${BOLD}=============================================="
    echo -e "$1"
    echo -e "==============================================${NC}"
    echo ""
}

log_to_file()
{
    local log_file="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $message" >> "$log_file"
}

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

get_file_size()
{
    local file_path="$1"
    stat -f "%z" "$file_path" 2>/dev/null || echo "0"
}

get_file_hash()
{
    local file_path="$1"
    shasum -a 256 "$file_path" 2>/dev/null | cut -d' ' -f1
}

# Pure integer arithmetic — avoids bc/awk dependency.
format_bytes()
{
    local bytes=$1
    if ((bytes >= 1073741824)); then echo "$((bytes / 1073741824)) GB"
    elif ((bytes >= 1048576)); then echo "$((bytes / 1048576)) MB"
    elif ((bytes >= 1024)); then echo "$((bytes / 1024)) KB"
    else echo "${bytes} bytes"
    fi
}

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

# find -depth ensures bottom-up traversal so parent dirs are emptied
# before we try to remove them — no second pass needed.
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

get_timestamp() { date '+%Y-%m-%d_%H-%M-%S'; }
get_date()      { date '+%Y-%m-%d'; }
