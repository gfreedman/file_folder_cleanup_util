#!/bin/bash
# ============================================================================
# FILE:        execute.sh
# PURPOSE:     Phase 4 - Execute the migration (wrapper script)
# DESCRIPTION: This is a convenience wrapper that runs the generated
#              execute script from Phase 3. It provides additional safety
#              checks and can run in dry-run or execute mode.
#
# USAGE:       ./execute.sh <generated_script.sh> [--dry-run|--execute]
#
# NOTE:        The actual move logic is in the generated script.
#              This wrapper adds pre-flight checks and post-flight verification.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# ============================================================================
# SECTION: PRE-FLIGHT CHECKS
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: verify_backup_exists
# PURPOSE:  Check that a backup was created before execution
# ARGS:     $1 = expected backup file path
# RETURNS:  0 if backup exists, 1 if not
# ----------------------------------------------------------------------------
verify_backup_exists()
{
    local backup_pattern="$1"

    # Look for backup files matching the pattern
    local backup_files
    backup_files=$(ls ${backup_pattern}*.tar.gz 2>/dev/null | head -1)

    if [[ -z "$backup_files" ]]
    then
        log_warn "No backup file found matching: ${backup_pattern}*.tar.gz"
        return 1
    fi

    log_success "Backup verified: $backup_files"
    return 0
}

# ----------------------------------------------------------------------------
# FUNCTION: verify_manifest_exists
# PURPOSE:  Check that the manifest file exists
# ARGS:     $1 = manifest file path
# RETURNS:  0 if exists, 1 if not
# ----------------------------------------------------------------------------
verify_manifest_exists()
{
    local manifest_file="$1"

    if [[ ! -f "$manifest_file" ]]
    then
        log_error "Manifest not found: $manifest_file"
        return 1
    fi

    local planned_count
    planned_count=$(grep -c '^PLANNED|' "$manifest_file" 2>/dev/null || echo "0")
    log_info "Manifest contains $planned_count planned moves"
    return 0
}

# ============================================================================
# SECTION: POST-FLIGHT VERIFICATION
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: verify_execution
# PURPOSE:  Check that files were moved correctly
# ARGS:     $1 = manifest file path
# ----------------------------------------------------------------------------
verify_execution()
{
    local manifest_file="$1"

    log_info "Verifying execution..."

    local expected=0
    local found=0
    local missing=0

    while IFS='|' read -r status source dest notes
    do
        [[ "$status" != "PLANNED" ]] && continue
        [[ -z "$dest" ]] && continue

        expected=$((expected + 1))

        if [[ -f "$dest" ]]
        then
            found=$((found + 1))
        else
            missing=$((missing + 1))
            log_warn "Missing at destination: $dest"
        fi
    done < "$manifest_file"

    echo ""
    echo "Verification Results:"
    echo "  Expected: $expected files"
    echo "  Found:    $found files"
    echo "  Missing:  $missing files"

    if [[ $missing -eq 0 ]]
    then
        log_success "All files moved successfully!"
        return 0
    else
        log_warn "Some files were not moved. Check the log for details."
        return 1
    fi
}

# ============================================================================
# SECTION: CLEANUP
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: cleanup_empty_directories
# PURPOSE:  Remove empty directories from source locations
# ARGS:     $1 = manifest file path
# ----------------------------------------------------------------------------
cleanup_empty_directories()
{
    local manifest_file="$1"

    log_info "Cleaning up empty directories..."

    # Extract unique source directories from manifest
    local source_dirs
    source_dirs=$(grep '^SOURCE_DIRS|' "$manifest_file" | cut -d'|' -f2)

    for dir in $source_dirs
    do
        if [[ -d "$dir" ]]
        then
            # Remove empty directories recursively
            find "$dir" -type d -empty -delete 2>/dev/null
            log_info "Cleaned up: $dir"
        fi
    done

    log_success "Cleanup complete"
}

# ============================================================================
# SECTION: MAIN EXECUTION
# ============================================================================

main()
{
    log_header "PHASE 4: EXECUTE MIGRATION"

    local execute_script=""
    local mode="dry-run"
    local manifest_file=""
    local skip_backup_check=0

    # Parse arguments
    while [[ $# -gt 0 ]]
    do
        case "$1" in
            --dry-run)
                mode="dry-run"
                shift
                ;;
            --execute)
                mode="execute"
                shift
                ;;
            --manifest)
                manifest_file="$2"
                shift 2
                ;;
            --skip-backup-check)
                skip_backup_check=1
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                execute_script="$1"
                shift
                ;;
        esac
    done

    # Validate execute script
    if [[ -z "$execute_script" ]]
    then
        log_error "Usage: $0 <execute_script.sh> [--dry-run|--execute]"
        exit 1
    fi

    if [[ ! -f "$execute_script" ]]
    then
        log_error "Execute script not found: $execute_script"
        exit 1
    fi

    # Infer manifest file if not provided
    if [[ -z "$manifest_file" ]]
    then
        # Try to find manifest with same timestamp
        local base_name
        base_name=$(basename "$execute_script" .sh | sed 's/execute_//')
        manifest_file="$(dirname "$execute_script")/manifest_${base_name}.txt"

        if [[ ! -f "$manifest_file" ]]
        then
            log_warn "Could not find manifest file. Skipping verification."
            manifest_file=""
        fi
    fi

    echo "Execute script: $execute_script"
    echo "Mode: $mode"
    [[ -n "$manifest_file" ]] && echo "Manifest: $manifest_file"
    echo ""

    # Pre-flight checks
    if [[ "$mode" == "execute" ]]
    then
        log_info "Running pre-flight checks..."

        # Check backup exists (unless skipped)
        if [[ $skip_backup_check -eq 0 ]]
        then
            local backup_pattern
            backup_pattern=$(dirname "$execute_script")/backup_
            if ! verify_backup_exists "$backup_pattern"
            then
                echo ""
                read -p "No backup found. Continue anyway? [y/N]: " confirm
                if [[ "$confirm" != "y" && "$confirm" != "Y" ]]
                then
                    log_info "Aborted. Create a backup first."
                    exit 0
                fi
            fi
        fi

        # Verify manifest
        if [[ -n "$manifest_file" ]]
        then
            verify_manifest_exists "$manifest_file"
        fi

        echo ""
    fi

    # Run the execute script
    log_info "Running execute script..."
    echo ""

    if [[ "$mode" == "dry-run" ]]
    then
        bash "$execute_script"
    else
        bash "$execute_script" --execute
    fi

    local exit_code=$?

    # Post-flight actions (only if actually executed)
    if [[ "$mode" == "execute" && $exit_code -eq 0 ]]
    then
        echo ""

        # Verify execution
        if [[ -n "$manifest_file" ]]
        then
            verify_execution "$manifest_file"
        fi

        # Cleanup empty directories
        if [[ -n "$manifest_file" ]]
        then
            echo ""
            read -p "Clean up empty source directories? [y/N]: " cleanup
            if [[ "$cleanup" == "y" || "$cleanup" == "Y" ]]
            then
                cleanup_empty_directories "$manifest_file"
            fi
        fi
    fi

    log_header "EXECUTION COMPLETE"

    if [[ "$mode" == "dry-run" ]]
    then
        echo "This was a dry run. No files were moved."
        echo ""
        echo "To execute for real:"
        echo "  $0 $execute_script --execute"
    fi
}

main "$@"
