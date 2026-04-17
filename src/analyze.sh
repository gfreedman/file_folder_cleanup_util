#!/bin/bash
# Phase 1: Read-only scan of source folders — inventory, duplicates, large files, conflicts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

set -e

declare -a ALL_FILES=()
declare -a LARGE_FILES=()
declare -a DUPLICATE_GROUPS=()
declare -A FILE_CHECKSUMS=()
declare -A FILENAME_LOCATIONS=()

TOTAL_FILES=0
TOTAL_DIRS=0
TOTAL_SIZE=0

scan_directory()
{
    local dir_path="$1"
    local source_name
    source_name=$(basename "$dir_path")

    log_info "Scanning: $dir_path"

    local dir_count
    dir_count=$(find "$dir_path" -type d ! -name '.*' 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    TOTAL_DIRS=$((TOTAL_DIRS + dir_count))

    local dir_file_count=0

    while IFS= read -r -d '' file_path
    do
        local file_size
        file_size=$(get_file_size "$file_path")
        local file_name
        file_name=$(basename "$file_path")

        dir_file_count=$((dir_file_count + 1))
        TOTAL_FILES=$((TOTAL_FILES + 1))
        TOTAL_SIZE=$((TOTAL_SIZE + file_size))

        ALL_FILES+=("$file_path")

        if [[ $file_size -gt $LARGE_FILE_THRESHOLD ]]
        then
            LARGE_FILES+=("$file_size|$file_path")
        fi

        if [[ -n "${FILENAME_LOCATIONS[$file_name]:-}" ]]
        then
            FILENAME_LOCATIONS[$file_name]="${FILENAME_LOCATIONS[$file_name]}|$file_path"
        else
            FILENAME_LOCATIONS[$file_name]="$file_path"
        fi

    # -type f matches only regular files. Symlinks are intentionally excluded
    # to avoid following links out of the source tree during reorganization.
    done < <(find "$dir_path" -type f "${FIND_EXCLUDES[@]}" -print0 2>/dev/null)

    log_success "Found $dir_file_count files in $source_name"
}

# Size-first: group by size before hashing — files that differ in size can't
# be duplicates, so this cuts hash operations by ~90% on typical directories.
find_duplicates()
{
    log_info "Checking for duplicate files..."

    # Pass 1: group files by size
    declare -A size_to_files
    for file_path in "${ALL_FILES[@]}"
    do
        local file_size
        file_size=$(get_file_size "$file_path")
        if [[ -n "${size_to_files[$file_size]:-}" ]]
        then
            size_to_files[$file_size]="${size_to_files[$file_size]}|$file_path"
        else
            size_to_files[$file_size]="$file_path"
        fi
    done

    # Pass 2: hash only size-matched candidates
    local checked=0
    local hash_candidates=0

    for size in "${!size_to_files[@]}"
    do
        local paths="${size_to_files[$size]}"
        if [[ "$paths" == *"|"* ]]
        then
            local count
            count=$(echo "$paths" | tr '|' '\n' | wc -l | tr -d ' ')
            hash_candidates=$((hash_candidates + count))
        fi
    done

    log_info "Size-filtering: ${#ALL_FILES[@]} files -> $hash_candidates candidates to hash"

    for size in "${!size_to_files[@]}"
    do
        local paths="${size_to_files[$size]}"
        # Skip sizes with only one file
        [[ "$paths" != *"|"* ]] && continue

        while IFS= read -r file_path
        do
            [[ -z "$file_path" ]] && continue
            checked=$((checked + 1))

            if [[ $((checked % 50)) -eq 0 ]]
            then
                echo -ne "\r  Progress: $checked / $hash_candidates files hashed"
            fi

            local checksum
            checksum=$(get_file_hash "$file_path")

            [[ -z "$checksum" ]] && continue

            if [[ -n "${FILE_CHECKSUMS[$checksum]:-}" ]]
            then
                FILE_CHECKSUMS[$checksum]="${FILE_CHECKSUMS[$checksum]}|$file_path"
            else
                FILE_CHECKSUMS[$checksum]="$file_path"
            fi
        done <<< "$(echo "$paths" | tr '|' '\n')"
    done

    if [[ $hash_candidates -gt 0 ]]
    then
        echo ""  # New line after progress indicator
    fi
    log_success "Duplicate check complete"
}

print_summary()
{
    log_header "ANALYSIS SUMMARY"

    echo "Files found:      $TOTAL_FILES"
    echo "Directories:      $TOTAL_DIRS"
    echo "Total size:       $(format_bytes $TOTAL_SIZE)"
    echo ""

    echo -e "${BOLD}Large Files (>${LARGE_FILE_THRESHOLD} bytes):${NC}"
    if [[ ${#LARGE_FILES[@]} -eq 0 ]]
    then
        echo "  None found"
    else
        echo "  Found ${#LARGE_FILES[@]} large file(s):"
        printf '%s\n' "${LARGE_FILES[@]}" | sort -t'|' -k1 -nr | while IFS='|' read -r size path
        do
            echo "  - $(format_bytes "$size"): $(basename "$path")"
        done
    fi
    echo ""

    echo -e "${BOLD}Duplicate Files (identical content):${NC}"
    local dup_count=0
    for checksum in "${!FILE_CHECKSUMS[@]}"
    do
        local paths="${FILE_CHECKSUMS[$checksum]}"
        if [[ "$paths" == *"|"* ]]
        then
            dup_count=$((dup_count + 1))
            if [[ $dup_count -le 10 ]]
            then
                echo "  Duplicate group $dup_count (SHA256: ${checksum:0:8}...):"
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

    echo -e "${BOLD}Filename Conflicts (same name, different locations):${NC}"
    local conflict_count=0
    for filename in "${!FILENAME_LOCATIONS[@]}"
    do
        local locations="${FILENAME_LOCATIONS[$filename]}"
        if [[ "$locations" == *"|"* ]]
        then
            conflict_count=$((conflict_count + 1))
            if [[ $conflict_count -le 10 ]]
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

export_analysis()
{
    local output_file="$1"

    log_info "Exporting analysis to: $output_file"

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

main()
{
    log_header "PHASE 1: ANALYSIS"

    if [[ $# -lt 1 ]]
    then
        log_error "Usage: $0 <source_dir1> [source_dir2] ..."
        log_error "Example: $0 ~/Desktop ~/Downloads"
        exit 1
    fi

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

    for source_dir in "$@"
    do
        scan_directory "$source_dir"
    done

    find_duplicates

    print_summary

    # Always export an audit record of the analysis phase.
    # OUTPUT_DIR defaults to '.' (current directory) if CLEANUP_OUTPUT_DIR is not set.
    export_analysis "${OUTPUT_DIR}/analysis_$(get_timestamp).txt"

    log_success "Analysis complete!"

    echo ""
    echo "ANALYSIS_COMPLETE|$TOTAL_FILES|$TOTAL_DIRS|$TOTAL_SIZE"
}

main "$@"
