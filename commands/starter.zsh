# --- starter.zsh ---
#
# This script provides functions for managing and creating project starters
# within the 'buildme' tool. It allows users to list, create, initialize, and
# delete project starters, facilitating the setup of new projects with predefined
# templates.
#
# Features:
# - `buildme_starter_list`: Lists available built-in and custom project starters.
# - `buildme_starter_new`: Creates a new project from a specified starter template.
# - `buildme_starter_init`: Initializes a new starter from a directory or GitHub
#   repository, analyzing the project structure and dependencies.
# - `buildme_starter_delete`: Deletes an existing starter.
# - Supports extraction and cleaning of dependencies, identification of main files,
#   and generation of project templates.
#
# Usage:
# - Use `buildme starter list` to view available starters.
# - Use `buildme starter new <name> <target>` to create a new project.
# - Use `buildme starter init <name> <source>` to initialize a new starter.
# - Use `buildme starter delete <name>` to remove a starter.
#
# Dependencies:
# - Requires `git` for cloning repositories.
# - Uses `tree` or `find` for generating project structure treemaps.
# - Assumes access to the `buildme_generate` function for generating templates.

STARTER_DIR="$BUILDME_PLUGIN_DIR/starters"
USER_STARTER_DIR="$HOME/.buildme_starters"

mkdir -p "$USER_STARTER_DIR"

get_starter_path() {
    local name="$1"
    if [[ -d "$USER_STARTER_DIR/$name" ]]; then
        echo "$USER_STARTER_DIR/$name"
    elif [[ -d "$STARTER_DIR/$name" ]]; then
        echo "$STARTER_DIR/$name"
    else
        return 1
    fi
}

buildme_starter_list() {
    echo "📦 Available starters:"
    
    echo "\nBuilt-in starters:"
    if [[ -d "$STARTER_DIR" ]]; then
        if [[ -n "$(ls -A "$STARTER_DIR" 2>/dev/null)" ]]; then
            for starter in "$STARTER_DIR"/*; do
                [[ -d "$starter" ]] || continue
                name="${starter:t}"
                if [[ -f "$starter/metadata.yaml" ]]; then
                    desc=$(grep "^description:" "$starter/metadata.yaml" | cut -d: -f2- | sed 's/^ *//')
                    echo "• $name — ${desc:-No description}"
                else
                    echo "• $name"
                fi
            done
        else
            echo "No built-in starters available"
        fi
    fi
    
    echo "\nYour custom starters:"
    if [[ -d "$USER_STARTER_DIR" ]]; then
        if [[ -n "$(ls -A "$USER_STARTER_DIR" 2>/dev/null)" ]]; then
            for starter in "$USER_STARTER_DIR"/*; do
                [[ -d "$starter" ]] || continue
                name="${starter:t}"
                if [[ -f "$starter/metadata.yaml" ]]; then
                    desc=$(grep "^description:" "$starter/metadata.yaml" | cut -d: -f2- | sed 's/^ *//')
                    echo "• $name — ${desc:-No description}"
                else
                    echo "• $name"
                fi
            done
        else
            echo "No custom starters available"
        fi
    fi
}

buildme_starter_new() {
    local name="$1"
    local target="$2"
    shift 2
    
    local starter_path
    starter_path=$(get_starter_path "$name") || {
        echo "❌ Starter '$name' not found"
        return 1
    }
    
    local metadata="$starter_path/metadata.yaml"
    if [[ -f "$metadata" ]]; then
        local required_vars=()
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*([^[:space:]]+) ]]; then
                required_vars+=("${BASH_REMATCH[1]}")
            fi
        done < "$metadata"
        
        for var in "${required_vars[@]}"; do
            if ! [[ " $* " =~ " --$var=" ]]; then
                echo "❌ Missing required variable: $var"
                echo "Usage: buildme starter new $name <target> --$var=<value> [--other-var=<value>]"
                return 1
            fi
        done
    fi
    
    if [[ -f "$starter_path/template.sh" ]]; then
        zsh "$starter_path/template.sh" "$target" "$@"
    else
        echo "❌ No template.sh found in starter '$name'"
        return 1
    fi
}

