#!/bin/bash
# ============================================================================
# FILE:        propose.sh
# PURPOSE:     Phase 2 - Propose a folder structure for reorganization
# DESCRIPTION: This script helps the user define or choose a target folder
#              structure. It offers three approaches:
#              1. Auto-analyze: Suggest structure based on file types found
#              2. Templates: Choose from pre-built structure templates
#              3. Custom: Define your own structure interactively
#
# USAGE:       ./propose.sh <target_dir> [--template <name>] [--auto] [--custom]
#
# OUTPUT:      Prints proposed structure to stdout
#              Writes structure definition to file for next phase
#
# NOTE:        This is a READ-ONLY phase. No files are modified.
# ============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the utility functions
source "${SCRIPT_DIR}/utils.sh"

# Templates directory (relative to script location)
TEMPLATES_DIR="${SCRIPT_DIR}/../templates"

# ============================================================================
# SECTION: STRUCTURE TEMPLATES
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: load_template
# PURPOSE:  Load a structure template from file
# ARGS:     $1 = template name (without extension)
# OUTPUT:   Prints template content to stdout
# ----------------------------------------------------------------------------
load_template() {
    local template_name="$1"
    local template_file="${TEMPLATES_DIR}/structure_${template_name}.txt"

    if [[ ! -f "$template_file" ]]; then
        log_error "Template not found: $template_name"
        log_info "Available templates:"
        list_templates
        return 1
    fi

    cat "$template_file"
}

# ----------------------------------------------------------------------------
# FUNCTION: list_templates
# PURPOSE:  List all available structure templates
# ----------------------------------------------------------------------------
list_templates() {
    echo "Available templates:"
    for template in "${TEMPLATES_DIR}"/structure_*.txt; do
        if [[ -f "$template" ]]; then
            local name
            name=$(basename "$template" .txt | sed 's/structure_//')
            echo "  - $name"
        fi
    done
}

# ============================================================================
# SECTION: AUTO-ANALYSIS
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: analyze_file_types
# PURPOSE:  Analyze an analysis export file to understand what types of
#           files are present, then suggest a structure
# ARGS:     $1 = analysis export file path
# OUTPUT:   Prints suggested structure based on file types
# ----------------------------------------------------------------------------
analyze_file_types() {
    local analysis_file="$1"

    log_info "Analyzing file types to suggest structure..."

    # Count files by extension
    declare -A ext_counts

    # Read the analysis file and count extensions
    while IFS='|' read -r type data; do
        if [[ "$type" == "FILE" ]]; then
            # Extract file extension (lowercase)
            local ext
            ext=$(echo "${data##*.}" | tr '[:upper:]' '[:lower:]')
            ext_counts[$ext]=$((${ext_counts[$ext]:-0} + 1))
        fi
    done < "$analysis_file"

    # Categorize extensions into groups
    local has_documents=0
    local has_images=0
    local has_audio=0
    local has_video=0
    local has_code=0
    local has_archives=0
    local has_data=0

    for ext in "${!ext_counts[@]}"; do
        case "$ext" in
            pdf|doc|docx|txt|rtf|pages|odt|xls|xlsx|ppt|pptx)
                has_documents=1 ;;
            jpg|jpeg|png|gif|heic|webp|svg|bmp|tiff|raw)
                has_images=1 ;;
            mp3|wav|m4a|aac|flac|ogg|aiff)
                has_audio=1 ;;
            mp4|mov|avi|mkv|wmv|flv|webm)
                has_video=1 ;;
            py|js|ts|sh|bash|rb|go|rs|java|c|cpp|h|swift)
                has_code=1 ;;
            zip|tar|gz|rar|7z|dmg|pkg)
                has_archives=1 ;;
            csv|json|xml|yaml|yml|sql|db)
                has_data=1 ;;
        esac
    done

    # Generate suggested structure based on what we found
    echo "# Auto-generated structure based on file analysis"
    echo "# Modify as needed before proceeding"
    echo ""

    if [[ $has_documents -eq 1 ]]; then
        echo "Documents/"
        echo "Documents/Personal/"
        echo "Documents/Professional/"
        echo "Documents/Financial/"
    fi

    if [[ $has_images -eq 1 ]]; then
        echo "Media/"
        echo "Media/Images/"
        echo "Media/Images/Photos/"
        echo "Media/Images/Screenshots/"
    fi

    if [[ $has_audio -eq 1 ]]; then
        echo "Media/Audio/"
    fi

    if [[ $has_video -eq 1 ]]; then
        echo "Media/Video/"
    fi

    if [[ $has_code -eq 1 ]]; then
        echo "Projects/"
        echo "Projects/Code/"
    fi

    if [[ $has_archives -eq 1 ]]; then
        echo "Archives/"
        echo "Archives/Software/"
    fi

    if [[ $has_data -eq 1 ]]; then
        echo "Archives/Data/"
    fi

    echo ""
    echo "# File type summary:"
    for ext in "${!ext_counts[@]}"; do
        echo "# .$ext: ${ext_counts[$ext]} files"
    done | sort -t':' -k2 -nr | head -20
}

