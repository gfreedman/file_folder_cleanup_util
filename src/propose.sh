#!/bin/bash
# Phase 2: Read-only — define the target folder structure via template, auto-analysis, or custom input.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

set -e

TEMPLATES_DIR="${SCRIPT_DIR}/../templates"

load_template()
{
    local template_name="$1"
    local template_file="${TEMPLATES_DIR}/structure_${template_name}.txt"

    if [[ ! -f "$template_file" ]]
    then
        log_error "Template not found: $template_name"
        log_info "Available templates:"
        list_templates
        return 1
    fi

    cat "$template_file"
}

list_templates()
{
    echo "Available templates:"
    for template in "${TEMPLATES_DIR}"/structure_*.txt
    do
        if [[ -f "$template" ]]
        then
            local name
            name=$(basename "$template" .txt | sed 's/structure_//')
            echo "  - $name"
        fi
    done
}

analyze_file_types()
{
    local analysis_file="$1"

    log_info "Analyzing file types to suggest structure..."

    declare -A ext_counts
    while IFS='|' read -r type data
    do
        if [[ "$type" == "FILE" ]]
        then
            local ext
            ext=$(echo "${data##*.}" | tr '[:upper:]' '[:lower:]')
            ext_counts[$ext]=$((${ext_counts[$ext]:-0} + 1))
        fi
    done < "$analysis_file"

    local has_documents=0
    local has_images=0
    local has_audio=0
    local has_video=0
    local has_code=0
    local has_archives=0
    local has_data=0

    for ext in "${!ext_counts[@]}"
    do
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

    echo "# Auto-generated structure based on file analysis"
    echo "# Modify as needed before proceeding"
    echo ""

    if [[ $has_documents -eq 1 ]]
    then
        echo "Documents/"
        echo "Documents/Personal/"
        echo "Documents/Professional/"
        echo "Documents/Financial/"
    fi

    if [[ $has_images -eq 1 ]]
    then
        echo "Media/"
        echo "Media/Images/"
        echo "Media/Images/Photos/"
        echo "Media/Images/Screenshots/"
    fi

    if [[ $has_audio -eq 1 ]]
    then
        echo "Media/Audio/"
    fi

    if [[ $has_video -eq 1 ]]
    then
        echo "Media/Video/"
    fi

    if [[ $has_code -eq 1 ]]
    then
        echo "Projects/"
        echo "Projects/Code/"
    fi

    if [[ $has_archives -eq 1 ]]
    then
        echo "Archives/"
        echo "Archives/Software/"
    fi

    if [[ $has_data -eq 1 ]]
    then
        echo "Archives/Data/"
    fi

    echo ""
    echo "# File type summary:"
    for ext in "${!ext_counts[@]}"
    do
        echo "# .$ext: ${ext_counts[$ext]} files"
    done | sort -t':' -k2 -nr | head -20
}

get_custom_structure()
{
    log_info "Define your custom folder structure"
    echo ""
    echo "Enter folder paths, one per line."
    echo "Use / to indicate hierarchy (e.g., 'Personal/Medical/')"
    echo "Enter an empty line when done."
    echo ""

    local structure=""
    while true
    do
        read -r -p "Folder: " folder
        if [[ -z "$folder" ]]
        then
            break
        fi
        [[ "$folder" != */ ]] && folder="${folder}/"
        structure="${structure}${folder}"$'\n'
    done

    echo "$structure"
}

validate_structure()
{
    local structure="$1"

    if [[ -z "$structure" ]]
    then
        log_error "Structure is empty"
        return 1
    fi

    if echo "$structure" | grep -qE '[<>:"|?*]'
    then
        log_error "Structure contains invalid characters"
        return 1
    fi

    if echo "$structure" | grep -qE '^/'
    then
        log_warn "Paths should be relative, not absolute"
    fi

    log_success "Structure is valid"
    return 0
}

display_structure()
{
    local structure="$1"

    echo -e "${BOLD}Proposed Folder Structure:${NC}"
    echo ""

    echo "$structure" | grep -v '^#' | grep -v '^$' | sort | while read -r path
    do
        local depth
        depth=$(echo "$path" | tr -cd '/' | wc -c)

        local indent=""
        for ((i=1; i<depth; i++))
        do
            indent="${indent}    "
        done

        local name
        name=$(echo "$path" | sed 's|/$||' | rev | cut -d'/' -f1 | rev)

        if [[ $depth -eq 1 ]]
        then
            echo "├── $name/"
        else
            echo "${indent}├── $name/"
        fi
    done

    echo ""
}

export_structure()
{
    local output_file="$1"
    local target_dir="$2"
    local structure="$3"

    log_info "Exporting structure to: $output_file"

    {
        echo "# Structure Definition - $(get_timestamp)"
        echo ""
        echo "TARGET_DIR|$target_dir"
        echo ""
        echo "$structure" | grep -v '^#' | grep -v '^$' | while read -r path
        do
            echo "FOLDER|$path"
        done
    } > "$output_file"

    log_success "Structure exported"
}

main()
{
    log_header "PHASE 2: PROPOSE STRUCTURE"

    local target_dir=""
    local mode="interactive"
    local template_name=""
    local analysis_file=""

    while [[ $# -gt 0 ]]
    do
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

    if [[ -z "$target_dir" ]]
    then
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
            if ! structure=$(load_template "$template_name")
            then
                exit 1
            fi
            ;;

        auto)
            if [[ -z "$analysis_file" ]]
            then
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
                    if ! structure=$(load_template "$template_name")
                    then
                        exit 1
                    fi
                    ;;
                2)
                    if [[ -z "$analysis_file" ]]
                    then
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

    if ! validate_structure "$structure"
    then
        exit 1
    fi

    display_structure "$structure"

    # Structure is displayed for user review and confirmed interactively.
    # Nothing downstream reads a structure file — no export needed.

    log_success "Structure proposal complete!"
    echo ""
    echo "If this structure looks good, proceed to Phase 3 (generate_plan.sh)"
}

main "$@"
