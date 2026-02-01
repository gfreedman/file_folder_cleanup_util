#!/bin/bash
# ============================================================================
# FILE:        generate_plan.sh
# PURPOSE:     Phase 3 - Generate migration plan and scripts
# DESCRIPTION: Takes analysis and structure from previous phases and generates:
#              1. manifest.txt - Complete audit trail of all planned moves
#              2. execute.sh - The actual migration script (with dry-run)
#              3. reversal.sh - Script to undo all changes
#              4. backup.tar.gz - Full backup of source folders (optional)
#
# USAGE:       ./generate_plan.sh --sources <dir1,dir2> --target <dir>
#                                 --structure <file> [--mapping <file>]
#                                 [--analysis <file>]
#
# OUTPUT:      Creates 4 files in OUTPUT_DIR
# NOTE:        This phase WRITES files but does NOT move any user files.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# ============================================================================
# SECTION: CONFIGURATION
# ============================================================================

TIMESTAMP=$(get_timestamp)
MANIFEST_FILE=""
EXECUTE_SCRIPT=""
REVERSAL_SCRIPT=""
BACKUP_FILE=""

declare -a MAPPING_RULES=()

# ============================================================================
# SECTION: MAPPING FUNCTIONS
# ============================================================================

# Load default file-to-folder mapping rules
load_default_mappings()
{
    MAPPING_RULES=(
        # Documents
        "*.pdf|Documents/"
        "*.doc|Documents/"
        "*.docx|Documents/"
        "*.txt|Documents/"
        "*.pages|Documents/"
        "*.rtf|Documents/"

        # Spreadsheets
        "*.xls|Documents/Spreadsheets/"
        "*.xlsx|Documents/Spreadsheets/"
        "*.csv|Archives/Data/"
        "*.numbers|Documents/Spreadsheets/"

        # Images
        "*.jpg|Media/Images/Photos/"
        "*.jpeg|Media/Images/Photos/"
        "*.png|Media/Images/"
        "*.gif|Media/Images/"
        "*.heic|Media/Images/Photos/"
        "*.webp|Media/Images/"
        "*.svg|Media/Images/Diagrams/"

        # Audio
        "*.mp3|Media/Audio/"
        "*.m4a|Media/Audio/"
        "*.wav|Media/Audio/"
        "*.aac|Media/Audio/"
        "*.flac|Media/Audio/"

        # Video
        "*.mp4|Media/Video/"
        "*.mov|Media/Video/"
        "*.avi|Media/Video/"
        "*.mkv|Media/Video/"

        # Archives
        "*.zip|Archives/"
        "*.tar|Archives/"
        "*.gz|Archives/"
        "*.tar.gz|Archives/"
        "*.dmg|Archives/Software/"
        "*.pkg|Archives/Software/"

        # Code
        "*.py|Projects/Code/"
        "*.js|Projects/Code/"
        "*.sh|Projects/Code/"
        "*.html|Projects/Code/"
        "*.css|Projects/Code/"

        # Fonts
        "*.ttf|Archives/Fonts/"
        "*.otf|Archives/Fonts/"
        "*.woff|Archives/Fonts/"
    )
}

