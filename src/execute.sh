#!/bin/bash
# Phase 4 wrapper: pre-flight checks, runs generated execute script, post-flight verification.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

set -e

verify_manifest_integrity()
{
    local manifest_file="$1"
    local sidecar="${manifest_file}.sha256"
    local manifest_dir
    manifest_dir=$(dirname "$manifest_file")

    if [[ ! -f "$sidecar" ]]
    then
        log_warn "No integrity sidecar found (${sidecar}). Skipping verification."
        log_warn "This is expected for manifests generated before this version."
        return 0
    fi

    # Run shasum -c from the manifest directory so the relative path in the
    # sidecar (written by generate_plan.sh) resolves correctly.
    if (cd "$manifest_dir" && shasum -a 256 -c "$(basename "$sidecar")" > /dev/null 2>&1)
    then
        log_success "Manifest integrity verified"
        return 0
    else
        log_error "Manifest integrity check FAILED: $(basename "$manifest_file")"
        log_error "The manifest may have been modified after generation."
        log_error "Do not proceed. Re-run generate_plan.sh to create a fresh manifest."
        return 1
    fi
}

verify_backup_exists()
{
    local backup_pattern="$1"

    # Array glob avoids unquoted word-splitting on the pattern.
    local -a matches=( "${backup_pattern}"*.tar.gz )
    if [[ -f "${matches[0]:-}" ]]
    then
        log_success "Backup verified: ${matches[0]}"
        return 0
    fi

    log_warn "No backup file found matching: ${backup_pattern}*.tar.gz"
    return 1
}

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

cleanup_empty_directories()
{
    local manifest_file="$1"

    log_info "Cleaning up empty directories..."

    local source_dirs_raw
    source_dirs_raw=$(grep '^SOURCE_DIRS|' "$manifest_file" | cut -d'|' -f2- || true)

    while IFS= read -r dir
    do
        [[ -z "$dir" ]] && continue
        if [[ -d "$dir" ]]
        then
            find "$dir" -type d -empty -delete 2>/dev/null
            log_info "Cleaned up: $dir"
        fi
    done < <(echo "$source_dirs_raw" | tr ' ' '\n')

    log_success "Cleanup complete"
}

main()
{
    log_header "PHASE 4: EXECUTE MIGRATION"

    local execute_script=""
    local mode="dry-run"
    local manifest_file=""
    local skip_backup_check=0

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

    # Infer manifest from the execute script's timestamp suffix.
    if [[ -z "$manifest_file" ]]
    then
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

    if [[ "$mode" == "execute" ]]
    then
        log_info "Running pre-flight checks..."

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

        if [[ -n "$manifest_file" ]]
        then
            verify_manifest_exists "$manifest_file"
            verify_manifest_integrity "$manifest_file"
        fi

        echo ""
    fi

    log_info "Running execute script..."
    echo ""

    if [[ "$mode" == "dry-run" ]]
    then
        bash "$execute_script"
    else
        bash "$execute_script" --execute
    fi

    local exit_code=$?

    if [[ "$mode" == "execute" && $exit_code -eq 0 ]]
    then
        echo ""

        if [[ -n "$manifest_file" ]]
        then
            verify_execution "$manifest_file"
        fi

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
