# buildme_starter.zsh

# Constants
STARTER_DIR="${0:A:h}/starters"
USER_STARTER_DIR="$HOME/.buildme_starters"

# Ensure directories exist
mkdir -p "$STARTER_DIR" "$USER_STARTER_DIR"

# Helper function to get starter path
get_starter_path() {
    local name="$1"
    # First check user's custom starters
    if [[ -d "$USER_STARTER_DIR/$name" ]]; then
        echo "$USER_STARTER_DIR/$name"
    # Then check built-in starters
    elif [[ -d "$STARTER_DIR/$name" ]]; then
        echo "$STARTER_DIR/$name"
    else
        return 1
    fi
}

# List available starters
buildme_starter_list() {
    echo "📦 Available starters:"
    
    # List built-in starters
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
    
    # List user's custom starters
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

# Create a new project from a starter
buildme_starter_new() {
    local name="$1"
    local target="$2"
    shift 2
    
    local starter_path
    starter_path=$(get_starter_path "$name") || {
        echo "❌ Starter '$name' not found"
        return 1
    }
    
    # Read metadata
    local metadata="$starter_path/metadata.yaml"
    if [[ -f "$metadata" ]]; then
        # Parse required variables
        local required_vars=()
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*([^[:space:]]+) ]]; then
                required_vars+=("${BASH_REMATCH[1]}")
            fi
        done < "$metadata"
        
        # Check if all required variables are provided
        for var in "${required_vars[@]}"; do
            if ! [[ " $* " =~ " --$var=" ]]; then
                echo "❌ Missing required variable: $var"
                echo "Usage: buildme starter new $name <target> --$var=<value> [--other-var=<value>]"
                return 1
            fi
        done
    fi
    
    # Create the project
    if [[ -f "$starter_path/template.sh" ]]; then
        bash "$starter_path/template.sh" "$target" "$@"
    else
        echo "❌ No template.sh found in starter '$name'"
        return 1
    fi
}

# Better dependency extraction with LLM assistance
extract_dependencies() {
    local dir="$1"
    local dep_files="$2"
    local all_deps=""
    
    echo "🔍 Debug: extract_dependencies called with:" >&2
    echo "  dir: $dir" >&2
    echo "  dep_files: $dep_files" >&2
    echo "🔍 Debug: Directory exists? $(test -d "$dir" && echo "YES" || echo "NO")" >&2
    echo "🔍 Debug: Directory contents:" >&2
    ls -la "$dir" >&2 2>/dev/null || echo "  Cannot list directory" >&2
    echo "" >&2
    
    # Read each dependency file - handle multi-line input properly
    while IFS= read -r dep_file; do
        [[ -z "$dep_file" ]] && continue
        
        local full_path="$dir/$dep_file"
        echo "🔍 Debug: Processing dep_file: '$dep_file'" >&2
        echo "🔍 Debug: Full path: '$full_path'" >&2
        echo "🔍 Debug: File exists? $(test -f "$full_path" && echo "YES" || echo "NO")" >&2
        
        if [[ -f "$full_path" ]]; then
            echo "📖 Reading $dep_file..." >&2
            local content=$(cat "$full_path")
            echo "🔍 Debug: File content length: ${#content} characters" >&2
            echo "🔍 Debug: First 100 chars: ${content:0:100}..." >&2
            all_deps="${all_deps}From $dep_file:\n${content}\n\n"
        else
            echo "❌ Debug: File not found: $full_path" >&2
            # Check if parent directory exists
            local parent_dir=$(dirname "$full_path")
            echo "🔍 Debug: Parent directory '$parent_dir' exists? $(test -d "$parent_dir" && echo "YES" || echo "NO")" >&2
            if [[ -d "$parent_dir" ]]; then
                echo "🔍 Debug: Parent directory contents:" >&2
                ls -la "$parent_dir" >&2 2>/dev/null || echo "  Cannot list parent directory" >&2
            fi
        fi
    done <<< "$dep_files"
    
    echo "🔍 Debug: Total deps content length: ${#all_deps}" >&2
    echo "🔍 Debug: all_deps preview: ${all_deps:0:200}..." >&2
    
    # If no dependencies found, return empty
    if [[ -z "$all_deps" ]]; then
        echo "⚠️  Debug: No dependencies found, returning empty" >&2
        echo ""
        return
    fi
    
    # Use LLM to filter and clean dependencies
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
    
    echo "🔍 Dependency extraction LLM prompt:" >&2
    echo "──────────────────────────────" >&2
    echo "$deps_prompt" >&2
    echo "──────────────────────────────" >&2
    echo "" >&2
    
    local cleaned_deps=$(buildme_generate "$deps_prompt" "$(get_api_key "gpt")")
    echo "$cleaned_deps"
}