# ============================================================================
# SECTION: CUSTOM STRUCTURE INPUT
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: get_custom_structure
# PURPOSE:  Interactively get a custom structure from the user
# OUTPUT:   Prints structure definition
# NOTE:     This function is designed to work with Claude Code, which can
#           gather this information conversationally
# ----------------------------------------------------------------------------
get_custom_structure() {
    log_info "Define your custom folder structure"
    echo ""
    echo "Enter folder paths, one per line."
    echo "Use / to indicate hierarchy (e.g., 'Personal/Medical/')"
    echo "Enter an empty line when done."
    echo ""

    local structure=""
    while true; do
        read -r -p "Folder: " folder
        if [[ -z "$folder" ]]; then
            break
        fi
        # Ensure folder ends with /
        [[ "$folder" != */ ]] && folder="${folder}/"
        structure="${structure}${folder}"$'\n'
    done

    echo "$structure"
}

# ============================================================================
# SECTION: STRUCTURE VALIDATION
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: validate_structure
# PURPOSE:  Check that a proposed structure is valid
# ARGS:     $1 = structure definition (newline-separated folder paths)
# RETURNS:  0 if valid, 1 if invalid
# ----------------------------------------------------------------------------
validate_structure() {
    local structure="$1"

    # Check that we have at least one folder
    if [[ -z "$structure" ]]; then
        log_error "Structure is empty"
        return 1
    fi

    # Check for invalid characters
    if echo "$structure" | grep -qE '[<>:"|?*]'; then
        log_error "Structure contains invalid characters"
        return 1
    fi

    # Check that paths don't start with /
    if echo "$structure" | grep -qE '^/'; then
        log_warn "Paths should be relative, not absolute"
    fi

    log_success "Structure is valid"
    return 0
}

# ============================================================================
# SECTION: STRUCTURE DISPLAY
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: display_structure
# PURPOSE:  Display a structure in a tree-like format
# ARGS:     $1 = structure definition (newline-separated folder paths)
# ----------------------------------------------------------------------------
display_structure() {
    local structure="$1"

    echo -e "${BOLD}Proposed Folder Structure:${NC}"
    echo ""

    # Convert flat list to tree display
    echo "$structure" | grep -v '^#' | grep -v '^$' | sort | while read -r path; do
        # Count depth by counting slashes
        local depth
        depth=$(echo "$path" | tr -cd '/' | wc -c)

        # Create indentation
        local indent=""
        for ((i=1; i<depth; i++)); do
            indent="${indent}    "
        done

        # Get just the folder name (last component)
        local name
        name=$(echo "$path" | sed 's|/$||' | rev | cut -d'/' -f1 | rev)

        # Print with tree-like formatting
        if [[ $depth -eq 1 ]]; then
            echo "├── $name/"
        else
            echo "${indent}├── $name/"
        fi
    done

    echo ""
}

# ============================================================================
# SECTION: STRUCTURE EXPORT
# ============================================================================

