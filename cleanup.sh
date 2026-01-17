#!/bin/bash
# ============================================================================
# FILE:        cleanup.sh
# PURPOSE:     Main entry point for the File Folder Cleanup Utility
# DESCRIPTION: This script orchestrates the complete cleanup workflow,
#              running all four phases in sequence. It can also run
#              individual phases as needed.
#
# USAGE:       ./cleanup.sh --sources ~/Desktop,~/Downloads --target ~/Documents
#              ./cleanup.sh --phase analyze --sources ~/Desktop,~/Downloads
#              ./cleanup.sh --help
#
# NOTE:        This tool is designed to work with Claude Code for an
#              interactive, conversational experience.
# ============================================================================

# Get the directory where this script is located
# This allows us to find other scripts regardless of where cleanup.sh is called from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the utility functions for logging
source "${SCRIPT_DIR}/src/utils.sh"

# ============================================================================
# SECTION: HELP AND VERSION
# ============================================================================

VERSION="1.0.0"

show_help() {
    cat << 'EOF'
File Folder Cleanup Utility
===========================

A safe, interactive tool for consolidating and reorganizing files.

USAGE:
    cleanup.sh [OPTIONS]

OPTIONS:
    --sources <dirs>     Comma-separated list of source directories
                         Example: --sources ~/Desktop,~/Downloads

    --target <dir>       Target directory for consolidated files
                         Example: --target ~/Documents

    --template <name>    Use a structure template (personal, business, minimal)
                         Example: --template personal

    --phase <phase>      Run only a specific phase
                         Phases: analyze, propose, generate, execute
                         Example: --phase analyze

    --output <dir>       Directory for output files (default: current directory)
                         Example: --output ~/Documents

    --dry-run            Preview changes without making them (default)

    --execute            Actually perform the file moves

    --help               Show this help message

    --version            Show version number

EXAMPLES:
    # Full workflow with interactive prompts
    ./cleanup.sh --sources ~/Desktop,~/Downloads --target ~/Documents

    # Use a template structure
    ./cleanup.sh --sources ~/Desktop --target ~/Documents --template personal

    # Run only analysis phase
    ./cleanup.sh --phase analyze --sources ~/Desktop,~/Downloads

    # Execute a previously generated script
    ./cleanup.sh --phase execute --script ./execute_2026-01-16.sh

PHASES:
    1. analyze   - Scan source folders, find duplicates, conflicts
    2. propose   - Define or choose target folder structure
    3. generate  - Create manifest, migration scripts, backup
    4. execute   - Run migration (dry-run by default)

For detailed documentation, see README.md
For Claude Code integration, see CLAUDE.md
EOF
}

show_version() {
    echo "File Folder Cleanup Utility v${VERSION}"
}

# ============================================================================
# SECTION: ARGUMENT PARSING
# ============================================================================

# Default values
SOURCES=""
TARGET=""
TEMPLATE=""
PHASE="all"
OUTPUT_DIR="."
EXECUTE_MODE="dry-run"
EXECUTE_SCRIPT=""

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sources)
                SOURCES="$2"
                shift 2
                ;;
            --target)
                TARGET="$2"
                shift 2
                ;;
            --template)
                TEMPLATE="$2"
                shift 2
                ;;
            --phase)
                PHASE="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --dry-run)
                EXECUTE_MODE="dry-run"
                shift
                ;;
            --execute)
                EXECUTE_MODE="execute"
                shift
                ;;
            --script)
                EXECUTE_SCRIPT="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# SECTION: VALIDATION
# ============================================================================

validate_inputs() {
    # For analyze phase, only sources are required
    if [[ "$PHASE" == "analyze" ]]; then
        if [[ -z "$SOURCES" ]]; then
            log_error "Source directories required. Use --sources dir1,dir2"
            exit 1
        fi
        return 0
    fi

    # For execute phase with script, only script is required
    if [[ "$PHASE" == "execute" && -n "$EXECUTE_SCRIPT" ]]; then
        if [[ ! -f "$EXECUTE_SCRIPT" ]]; then
            log_error "Execute script not found: $EXECUTE_SCRIPT"
            exit 1
        fi
        return 0
    fi

    # For full workflow or generate phase, both sources and target required
    if [[ "$PHASE" == "all" || "$PHASE" == "generate" ]]; then
        if [[ -z "$SOURCES" ]]; then
            log_error "Source directories required. Use --sources dir1,dir2"
            exit 1
        fi
        if [[ -z "$TARGET" ]]; then
            log_error "Target directory required. Use --target dir"
            exit 1
        fi
    fi
}