# LLM-powered main files identification
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
    # Clean up the output - remove backticks, echo commands, &&, etc.
    main_files=$(echo "$main_files" | sed -e 's/```[a-zA-Z]*//g' -e 's/```//g' -e 's/echo "//g' -e 's/"//g' -e 's/ && /\n/g' -e '/^$/d')
    echo "$main_files"
}

# LLM-powered dependency file identification
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
    # Clean up the output - remove backticks, echo commands, &&, etc.
    dep_files=$(echo "$dep_files" | sed -e 's/```[a-zA-Z]*//g' -e 's/```//g' -e 's/echo "//g' -e 's/"//g' -e 's/ && /\n/g' -e '/^$/d')
    echo "$dep_files"
}

# Read file content with truncation
read_file_content() {
    local file="$1"
    local max_lines=300
    
    if [[ -f "$file" ]]; then
        # Get first 300 lines, prioritizing actual code
        head -n "$max_lines" "$file"
    else
        echo "# File not found: $file"
    fi
}

# Create template from directory with improved flow
buildme_starter_init_from_dir() {
    local name="$1"
    local source_dir="$2"
    local instructions="$3"
    
    if [[ ! -d "$source_dir" ]]; then
        echo "❌ Source directory not found: $source_dir"
        return 1
    fi
    
    # Step 1: Generate project structure
    echo "🔍 Analyzing project structure..."
    local structure=$(generate_treemap "$source_dir")
    echo "📊 Project structure found:"
    echo "──────────────────────────────"
    echo "$structure"
    echo "──────────────────────────────"
    echo ""
    
    # Step 2: Identify dependency files using LLM
    echo "🔎 Identifying dependency files..."
    local dep_files=$(identify_dependency_files "$structure")
    echo "📋 Dependency files identified:"
    echo "──────────────────────────────"
    echo "$dep_files"
    echo "──────────────────────────────"
    echo ""
    
    # Step 3: Extract dependencies
    echo "📦 Extracting dependencies..."
    local deps=$(extract_dependencies "$source_dir" "$dep_files")
    echo "📦 Dependencies extracted:"
    echo "──────────────────────────────"
    echo "$deps"
    echo "──────────────────────────────"
    echo ""
    
    # Step 4: Identify main files using LLM
    echo "📄 Identifying main files..."
    local main_files=$(identify_main_files "$source_dir" "$structure")
    echo "📄 Main files identified:"
    echo "──────────────────────────────"
    echo "$main_files"
    echo "──────────────────────────────"
    echo ""
    
    # Step 5: Read main files content
    echo "📖 Reading main files content..."
    local main_files_content=""
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        echo "  Reading: $file"
        main_files_content="${main_files_content}=== File: $file ===\n"
        main_files_content="${main_files_content}$(read_file_content "$source_dir/$file")\n\n"
    done <<< "$main_files"
    echo ""
    
    # Step 6: Generate template with all context
    echo "🧠 Generating template..."
#     local template_prompt=$(cat <<EOF
# You are a reusable template generator. Create a Bash script that generates a project with the same structure as the analyzed project.

# PROJECT CONTEXT:
# Structure:
# $structure

# Dependencies (cleaned and filtered):
# $deps

# Main files and their content (truncated to 300 lines each):
# $(echo -e "$main_files_content")

# User instructions: $instructions

# YOUR TASK:
# Create a Bash script that:
# 1. Recreates the essential directory structure
# 2. Generates placeholder versions of the main files (keep imports, class/function signatures, but use placeholder implementations)
# 3. Creates dependency files with the exact dependencies listed above
# 4. Uses variables for project-specific names (PROJECT_NAME, etc.)
# 5. Includes helpful comments

# REQUIREMENTS:
# - Start with: #!/usr/bin/env bash
# - Include: set -euo pipefail
# - Accept TARGET_DIR as \$1
# - Use mkdir -p for directories
# - Use cat << '\''EOF'\'' for file content (note the quotes to prevent variable expansion)
# - For placeholder code:
#   - Python: def function_name(): pass
#   - JavaScript: export const functionName = () => { /* TODO: Implement */ }
# - Include success message: echo "✅ Project created at \$TARGET_DIR"

# Output ONLY the bash script, no explanations or markdown.
# EOF
# )
    local template_prompt=$(cat <<EOF
You are a reusable template generator. Your job is to analyze a project directory and create a clean, reusable Bash script template that can generate similar projects.

CONTEXT:
You're given:
- The folder structure of a real project
- A list of dependencies
- The main application files
- Optional user instructions guiding what to emphasize or omit

You must create a Bash script that builds a *reusable skeleton* of this project. The output should preserve the project's architectural structure and dependency layout — but use placeholders and minimal boilerplate to make it usable for new projects.

PROJECT SNAPSHOT:
Project type: $project_type
Dependencies:
$deps

Main files:
$main_files

Project structure:
$structure

User instructions:
$instructions

YOUR TASK:
Write a Bash script that:
1. Creates a new project with the same structure and layout logic
2. Includes only essential directories and representative files (no need to replicate every single folder unless important)
3. Uses placeholder code for logic (function stubs, class shells, etc.)
4. Populates `requirements.txt`, `package.json`, or other files with actual dependency versions from the original
5. Honors user instructions to modify or simplify the output
6. Supports configurable values like project name or author using variables or CLI flags

REQUIREMENTS FOR THE SCRIPT:
- Start with: #!/usr/bin/env bash
- Use: set -euo pipefail
- Accept TARGET_DIR as \$1
- Use mkdir -p for folders and cat <<EOF for file content
- Structure your script into readable sections (e.g., "# Backend", "# Frontend", etc.)
- Use placeholders in code (e.g., \`def placeholder(): pass\`, \`export const MyComponent = () => null\`)
- Include a success message at the end
- Output ONLY the bash script, no markdown or explanations
- Do not include any other text or comments in the output
EOF
)
    
    echo "📝 Final LLM prompt:"
    echo "════════════════════════════════════════════════════════════════"
    echo "$template_prompt"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    local template=$(buildme_generate "$template_prompt" "$(get_api_key "gpt")")
    
    echo "🤖 LLM Response (generated template):"
    echo "──────────────────────────────"
    echo "$template"
    echo "──────────────────────────────"
    echo ""
    
    # Step 7: Save template
    local target_dir="$USER_STARTER_DIR/$name"
    mkdir -p "$target_dir"
    
    # Save template script
    echo "$template" > "$target_dir/template.sh"
    chmod +x "$target_dir/template.sh"
    
    # Save metadata
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

# Simplified init function
buildme_starter_init() {
    local name="$1"
    local source="$2"
    shift 2
    
    # Parse instructions
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
    
    # Auto-detect source type
    if [[ "$source" =~ ^https?://github.com/ ]] || [[ "$source" =~ ^[^/]+/[^/]+$ ]]; then
        # GitHub repo
        local repo="${source#https://github.com/}"
        local temp_dir="/tmp/buildme_github_$name"
        
        # Remove existing temp directory if it exists
        if [[ -d "$temp_dir" ]]; then
            echo "⚠️  Removing existing temporary directory..."
            rm -rf "$temp_dir"
        fi
        
        echo "📥 Cloning repository..."
        git clone "https://github.com/$repo.git" "$temp_dir" || return 1
        
        # Process the directory before cleanup
        buildme_starter_init_from_dir "$name" "$temp_dir" "$instructions"
        local result=$?
        
        # Cleanup after processing
        rm -rf "$temp_dir"
        return $result
    elif [[ -d "$source" ]]; then
        # Local directory
        buildme_starter_init_from_dir "$name" "$source" "$instructions"
    else
        echo "❌ Invalid source: $source"
        return 1
    fi
}

# Delete a starter
buildme_starter_delete() {
    local name="$1"
    
    # Determine the path of the starter
    local starter_path
    starter_path=$(get_starter_path "$name") || {
        echo "❌ Starter '$name' not found"
        return 1
    }
    
    # Confirm deletion
    echo "Are you sure you want to delete the starter '$name'? This action cannot be undone. [y/N]"
    read -r confirmation
    if [[ "$confirmation" != "y" ]]; then
        echo "Deletion cancelled."
        return 0
    fi
    
    # Delete the starter
    rm -rf "$starter_path"
    echo "✅ Starter '$name' has been deleted."
}

# Main starter function
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
    local max_depth=3  # Adjust depth as needed

    if command -v tree &> /dev/null; then
        # Use tree if available
        tree -L "$max_depth" "$dir"
    else
        # Fallback to find if tree is not available
        find "$dir" -maxdepth "$max_depth" -type d -print | while read -r d; do
            echo "$d"
            find "$d" -maxdepth 1 -type f \( -name "requirements.txt" -o -name "package.json" -o -name "*.py" -o -name "*.js" \) -print | sed 's/^/  /'
        done
    fi
}