extract_dependencies() {
    local dir="$1"
    local dep_files="$2"
    local all_deps=""

    while IFS= read -r dep_file; do
        [[ -z "$dep_file" ]] && continue
        
        local full_path="$dir/$dep_file"
        if [[ -f "$full_path" ]]; then
            echo "📖 Reading $dep_file..." >&2
            local content=$(cat "$full_path")
            all_deps="${all_deps}From $dep_file:\n${content}\n\n"
        else
            local parent_dir=$(dirname "$full_path")
            if [[ -d "$parent_dir" ]]; then
            fi
        fi
    done <<< "$dep_files"
    
    if [[ -z "$all_deps" ]]; then
        echo ""
        return
    fi
    
    local deps_prompt=$(cat <<EOF
Extract and clean the dependencies from the following files. Return ONLY the dependencies in the format:
- For Python: package==version (one per line)
- For Node.js: package@version (one per line)

Remove any comments, development-only dependencies (unless critical), and test dependencies.
Keep only production dependencies that are essential for the project structure.

$(echo -e "$all_deps")

Output ONLY the cleaned dependencies list, nothing else.
EOF
)
    
    local cleaned_deps=$(buildme_generate "$deps_prompt" "$(get_api_key "gpt")")
    echo "$cleaned_deps"
}

identify_main_files() {
    local dir="$1"
    local structure="$2"
    
    local files_prompt=$(cat <<EOF
Analyze this project structure and identify the MAIN/CORE files that define the project's architecture.
Look for:
- Entry points (main.py, index.js, app.py, server.js)
- Configuration files (config.py, settings.py, .env.example)
- Core business logic files
- API route definitions
- Database models
- Important utility files

Project structure:
$structure

Return ONLY the file paths (relative to project root), one per line.
Maximum 10 files. Prioritize the most important architectural files.
DO NOT include any shell commands, backticks, or code formatting.
Just plain file paths, one per line.

Example output:
backend/app/main.py
backend/app/config.py
frontend/src/index.js
EOF
)
    
    local main_files=$(buildme_generate "$files_prompt" "$(get_api_key "gpt")")
    main_files=$(echo "$main_files" | sed -e 's/```[a-zA-Z]*//g' -e 's/```//g' -e 's/echo "//g' -e 's/"//g' -e 's/ && /\n/g' -e '/^$/d')
    echo "$main_files"
}

identify_dependency_files() {
    local structure="$1"
    
    local dep_prompt=$(cat <<EOF
Analyze this project structure and identify ALL dependency files.
Look for:
- requirements.txt, requirements-*.txt
- package.json, package-lock.json
- Pipfile, Pipfile.lock
- pyproject.toml
- setup.py, setup.cfg
- Gemfile, Gemfile.lock
- go.mod, go.sum
- Cargo.toml
- pom.xml
- build.gradle

Project structure:
$structure

Return ONLY the file paths (relative to project root), one per line.
Include all dependency files you find.
DO NOT include any shell commands, backticks, or code formatting.
Just plain file paths, one per line.

Example output:
backend/requirements.txt
frontend/package.json
EOF
)
    
    local dep_files=$(buildme_generate "$dep_prompt" "$(get_api_key "gpt")")
    dep_files=$(echo "$dep_files" | sed -e 's/```[a-zA-Z]*//g' -e 's/```//g' -e 's/echo "//g' -e 's/"//g' -e 's/ && /\n/g' -e '/^$/d')
    echo "$dep_files"
}

read_file_content() {
    local file="$1"
    local max_lines=300
    
    if [[ -f "$file" ]]; then
        head -n "$max_lines" "$file"
    else
        echo "# File not found: $file"
    fi
}

