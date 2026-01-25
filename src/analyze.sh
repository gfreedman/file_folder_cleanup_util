#!/bin/bash
# ============================================================================
# FILE:        analyze.sh
# PURPOSE:     Phase 1 - Analyze source folders before reorganization
# DESCRIPTION: This script scans the specified source folders and collects
#              information needed to plan the reorganization:
#              - Complete file inventory with sizes
#              - Duplicate files (same content, detected via MD5)
#              - Large files (above configurable threshold)
#              - Filename conflicts (same name in different locations)
#
# USAGE:       ./analyze.sh <source_dir1> [source_dir2] [source_dir3] ...
#
# OUTPUT:      Prints analysis summary to stdout
#              Optionally writes detailed report to file
#
# NOTE:        This is a READ-ONLY phase. No files are modified.
# ============================================================================

# Get the directory where this script is located
# This allows us to find utils.sh regardless of where the script is called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the utility functions
# The "source" command loads another script's functions into this script
source "${SCRIPT_DIR}/utils.sh"

# ============================================================================
# SECTION: CONFIGURATION
# ============================================================================

# These arrays will hold our analysis results
declare -a ALL_FILES=()           # All files found
declare -a LARGE_FILES=()         # Files larger than threshold
declare -a DUPLICATE_GROUPS=()    # Groups of duplicate files
declare -A FILE_CHECKSUMS=()      # Map of checksum -> file paths
declare -A FILENAME_LOCATIONS=()  # Map of filename -> locations (for conflict detection)

# Counters for summary
TOTAL_FILES=0
TOTAL_DIRS=0
TOTAL_SIZE=0

