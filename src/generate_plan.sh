#!/bin/bash
# ============================================================================
# FILE:        generate_plan.sh
# PURPOSE:     Phase 3 - Generate migration plan and scripts
# DESCRIPTION: This script takes the analysis and structure from previous
#              phases and generates:
#              1. manifest.txt - Complete audit trail of all planned moves
#              2. execute.sh - The actual migration script (with dry-run)
#              3. reversal.sh - Script to undo all changes
#              4. backup.tar.gz - Full backup of source folders (optional)
#
# USAGE:       ./generate_plan.sh --sources <dir1,dir2> --target <dir>
#                                 --structure <file> [--mapping <file>]
#
# OUTPUT:      Creates 4 files in OUTPUT_DIR
#
# NOTE:        This phase WRITES files but does NOT move any user files.
#              User files are only moved in Phase 4.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# ============================================================================
# SECTION: CONFIGURATION
# ============================================================================

# File paths for generated outputs
TIMESTAMP=$(get_timestamp)
MANIFEST_FILE=""
EXECUTE_SCRIPT=""
REVERSAL_SCRIPT=""
BACKUP_FILE=""

# Mapping rules (can be customized)
# Format: source_pattern|destination_folder
declare -a MAPPING_RULES=()

# ============================================================================
# SECTION: MAPPING FUNCTIONS
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: load_default_mappings
# PURPOSE:  Load default file-to-folder mapping rules
# NOTE:     These can be overridden by a custom mapping file
# ----------------------------------------------------------------------------
load_default_mappings()
{
    # Default mappings based on file extensions
    # Format: "pattern|destination"
    # Pattern can be: extension (*.pdf), folder name, or filename pattern

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

# ----------------------------------------------------------------------------
# FUNCTION: load_mapping_file
# PURPOSE:  Load custom mapping rules from a file
# ARGS:     $1 = mapping file path
# ----------------------------------------------------------------------------
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

    # Clear default rules
    MAPPING_RULES=()

    # Read rules from file
    while IFS='|' read -r pattern destination
    do
        # Skip comments and empty lines
        [[ "$pattern" =~ ^# ]] && continue
        [[ -z "$pattern" ]] && continue

        MAPPING_RULES+=("$pattern|$destination")
    done < "$mapping_file"

    log_success "Loaded ${#MAPPING_RULES[@]} mapping rules"
}

# ----------------------------------------------------------------------------
# FUNCTION: get_destination
# PURPOSE:  Determine destination folder for a file based on mapping rules
# ARGS:     $1 = source file path
#           $2 = target root directory
# OUTPUT:   Prints full destination path
# ----------------------------------------------------------------------------
get_destination()
{
    local source_path="$1"
    local target_root="$2"

    local filename
    filename=$(basename "$source_path")

    local extension
    extension=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')

    # Try to match against rules
    for rule in "${MAPPING_RULES[@]}"
    do
        local pattern="${rule%%|*}"
        local destination="${rule##*|}"

        # Check if pattern matches
        # Handle *.ext patterns
        if [[ "$pattern" == "*."* ]]
        then
            local rule_ext="${pattern#*.}"
            if [[ "$extension" == "$rule_ext" ]]
            then
                echo "${target_root}/${destination}${filename}"
                return
            fi
        # Handle exact filename match
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
# PURPOSE:  Create a detailed manifest of all planned moves
# ARGS:     $1 = manifest file path
#           $2 = target directory
#           $3... = source directories
# ----------------------------------------------------------------------------
generate_manifest()
{
    local manifest_file="$1"
    local target_dir="$2"
    shift 2
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

    # Track destinations to detect conflicts
    declare -A destination_map

    # Process each source directory
    for source_dir in "${source_dirs[@]}"
    do
        log_info "Processing: $source_dir"

        # Find all files
        while IFS= read -r -d '' source_path
        do
            local filename
            filename=$(basename "$source_path")

            # Determine destination
            local dest_path
            dest_path=$(get_destination "$source_path" "$target_dir")

            # Check for conflicts
            local status="PLANNED"
            local notes=""

            if [[ -n "${destination_map[$dest_path]:-}" ]]
            then
                status="CONFLICT"
                notes="Conflicts with: ${destination_map[$dest_path]}"
            else
                destination_map[$dest_path]="$source_path"
            fi

            # Check file size
            local file_size
            file_size=$(get_file_size "$source_path")
            if [[ $file_size -gt $LARGE_FILE_THRESHOLD ]]
            then
                notes="${notes}Large file: $(format_bytes $file_size)"
            fi

            # Write to manifest
            echo "$status|$source_path|$dest_path|$notes" >> "$manifest_file"

        done < <(find "$source_dir" -type f \
            ! -name '.DS_Store' \
            ! -name '.localized' \
            ! -name '._*' \
            ! -path '*/.git/*' \
            ! -path '*/venv/*' \
            ! -path '*/__pycache__/*' \
            -print0 2>/dev/null)
    done

    log_success "Manifest generated with $(grep -c '^PLANNED\|^CONFLICT\|^DUPLICATE\|^LARGE' "$manifest_file") entries"
}

# ============================================================================
# SECTION: SCRIPT GENERATION
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: generate_execute_script
# PURPOSE:  Create the migration execution script
# ARGS:     $1 = script file path
#           $2 = manifest file path
# ----------------------------------------------------------------------------
generate_execute_script()
{
    local script_file="$1"
    local manifest_file="$2"

    log_info "Generating execute script: $script_file"

    # Write script header
    cat > "$script_file" << 'HEADER'
#!/bin/bash
# ============================================================================
# FILE:        execute.sh (auto-generated)
# PURPOSE:     Execute the file reorganization
# DESCRIPTION: This script performs all the file moves defined in the manifest.
#              It runs in DRY-RUN mode by default for safety.
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
if [[ "$1" == "--execute" ]]
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

    # Add move commands from manifest
    echo "" >> "$script_file"
    echo "# ============================================================================" >> "$script_file"
    echo "# FILE MOVES" >> "$script_file"
    echo "# ============================================================================" >> "$script_file"
    echo "" >> "$script_file"

    # Read manifest and generate move commands
    while IFS='|' read -r status source dest notes
    do
        # Skip header lines and non-planned entries
        [[ "$status" =~ ^# ]] && continue
        [[ "$status" != "PLANNED" ]] && continue
        [[ -z "$source" ]] && continue

        # Escape special characters in paths for safe embedding
        local escaped_source="${source//\\/\\\\}"
        escaped_source="${escaped_source//\"/\\\"}"
        escaped_source="${escaped_source//\$/\\\$}"
        escaped_source="${escaped_source//\`/\\\`}"

        local escaped_dest="${dest//\\/\\\\}"
        escaped_dest="${escaped_dest//\"/\\\"}"
        escaped_dest="${escaped_dest//\$/\\\$}"
        escaped_dest="${escaped_dest//\`/\\\`}"

        local escaped_basename
        escaped_basename=$(basename "$source")
        escaped_basename="${escaped_basename//\\/\\\\}"
        escaped_basename="${escaped_basename//\"/\\\"}"

        # Write the move command
        cat >> "$script_file" << EOF

# Move: $escaped_basename
if [[ -f "$escaped_source" ]]
then
    dest_dir="\$(dirname "$escaped_dest")"
    if [[ "\$DRY_RUN" -eq 1 ]]
    then
        echo "[DRY RUN] Would move: $escaped_basename"
    else
        mkdir -p "\$dest_dir"
        if mv "$escaped_source" "$escaped_dest"
        then
            log "MOVED: $escaped_source -> $escaped_dest"
            ((moved++))
        else
            log "FAILED: $escaped_source"
            ((failed++))
        fi
    fi
else
    log "SKIPPED (not found): $escaped_source"
    ((skipped++))
fi
EOF

    done < "$manifest_file"

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

    # Make executable
    chmod +x "$script_file"

    log_success "Execute script generated"
}

# ----------------------------------------------------------------------------
# FUNCTION: generate_reversal_script
# PURPOSE:  Create a script to undo all moves
# ARGS:     $1 = script file path
#           $2 = manifest file path
# ----------------------------------------------------------------------------
generate_reversal_script()
{
    local script_file="$1"
    local manifest_file="$2"

    log_info "Generating reversal script: $script_file"

    # Write script header
    cat > "$script_file" << 'HEADER'
#!/bin/bash
# ============================================================================
# FILE:        reversal.sh (auto-generated)
# PURPOSE:     Undo the file reorganization
# DESCRIPTION: This script moves files back to their original locations.
#
# USAGE:       ./reversal.sh
#
# NOTE:        This script reverses moves in reverse order (LIFO)
# ============================================================================

set -e

echo "=============================================="
echo "REVERSAL SCRIPT"
echo "=============================================="
echo ""
echo "This will move files back to their original locations."
read -p "Are you sure? Type 'yes' to proceed: " confirm
if [[ "$confirm" != "yes" ]]
then
    echo "Aborted."
    exit 0
fi

echo ""

HEADER

    # Read manifest in reverse and generate reversal commands
    # Using tail -r on macOS, tac on Linux, or awk as fallback
    local reversed_content
    if command -v tac &> /dev/null
    then
        reversed_content=$(tac "$manifest_file")
    elif tail -r /dev/null &> /dev/null
    then
        reversed_content=$(tail -r "$manifest_file")
    else
        # awk fallback for reversing lines
        reversed_content=$(awk '{a[NR]=$0} END {for(i=NR;i>=1;i--) print a[i]}' "$manifest_file")
    fi

    while IFS='|' read -r status source dest notes
    do
        [[ "$status" =~ ^# ]] && continue
        [[ "$status" != "PLANNED" ]] && continue
        [[ -z "$source" ]] && continue

        # Escape special characters
        local escaped_source="${source//\\/\\\\}"
        escaped_source="${escaped_source//\"/\\\"}"
        escaped_source="${escaped_source//\$/\\\$}"

        local escaped_dest="${dest//\\/\\\\}"
        escaped_dest="${escaped_dest//\"/\\\"}"
        escaped_dest="${escaped_dest//\$/\\\$}"

        local escaped_basename
        escaped_basename=$(basename "$source")

        local source_dir
        source_dir=$(dirname "$source")
        local escaped_source_dir="${source_dir//\\/\\\\}"
        escaped_source_dir="${escaped_source_dir//\"/\\\"}"

        cat >> "$script_file" << EOF
# Reverse: $escaped_basename
if [[ -f "$escaped_dest" ]]
then
    mkdir -p "$escaped_source_dir"
    mv "$escaped_dest" "$escaped_source" && echo "Restored: $escaped_basename"
fi
EOF

    done <<< "$reversed_content"

    cat >> "$script_file" << 'FOOTER'

echo ""
echo "Reversal complete!"
FOOTER

    chmod +x "$script_file"

    log_success "Reversal script generated"
}

# ============================================================================
# SECTION: BACKUP GENERATION
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: generate_backup
# PURPOSE:  Create a tar.gz backup of source directories
# ARGS:     $1 = backup file path (without extension)
#           $2... = directories to backup
# ----------------------------------------------------------------------------
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

    # Create backup
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

    # Parse command line arguments
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

    # Validate inputs
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

    # Set up output files
    OUTPUT_DIR="${OUTPUT_DIR:-.}"
    MANIFEST_FILE="${OUTPUT_DIR}/manifest_${TIMESTAMP}.txt"
    EXECUTE_SCRIPT="${OUTPUT_DIR}/execute_${TIMESTAMP}.sh"
    REVERSAL_SCRIPT="${OUTPUT_DIR}/reversal_${TIMESTAMP}.sh"
    BACKUP_FILE="${OUTPUT_DIR}/backup_${TIMESTAMP}"

    echo "Configuration:"
    echo "  Target:  $target_dir"
    echo "  Sources: ${source_dirs[*]}"
    echo "  Output:  $OUTPUT_DIR"
    echo ""

    # Load mappings
    if [[ -n "$mapping_file" ]]
    then
        load_mapping_file "$mapping_file"
    else
        load_default_mappings
    fi

    # Generate all artifacts
    generate_manifest "$MANIFEST_FILE" "$target_dir" "${source_dirs[@]}"
    generate_execute_script "$EXECUTE_SCRIPT" "$MANIFEST_FILE"
    generate_reversal_script "$REVERSAL_SCRIPT" "$MANIFEST_FILE"
    generate_backup "$BACKUP_FILE" "${source_dirs[@]}"

    # Summary
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