# ============================================================================
# SECTION: PHASE RUNNERS
# ============================================================================

run_analyze() {
    log_header "Running Phase 1: Analyze"

    # Convert comma-separated sources to space-separated for the script
    local sources_array
    IFS=',' read -ra sources_array <<< "$SOURCES"

    bash "${SCRIPT_DIR}/src/analyze.sh" "${sources_array[@]}"
}

run_propose() {
    log_header "Running Phase 2: Propose Structure"

    local template_arg=""
    if [[ -n "$TEMPLATE" ]]; then
        template_arg="--template $TEMPLATE"
    fi

    bash "${SCRIPT_DIR}/src/propose.sh" "$TARGET" $template_arg
}

run_generate() {
    log_header "Running Phase 3: Generate Plan"

    bash "${SCRIPT_DIR}/src/generate_plan.sh" \
        --sources "$SOURCES" \
        --target "$TARGET" \
        --output "$OUTPUT_DIR"
}

run_execute() {
    log_header "Running Phase 4: Execute"

    if [[ -n "$EXECUTE_SCRIPT" ]]; then
        # Run specific script
        bash "${SCRIPT_DIR}/src/execute.sh" "$EXECUTE_SCRIPT" --$EXECUTE_MODE
    else
        # Find the most recent execute script in output dir
        local latest_script
        latest_script=$(ls -t "${OUTPUT_DIR}"/execute_*.sh 2>/dev/null | head -1)

        if [[ -z "$latest_script" ]]; then
            log_error "No execute script found in $OUTPUT_DIR"
            log_info "Run --phase generate first, or specify --script <path>"
            exit 1
        fi

        log_info "Using most recent execute script: $latest_script"
        bash "${SCRIPT_DIR}/src/execute.sh" "$latest_script" --$EXECUTE_MODE
    fi
}

# ============================================================================
# SECTION: MAIN WORKFLOW
# ============================================================================

run_full_workflow() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           FILE FOLDER CLEANUP UTILITY v${VERSION}                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "This utility will help you consolidate and organize your files."
    echo ""
    echo "Configuration:"
    echo "  Sources: $SOURCES"
    echo "  Target:  $TARGET"
    echo "  Output:  $OUTPUT_DIR"
    [[ -n "$TEMPLATE" ]] && echo "  Template: $TEMPLATE"
    echo ""

    # Phase 1: Analyze
    run_analyze

    echo ""
    read -p "Continue to structure proposal? [Y/n]: " continue_propose
    if [[ "$continue_propose" == "n" || "$continue_propose" == "N" ]]; then
        log_info "Stopped after analysis. Run with --phase propose to continue."
        exit 0
    fi

    # Phase 2: Propose
    run_propose

    echo ""
    read -p "Continue to generate migration plan? [Y/n]: " continue_generate
    if [[ "$continue_generate" == "n" || "$continue_generate" == "N" ]]; then
        log_info "Stopped after proposal. Run with --phase generate to continue."
        exit 0
    fi

    # Phase 3: Generate
    run_generate

    echo ""
    read -p "Continue to execute (dry-run first)? [Y/n]: " continue_execute
    if [[ "$continue_execute" == "n" || "$continue_execute" == "N" ]]; then
        log_info "Stopped after generation. Run with --phase execute to continue."
        exit 0
    fi

    # Phase 4: Execute (dry-run first)
    EXECUTE_MODE="dry-run"
    run_execute

    echo ""
    read -p "Execute for real? [y/N]: " do_execute
    if [[ "$do_execute" == "y" || "$do_execute" == "Y" ]]; then
        EXECUTE_MODE="execute"
        run_execute
    else
        log_info "Dry run complete. Run with --execute to perform actual moves."
    fi
}

# ============================================================================
# SECTION: MAIN ENTRY POINT
# ============================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Validate inputs
    validate_inputs

    # Export OUTPUT_DIR for child scripts
    export CLEANUP_OUTPUT_DIR="$OUTPUT_DIR"

    # Run appropriate phase(s)
    case "$PHASE" in
        analyze)
            run_analyze
            ;;
        propose)
            run_propose
            ;;
        generate)
            run_generate
            ;;
        execute)
            run_execute
            ;;
        all)
            run_full_workflow
            ;;
        *)
            log_error "Unknown phase: $PHASE"
            echo "Valid phases: analyze, propose, generate, execute, all"
            exit 1
            ;;
    esac
}

# Run main function with all command line arguments
main "$@"