# ----------------------------------------------------------------------------
# FUNCTION: export_structure
# PURPOSE:  Write structure definition to a file for the next phase
# ARGS:     $1 = output file path
#           $2 = target directory
#           $3 = structure definition
# ----------------------------------------------------------------------------
export_structure() {
    local output_file="$1"
    local target_dir="$2"
    local structure="$3"

    log_info "Exporting structure to: $output_file"

    {
        echo "# Structure Definition - $(get_timestamp)"
        echo "# This file defines the target folder structure for reorganization"
        echo ""
        echo "TARGET_DIR|$target_dir"
        echo ""
        echo "# Folders to create (relative to target)"
        echo "$structure" | grep -v '^#' | grep -v '^$' | while read -r path; do
            echo "FOLDER|$path"
        done
    } > "$output_file"

    log_success "Structure exported"
}

# ============================================================================
# SECTION: MAIN EXECUTION
# ============================================================================

main() {
    log_header "PHASE 2: PROPOSE STRUCTURE"

    local target_dir=""
    local mode="interactive"  # interactive, template, auto, custom
    local template_name=""
    local analysis_file=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --template)
                mode="template"
                template_name="$2"
                shift 2
                ;;
            --auto)
                mode="auto"
                shift
                ;;
            --custom)
                mode="custom"
                shift
                ;;
            --analysis)
                analysis_file="$2"
                shift 2
                ;;
            --list-templates)
                list_templates
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                target_dir="$1"
                shift
                ;;
        esac
    done

    # Validate target directory is specified
    if [[ -z "$target_dir" ]]; then
        log_error "Usage: $0 <target_dir> [--template <name>] [--auto] [--custom]"
        log_error ""
        log_error "Options:"
        log_error "  --template <name>  Use a pre-built template"
        log_error "  --auto             Auto-suggest based on file types"
        log_error "  --custom           Define structure interactively"
        log_error "  --analysis <file>  Use analysis file for auto mode"
        log_error "  --list-templates   List available templates"
        exit 1
    fi

    echo "Target directory: $target_dir"
    echo ""

    local structure=""

    case "$mode" in
        template)
            log_info "Loading template: $template_name"
            structure=$(load_template "$template_name")
            if [[ $? -ne 0 ]]; then
                exit 1
            fi
            ;;

        auto)
            if [[ -z "$analysis_file" ]]; then
                log_error "Auto mode requires --analysis <file>"
                exit 1
            fi
            structure=$(analyze_file_types "$analysis_file")
            ;;

        custom)
            structure=$(get_custom_structure)
            ;;

        interactive)
            echo "How would you like to define your folder structure?"
            echo ""
            echo "  1. Use a template (recommended for most users)"
            echo "  2. Auto-suggest based on file types"
            echo "  3. Define custom structure"
            echo ""
            read -r -p "Choice [1-3]: " choice

            case "$choice" in
                1)
                    list_templates
                    read -r -p "Template name: " template_name
                    structure=$(load_template "$template_name")
                    ;;
                2)
                    if [[ -z "$analysis_file" ]]; then
                        log_warn "No analysis file provided. Run analyze.sh first for best results."
                        # Provide a basic structure
                        structure="Documents/
Media/
Archives/"
                    else
                        structure=$(analyze_file_types "$analysis_file")
                    fi
                    ;;
                3)
                    structure=$(get_custom_structure)
                    ;;
                *)
                    log_error "Invalid choice"
                    exit 1
                    ;;
            esac
            ;;
    esac

    # Validate the structure
    if ! validate_structure "$structure"; then
        exit 1
    fi

    # Display the structure
    display_structure "$structure"

    # Export for next phase
    if [[ -n "$OUTPUT_DIR" ]]; then
        export_structure "${OUTPUT_DIR}/structure_$(get_timestamp).txt" "$target_dir" "$structure"
    fi

    log_success "Structure proposal complete!"
    echo ""
    echo "If this structure looks good, proceed to Phase 3 (generate_plan.sh)"
}

main "$@"