buildme_starter_init_from_dir() {
    local name="$1"
    local source_dir="$2"
    local instructions="$3"
    
    if [[ ! -d "$source_dir" ]]; then
        echo "❌ Source directory not found: $source_dir"
        return 1
    fi
    
    echo "🔍 Analyzing project structure..."
    local structure=$(generate_treemap "$source_dir")
    # echo "📊 Project structure found:"
    # echo "──────────────────────────────"
    # echo "$structure"
    # echo "──────────────────────────────"
    # echo ""
    
    echo "🔎 Identifying dependency files..."
    local dep_files=$(identify_dependency_files "$structure")
    # echo "📋 Dependency files identified:"
    # echo "──────────────────────────────"
    # echo "$dep_files"
    # echo "──────────────────────────────"
    # echo ""
    
    echo "📦 Extracting dependencies..."
    local deps=$(extract_dependencies "$source_dir" "$dep_files")
    # echo "📦 Dependencies extracted:"
    # echo "──────────────────────────────"
    # echo "$deps"
    # echo "──────────────────────────────"
    # echo ""
    
    echo "📄 Identifying main files..."
    local main_files=$(identify_main_files "$source_dir" "$structure")
    # echo "📄 Main files identified:"
    # echo "──────────────────────────────"
    # echo "$main_files"
    # echo "──────────────────────────────"
    # echo ""

    echo "📖 Reading main files content..."
    local main_files_content=""
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        echo "  Reading: $file"
        main_files_content="${main_files_content}=== File: $file ===\n"
        main_files_content="${main_files_content}$(read_file_content "$source_dir/$file")\n\n"
    done <<< "$main_files"
    echo ""
    
    echo "🧠 Generating template..."
    local template_prompt=$(cat <<EOF
Analyze this project and generate a bash script that creates a reusable template.

PROJECT DATA:
============
Structure:
$structure

Dependencies:
$deps

Core Files:
$main_files

File Contents:
$(echo -e "$main_files_content")

User Focus: $instructions

TASK:
=====
Generate a bash script that recreates this project's skeleton. The script should:

1. Identify the project type (FastAPI, Flask, Next.js, etc.) from the structure and dependencies
2. Create the essential directory structure (ignore .git, node_modules, __pycache__, etc.)
3. Generate dependency files with the exact versions provided
4. Create starter versions of core files that:
   - Keep the imports and overall structure
   - Replace implementation details with minimal working code
   - Add TODO comments where logic was removed
   - Ensure the project can actually run

SCRIPT REQUIREMENTS:
- Start with: #!/usr/bin/env bash
- Include: set -euo pipefail
- Accept target directory as \$1
- Use mkdir -p for each directory (one per line)
- Use heredocs (cat << 'CONTENT_EOF') for file content
- End with a success message
- NO command chaining with &&

INTELLIGENCE REQUIRED:
- Infer the project structure pattern (e.g., if it's a FastAPI app, preserve the routers/models/core pattern)
- For config files, keep the structure but use sensible defaults
- For main entry points, create minimal working versions
- For utility files, create stubs with the function signatures
- Preserve the technology stack but simplify the implementation

Output ONLY the executable bash script. Be smart about what to include vs exclude.
EOF
)

    local template=$(buildme_generate "$template_prompt" "$(get_api_key "gpt")")
    
    template=$(echo "$template" | sed -e 's/```bash//g' -e 's/```//g' -e '/^$/d')
    
    local target_dir="$USER_STARTER_DIR/$name"
    mkdir -p "$target_dir"
    
    echo "$template" > "$target_dir/template.sh"
    chmod +x "$target_dir/template.sh"
    
    cat > "$target_dir/metadata.yaml" << EOF
name: $name
version: 1.0.0
description: Generated from $source_dir
author: $USER
dependencies_found: $(echo "$deps" | wc -l)
main_files_found: $(echo "$main_files" | wc -l)
EOF
    
    echo "✅ Template created: $target_dir"
    echo "📝 You can now use: buildme starter new $name <project-name>"
}

buildme_starter_init() {
    local name="$1"
    local source="$2"
    shift 2
    
    local instructions=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --instructions=*)
                instructions="${1#*=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ "$source" =~ ^https?://github.com/ ]] || [[ "$source" =~ ^[^/]+/[^/]+$ ]]; then
        local repo="${source#https://github.com/}"
        local temp_dir="/tmp/buildme_github_$name"
        
        if [[ -d "$temp_dir" ]]; then
            echo "⚠️  Removing existing temporary directory..."
            rm -rf "$temp_dir"
        fi
        
        echo "📥 Cloning repository..."
        git clone "https://github.com/$repo.git" "$temp_dir" || return 1
        
        buildme_starter_init_from_dir "$name" "$temp_dir" "$instructions"
        local result=$?
        
        rm -rf "$temp_dir"
        return $result
    elif [[ -d "$source" ]]; then
        buildme_starter_init_from_dir "$name" "$source" "$instructions"
    else
        echo "❌ Invalid source: $source"
        return 1
    fi
}

buildme_starter_delete() {
    local name="$1"
    
    local starter_path
    starter_path=$(get_starter_path "$name") || {
        echo "❌ Starter '$name' not found"
        return 1
    }
    
    echo "Are you sure you want to delete the starter '$name'? This action cannot be undone. [y/N]"
    read -r confirmation
    if [[ "$confirmation" != "y" ]]; then
        echo "Deletion cancelled."
        return 0
    fi
    
    rm -rf "$starter_path"
    echo "✅ Starter '$name' has been deleted."
}

buildme_starter() {
    local subcmd="$1"
    shift
    
    case "$subcmd" in
        list)
            buildme_starter_list
            ;;
        new)
            buildme_starter_new "$@"
            ;;
        init)
            buildme_starter_init "$@"
            ;;
        delete)
            buildme_starter_delete "$@"
            ;;
        *)
            echo "❌ Unknown starter command. Use: list, new, init, delete"
            return 1
            ;;
    esac
}

generate_treemap() {
    local dir="$1"
    local max_depth=3

    if command -v tree &> /dev/null; then
        tree -L "$max_depth" "$dir"
    else
        find "$dir" -maxdepth "$max_depth" -type d -print | while read -r d; do
            echo "$d"
            find "$d" -maxdepth 1 -type f \( -name "requirements.txt" -o -name "package.json" -o -name "*.py" -o -name "*.js" \) -print | sed 's/^/  /'
        done
    fi
}