# Load custom mapping rules from a file
# Args: $1 = mapping file path
load_mapping_file()
{
    local mapping_file="$1"

    if [[ ! -f "$mapping_file" ]]
    then
        log_warn "Mapping file not found: $mapping_file"
        log_info "Using default mappings"
        load_default_mappings
        return
    fi

    log_info "Loading custom mappings from: $mapping_file"

    MAPPING_RULES=()

    while IFS='|' read -r pattern destination
    do
        [[ "$pattern" =~ ^# ]] && continue
        [[ -z "$pattern" ]] && continue

        MAPPING_RULES+=("$pattern|$destination")
    done < "$mapping_file"

    log_success "Loaded ${#MAPPING_RULES[@]} mapping rules"
}

# Determine destination folder for a file based on mapping rules
# Args: $1 = source file path, $2 = target root directory
# Output: Prints full destination path
get_destination()
{
    local source_path="$1"
    local target_root="$2"

    local filename
    filename=$(basename "$source_path")

    local extension
    extension=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')

    for rule in "${MAPPING_RULES[@]}"
    do
        local pattern="${rule%%|*}"
        local destination="${rule##*|}"

        if [[ "$pattern" == "*."* ]]
        then
            local rule_ext="${pattern#*.}"
            if [[ "$extension" == "$rule_ext" ]]
            then
                echo "${target_root}/${destination}${filename}"
                return
            fi
        elif [[ "$filename" == "$pattern" ]]
        then
            echo "${target_root}/${destination}${filename}"
            return
        fi
    done

    # Default: put in root of target with original filename
    echo "${target_root}/${filename}"
}

# ============================================================================
# SECTION: MANIFEST GENERATION
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: generate_manifest
# PURPOSE:  Create a detailed manifest of all planned moves. If an analysis
#           export file is provided, reads the file list from it instead of
#           re-running find (eliminates duplicate traversals).
# ARGS:     $1 = manifest file path
#           $2 = target directory
#           $3 = analysis file path (optional, "" to skip)
#           $4... = source directories
# ----------------------------------------------------------------------------
generate_manifest()
{
    local manifest_file="$1"
    local target_dir="$2"
    local analysis_file="$3"
    shift 3
    local source_dirs=("$@")

    log_info "Generating manifest: $manifest_file"

    # Write manifest header
    {
        echo "# ============================================================================"
        echo "# FILE REORGANIZATION MANIFEST"
        echo "# Generated: $(date)"
        echo "# ============================================================================"
        echo "#"
        echo "# This manifest documents all planned file moves."
        echo "# Review carefully before executing."
        echo "#"
        echo "# FORMAT: STATUS | SOURCE | DESTINATION | NOTES"
        echo "#"
        echo "# STATUSES:"
        echo "#   PLANNED    - Move is planned and ready to execute"
        echo "#   CONFLICT   - Destination exists, needs resolution"
        echo "#   DUPLICATE  - File is duplicate of another, will be skipped"
        echo "#   LARGE      - File exceeds size threshold (still moved)"
        echo "#"
        echo "# ============================================================================"
        echo ""
        echo "TARGET_DIR|$target_dir"
        echo "SOURCE_DIRS|${source_dirs[*]}"
        echo "GENERATED|$(get_timestamp)"
        echo ""
        echo "# ============================================================================"
        echo "# PLANNED MOVES"
        echo "# ============================================================================"
        echo ""
    } > "$manifest_file"

    declare -A destination_map

    # If analysis file is available, read file list from it
    if [[ -n "$analysis_file" && -f "$analysis_file" ]]
    then
        log_info "Reading file list from analysis export: $analysis_file"

        {
            while IFS='|' read -r type data
            do
                [[ "$type" != "FILE" ]] && continue
                [[ -z "$data" ]] && continue

                local source_path="$data"
                local filename
                filename=$(basename "$source_path")

                local dest_path
                dest_path=$(get_destination "$source_path" "$target_dir")

                local status="PLANNED"
                local notes=""

                if [[ -n "${destination_map[$dest_path]:-}" ]]
                then
                    status="CONFLICT"
                    notes="Conflicts with: ${destination_map[$dest_path]}"
                else
                    destination_map[$dest_path]="$source_path"
                fi

                local file_size
                file_size=$(get_file_size "$source_path")
                if [[ $file_size -gt $LARGE_FILE_THRESHOLD ]]
                then
                    notes="${notes}Large file: $(format_bytes $file_size)"
                fi

                echo "$status|$source_path|$dest_path|$notes"

            done < "$analysis_file"
        } >> "$manifest_file"
    else
        # Fall back to find traversal
        for source_dir in "${source_dirs[@]}"
        do
            log_info "Processing: $source_dir"

            {
                while IFS= read -r -d '' source_path
                do
                    local filename
                    filename=$(basename "$source_path")

                    local dest_path
                    dest_path=$(get_destination "$source_path" "$target_dir")

                    local status="PLANNED"
                    local notes=""

                    if [[ -n "${destination_map[$dest_path]:-}" ]]
                    then
                        status="CONFLICT"
                        notes="Conflicts with: ${destination_map[$dest_path]}"
                    else
                        destination_map[$dest_path]="$source_path"
                    fi

                    local file_size
                    file_size=$(get_file_size "$source_path")
                    if [[ $file_size -gt $LARGE_FILE_THRESHOLD ]]
                    then
                        notes="${notes}Large file: $(format_bytes $file_size)"
                    fi

                    echo "$status|$source_path|$dest_path|$notes"

                done < <(find "$source_dir" -type f "${FIND_EXCLUDES[@]}" -print0 2>/dev/null)
            } >> "$manifest_file"
        done
    fi

    log_success "Manifest generated with $(grep -c '^PLANNED\|^CONFLICT\|^DUPLICATE\|^LARGE' "$manifest_file") entries"
}

# ============================================================================
# SECTION: SCRIPT GENERATION
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: generate_execute_script
# PURPOSE:  Create the migration execution script. The generated script reads
#           moves from the manifest at runtime rather than inlining paths,
#           which eliminates shell injection vectors and produces a smaller script.
# ARGS:     $1 = script file path, $2 = manifest file path
# ----------------------------------------------------------------------------
generate_execute_script()
{
    local script_file="$1"
    local manifest_file="$2"
    local manifest_basename
    manifest_basename=$(basename "$manifest_file")

    log_info "Generating execute script: $script_file"

    cat > "$script_file" << 'HEADER'
#!/bin/bash
# ============================================================================
# FILE:        execute.sh (auto-generated)
# PURPOSE:     Execute the file reorganization
# DESCRIPTION: This script reads moves from the manifest file and performs
#              them. It runs in DRY-RUN mode by default for safety.
#
# USAGE:       ./execute.sh              # Dry run (preview)
#              ./execute.sh --execute    # Actually move files
#
# WARNING:     Always run without --execute first to preview changes!
# ============================================================================

set -e  # Exit on error

# Default to dry-run mode (safe)
DRY_RUN=1

# Parse arguments
if [[ "${1:-}" == "--execute" ]]
then
    DRY_RUN=0
    echo "*** EXECUTE MODE - Files will be moved ***"
    echo ""
    read -p "Are you sure? Type 'yes' to proceed: " confirm
    if [[ "$confirm" != "yes" ]]
    then
        echo "Aborted."
        exit 0
    fi
else
    echo "*** DRY RUN MODE - No files will be moved ***"
    echo "Run with --execute to perform actual moves"
    echo ""
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
moved=0
skipped=0
failed=0

# Logging
log_file="execution_log_$(date +%Y-%m-%d_%H-%M-%S).txt"

log()
{
    echo "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$log_file"
}

HEADER

    # Write the manifest-reading move logic
    cat >> "$script_file" << MANIFEST_READER

# ============================================================================
# FILE MOVES (read from manifest)
# ============================================================================

MANIFEST_FILE="\$(dirname "\$0")/${manifest_basename}"

if [[ ! -f "\$MANIFEST_FILE" ]]
then
    echo "Error: Manifest not found: \$MANIFEST_FILE" >&2
    exit 1
fi

while IFS='|' read -r status source dest notes
do
    # Skip header lines, comments, and non-planned entries
    [[ "\$status" =~ ^# ]] && continue
    [[ "\$status" != "PLANNED" ]] && continue
    [[ -z "\$source" ]] && continue

    basename_file="\$(basename "\$source")"

    if [[ -f "\$source" ]]
    then
        dest_dir="\$(dirname "\$dest")"
        if [[ "\$DRY_RUN" -eq 1 ]]
        then
            echo "[DRY RUN] Would move: \$basename_file"
        else
            mkdir -p "\$dest_dir"
            if mv "\$source" "\$dest"
            then
                log "MOVED: \$source -> \$dest"
                ((moved++))
            else
                log "FAILED: \$source"
                ((failed++))
            fi
        fi
    else
        log "SKIPPED (not found): \$source"
        ((skipped++))
    fi
done < "\$MANIFEST_FILE"

MANIFEST_READER

    # Add summary section
    cat >> "$script_file" << 'FOOTER'

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "=============================================="
echo "EXECUTION COMPLETE"
echo "=============================================="
echo ""

if [[ "$DRY_RUN" -eq 1 ]]
then
    echo "This was a DRY RUN. No files were moved."
    echo "Run with --execute to perform actual moves."
else
    echo "Moved:   $moved files"
    echo "Skipped: $skipped files"
    echo "Failed:  $failed files"
    echo ""
    echo "Log file: $log_file"
fi
FOOTER

    chmod +x "$script_file"

    log_success "Execute script generated"
}

# ----------------------------------------------------------------------------
# FUNCTION: generate_reversal_script
# PURPOSE:  Create a script to undo all moves. Reads from manifest at runtime.
# ARGS:     $1 = script file path, $2 = manifest file path
# ----------------------------------------------------------------------------
generate_reversal_script()
{
    local script_file="$1"
    local manifest_file="$2"
    local manifest_basename
    manifest_basename=$(basename "$manifest_file")

    log_info "Generating reversal script: $script_file"

    cat > "$script_file" << REVERSAL_SCRIPT
#!/bin/bash
# ============================================================================
# FILE:        reversal.sh (auto-generated)
# PURPOSE:     Undo the file reorganization
# DESCRIPTION: Reads the manifest and moves files back to their original
#              locations. Processes in reverse order (LIFO).
#
# USAGE:       ./reversal.sh
# ============================================================================

set -e

echo "=============================================="
echo "REVERSAL SCRIPT"
echo "=============================================="
echo ""
echo "This will move files back to their original locations."
read -p "Are you sure? Type 'yes' to proceed: " confirm
if [[ "\$confirm" != "yes" ]]
then
    echo "Aborted."
    exit 0
fi

echo ""

MANIFEST_FILE="\$(dirname "\$0")/${manifest_basename}"

if [[ ! -f "\$MANIFEST_FILE" ]]
then
    echo "Error: Manifest not found: \$MANIFEST_FILE" >&2
    exit 1
fi

# Read manifest in reverse order
reverse_lines()
{
    if command -v tac &> /dev/null
    then
        tac "\$1"
    elif tail -r /dev/null &> /dev/null
    then
        tail -r "\$1"
    else
        awk '{a[NR]=\$0} END {for(i=NR;i>=1;i--) print a[i]}' "\$1"
    fi
}

while IFS='|' read -r status source dest notes
do
    [[ "\$status" =~ ^# ]] && continue
    [[ "\$status" != "PLANNED" ]] && continue
    [[ -z "\$source" ]] && continue

    basename_file="\$(basename "\$source")"
    source_dir="\$(dirname "\$source")"

    if [[ -f "\$dest" ]]
    then
        mkdir -p "\$source_dir"
        mv "\$dest" "\$source" && echo "Restored: \$basename_file"
    fi
done < <(reverse_lines "\$MANIFEST_FILE")

echo ""
echo "Reversal complete!"
REVERSAL_SCRIPT

    chmod +x "$script_file"

    log_success "Reversal script generated"
}

# ============================================================================
# SECTION: BACKUP GENERATION
# ============================================================================

# Create a tar.gz backup of source directories
# Args: $1 = backup file path (without extension), $2... = directories
generate_backup()
{
    local backup_path="$1"
    shift
    local dirs=("$@")

    if [[ "$CREATE_BACKUP" -ne 1 ]]
    then
        log_info "Backup creation skipped (CREATE_BACKUP=0)"
        return
    fi

    local backup_file="${backup_path}.tar.gz"
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
    else
        log_error "Failed to create backup"
        return 1
    fi
}

# ============================================================================
# SECTION: MAIN EXECUTION
# ============================================================================

main()
{
    log_header "PHASE 3: GENERATE PLAN"

    local target_dir=""
    local source_dirs=()
    local structure_file=""
    local mapping_file=""
    local analysis_file=""

    while [[ $# -gt 0 ]]
    do
        case "$1" in
            --target)
                target_dir="$2"
                shift 2
                ;;
            --sources)
                IFS=',' read -ra source_dirs <<< "$2"
                shift 2
                ;;
            --structure)
                structure_file="$2"
                shift 2
                ;;
            --mapping)
                mapping_file="$2"
                shift 2
                ;;
            --analysis)
                analysis_file="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if [[ -z "$target_dir" ]]
    then
        log_error "Target directory required (--target)"
        exit 1
    fi

    if [[ ${#source_dirs[@]} -eq 0 ]]
    then
        log_error "Source directories required (--sources dir1,dir2)"
        exit 1
    fi

    OUTPUT_DIR="${OUTPUT_DIR:-.}"
    MANIFEST_FILE="${OUTPUT_DIR}/manifest_${TIMESTAMP}.txt"
    EXECUTE_SCRIPT="${OUTPUT_DIR}/execute_${TIMESTAMP}.sh"
    REVERSAL_SCRIPT="${OUTPUT_DIR}/reversal_${TIMESTAMP}.sh"
    BACKUP_FILE="${OUTPUT_DIR}/backup_${TIMESTAMP}"

    echo "Configuration:"
    echo "  Target:  $target_dir"
    echo "  Sources: ${source_dirs[*]}"
    echo "  Output:  $OUTPUT_DIR"
    [[ -n "$analysis_file" ]] && echo "  Analysis: $analysis_file"
    echo ""

    if [[ -n "$mapping_file" ]]
    then
        load_mapping_file "$mapping_file"
    else
        load_default_mappings
    fi

    generate_manifest "$MANIFEST_FILE" "$target_dir" "${analysis_file:-}" "${source_dirs[@]}"
    generate_execute_script "$EXECUTE_SCRIPT" "$MANIFEST_FILE"
    generate_reversal_script "$REVERSAL_SCRIPT" "$MANIFEST_FILE"
    generate_backup "$BACKUP_FILE" "${source_dirs[@]}"

    log_header "GENERATION COMPLETE"

    echo "Generated files:"
    echo "  Manifest:  $MANIFEST_FILE"
    echo "  Execute:   $EXECUTE_SCRIPT"
    echo "  Reversal:  $REVERSAL_SCRIPT"
    if [[ "$CREATE_BACKUP" -eq 1 ]]
    then
        echo "  Backup:    ${BACKUP_FILE}.tar.gz"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Review the manifest to ensure moves are correct"
    echo "  2. Run execute script in dry-run mode: bash $EXECUTE_SCRIPT"
    echo "  3. If satisfied, run with --execute: bash $EXECUTE_SCRIPT --execute"
    echo ""
}

main "$@"