# ============================================================================
# SECTION: ANALYSIS FUNCTIONS
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: scan_directory
# PURPOSE:  Recursively scan a directory and inventory all files
# ARGS:     $1 = directory path to scan
# SIDE EFFECTS: Populates global arrays with file information
# ----------------------------------------------------------------------------
scan_directory()
{
    local dir_path="$1"
    local source_name
    source_name=$(basename "$dir_path")

    log_info "Scanning: $dir_path"

    # Count directories (excluding hidden)
    local dir_count
    dir_count=$(find "$dir_path" -type d ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')
    TOTAL_DIRS=$((TOTAL_DIRS + dir_count))

    # Find all files (excluding system files like .DS_Store)
    # The 'find' command searches recursively
    # -type f means "only files, not directories"
    # ! -name pattern means "exclude files matching pattern"
    while IFS= read -r -d '' file_path
    do
        # Get file information
        local file_size
        file_size=$(get_file_size "$file_path")
        local file_name
        file_name=$(basename "$file_path")

        # Add to totals
        TOTAL_FILES=$((TOTAL_FILES + 1))
        TOTAL_SIZE=$((TOTAL_SIZE + file_size))

        # Track this file
        ALL_FILES+=("$file_path")

        # Check if it's a large file
        if [[ $file_size -gt $LARGE_FILE_THRESHOLD ]]
        then
            LARGE_FILES+=("$file_size|$file_path")
        fi

        # Track filename for conflict detection
        # If we've seen this filename before, it's a potential conflict
        if [[ -n "${FILENAME_LOCATIONS[$file_name]:-}" ]]
        then
            # Append this location (pipe-separated)
            FILENAME_LOCATIONS[$file_name]="${FILENAME_LOCATIONS[$file_name]}|$file_path"
        else
            FILENAME_LOCATIONS[$file_name]="$file_path"
        fi

    done < <(find "$dir_path" -type f \
        ! -name '.DS_Store' \
        ! -name '.localized' \
        ! -name '._*' \
        ! -path '*/.git/*' \
        ! -path '*/venv/*' \
        ! -path '*/__pycache__/*' \
        -print0 2>/dev/null)

    log_success "Found $TOTAL_FILES files in $source_name"
}

# ----------------------------------------------------------------------------
# FUNCTION: find_duplicates
# PURPOSE:  Identify duplicate files by comparing MD5 checksums
# NOTE:     This can be slow for large numbers of files
# SIDE EFFECTS: Populates FILE_CHECKSUMS associative array
# ----------------------------------------------------------------------------
find_duplicates()
{
    log_info "Checking for duplicate files (this may take a moment)..."

    local checked=0
    local total=${#ALL_FILES[@]}

    # Calculate MD5 for each file
    for file_path in "${ALL_FILES[@]}"
    do
        checked=$((checked + 1))

        # Show progress every 50 files
        if [[ $((checked % 50)) -eq 0 ]]
        then
            echo -ne "\r  Progress: $checked / $total files checked"
        fi

        # Get MD5 checksum
        local checksum
        checksum=$(get_file_md5 "$file_path")

        # Skip if we couldn't get checksum (permission issue, etc.)
        [[ -z "$checksum" ]] && continue

        # Track files by checksum
        if [[ -n "${FILE_CHECKSUMS[$checksum]:-}" ]]
        then
            # We've seen this checksum before - it's a duplicate!
            FILE_CHECKSUMS[$checksum]="${FILE_CHECKSUMS[$checksum]}|$file_path"
        else
            FILE_CHECKSUMS[$checksum]="$file_path"
        fi
    done

    echo ""  # New line after progress indicator
    log_success "Duplicate check complete"
}

# ----------------------------------------------------------------------------
# FUNCTION: print_summary
# PURPOSE:  Print a formatted summary of the analysis
# ----------------------------------------------------------------------------
print_summary()
{
    log_header "ANALYSIS SUMMARY"

    # Basic stats
    echo "Files found:      $TOTAL_FILES"
    echo "Directories:      $TOTAL_DIRS"
    echo "Total size:       $(format_bytes $TOTAL_SIZE)"
    echo ""

    # Large files
    echo -e "${BOLD}Large Files (>${LARGE_FILE_THRESHOLD} bytes):${NC}"
    if [[ ${#LARGE_FILES[@]} -eq 0 ]]
    then
        echo "  None found"
    else
        echo "  Found ${#LARGE_FILES[@]} large file(s):"
        # Sort by size (largest first) and display
        printf '%s\n' "${LARGE_FILES[@]}" | sort -t'|' -k1 -nr | while IFS='|' read -r size path
        do
            echo "  - $(format_bytes "$size"): $(basename "$path")"
        done
    fi
    echo ""

    # Duplicate files
    echo -e "${BOLD}Duplicate Files (identical content):${NC}"
    local dup_count=0
    for checksum in "${!FILE_CHECKSUMS[@]}"
    do
        local paths="${FILE_CHECKSUMS[$checksum]}"
        # Check if there's more than one file with this checksum (contains |)
        if [[ "$paths" == *"|"* ]]
        then
            dup_count=$((dup_count + 1))
            if [[ $dup_count -le 10 ]]  # Show first 10
            then
                echo "  Duplicate group $dup_count (MD5: ${checksum:0:8}...):"
                echo "$paths" | tr '|' '\n' | while read -r path
                do
                    echo "    - $(basename "$path")"
                    echo "      $path"
                done
            fi
        fi
    done
    if [[ $dup_count -eq 0 ]]
    then
        echo "  None found"
    elif [[ $dup_count -gt 10 ]]
    then
        echo "  ... and $((dup_count - 10)) more duplicate groups"
    fi
    echo ""

    # Filename conflicts
    echo -e "${BOLD}Filename Conflicts (same name, different locations):${NC}"
    local conflict_count=0
    for filename in "${!FILENAME_LOCATIONS[@]}"
    do
        local locations="${FILENAME_LOCATIONS[$filename]}"
        # Check if there's more than one location (contains |)
        if [[ "$locations" == *"|"* ]]
        then
            conflict_count=$((conflict_count + 1))
            if [[ $conflict_count -le 10 ]]  # Show first 10
            then
                echo "  \"$filename\" found in:"
                echo "$locations" | tr '|' '\n' | while read -r path
                do
                    echo "    - $(dirname "$path")"
                done
            fi
        fi
    done
    if [[ $conflict_count -eq 0 ]]
    then
        echo "  None found"
    elif [[ $conflict_count -gt 10 ]]
    then
        echo "  ... and $((conflict_count - 10)) more conflicts"
    fi
    echo ""
}

# ----------------------------------------------------------------------------
# FUNCTION: export_analysis
# PURPOSE:  Write detailed analysis to a JSON-like file for other scripts
# ARGS:     $1 = output file path
# ----------------------------------------------------------------------------
export_analysis()
{
    local output_file="$1"

    log_info "Exporting analysis to: $output_file"

    # Write analysis data in a simple format that's easy to parse
    {
        echo "# Analysis Export - $(get_timestamp)"
        echo "# Format: TYPE|DATA"
        echo ""
        echo "# Summary"
        echo "SUMMARY|files=$TOTAL_FILES|dirs=$TOTAL_DIRS|size=$TOTAL_SIZE"
        echo ""
        echo "# All Files (one per line)"
        for file in "${ALL_FILES[@]}"
        do
            echo "FILE|$file"
        done
        echo ""
        echo "# Large Files (size|path)"
        for item in "${LARGE_FILES[@]}"
        do
            echo "LARGE|$item"
        done
        echo ""
        echo "# Duplicates (checksum|path1|path2|...)"
        for checksum in "${!FILE_CHECKSUMS[@]}"
        do
            local paths="${FILE_CHECKSUMS[$checksum]}"
            if [[ "$paths" == *"|"* ]]
            then
                echo "DUPLICATE|$checksum|$paths"
            fi
        done
        echo ""
        echo "# Filename Conflicts (filename|path1|path2|...)"
        for filename in "${!FILENAME_LOCATIONS[@]}"
        do
            local locations="${FILENAME_LOCATIONS[$filename]}"
            if [[ "$locations" == *"|"* ]]
            then
                echo "CONFLICT|$filename|$locations"
            fi
        done
    } > "$output_file"

    log_success "Analysis exported"
}

# ============================================================================
# SECTION: MAIN EXECUTION
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: main
# PURPOSE:  Main entry point for the analysis script
# ARGS:     $@ = source directories to analyze
# ----------------------------------------------------------------------------
main()
{
    log_header "PHASE 1: ANALYSIS"

    # Check that we have at least one source directory
    if [[ $# -lt 1 ]]
    then
        log_error "Usage: $0 <source_dir1> [source_dir2] ..."
        log_error "Example: $0 ~/Desktop ~/Downloads"
        exit 1
    fi

    # Validate all source directories first
    for source_dir in "$@"
    do
        if ! validate_directory "$source_dir"
        then
            exit 1
        fi
        if ! validate_not_system_dir "$source_dir"
        then
            exit 1
        fi
    done

    echo "Source directories to analyze:"
    for source_dir in "$@"
    do
        echo "  - $source_dir"
    done
    echo ""

    # Scan each source directory
    for source_dir in "$@"
    do
        scan_directory "$source_dir"
    done

    # Find duplicates
    find_duplicates

    # Print summary
    print_summary

    # Export if OUTPUT_DIR is set
    if [[ -n "${OUTPUT_DIR:-}" && "$OUTPUT_DIR" != "." ]]
    then
        export_analysis "${OUTPUT_DIR}/analysis_$(get_timestamp).txt"
    fi

    log_success "Analysis complete!"

    # Return data for piping to next phase
    echo ""
    echo "ANALYSIS_COMPLETE|$TOTAL_FILES|$TOTAL_DIRS|$TOTAL_SIZE"
}

# Run main function with all command line arguments
# The "$@" passes all arguments to the function
main "$@"
