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

# Helper function to identify project type
    identify_project_type() {
    local dir="$1"
    
    # Check for common project indicators
    if [[ -f "$dir/requirements.txt" ]] && grep -q "fastapi" "$dir/requirements.txt"; then
        echo "fastapi"
    elif [[ -f "$dir/requirements.txt" ]] && grep -q "flask" "$dir/requirements.txt"; then
        echo "flask"
    elif [[ -f "$dir/pyproject.toml" ]] && grep -q "click" "$dir/pyproject.toml"; then
        echo "python-cli"
    elif [[ -f "$dir/package.json" ]]; then
        echo "nodejs"
    else
        echo "unknown"
    fi
}

# Better dependency extraction
extract_dependencies() {
    local dir="$1"
    local project_type="$2"
    
    case "$project_type" in
        fastapi|flask|python-cli)
            if [[ -f "$dir/requirements.txt" ]]; then
                # Get actual dependencies, not comments or empty lines
                grep -v "^#" "$dir/requirements.txt" | grep -v "^$"
            elif [[ -f "$dir/pyproject.toml" ]]; then
                # Extract dependencies section from pyproject.toml
                awk '/\[tool\.poetry\.dependencies\]/{flag=1;next}/\[/{flag=0}flag' "$dir/pyproject.toml"
            elif [[ -f "$dir/setup.py" ]]; then
                # Extract install_requires from setup.py
                grep -A 20 "install_requires" "$dir/setup.py" | grep -E "^\s*['\"]"
            fi
            ;;
        nodejs)
            if [[ -f "$dir/package.json" ]]; then
                # Extract just the dependencies object
                jq -r '.dependencies | to_entries | .[] | "\(.key)@\(.value)"' "$dir/package.json" 2>/dev/null
            fi
            ;;
    esac
}

# Better main files identification
identify_main_files() {
    local dir="$1"
    local project_type="$2"
    
    case "$project_type" in
        fastapi)
            # Look for main.py, app.py, or files with FastAPI() instantiation
            find "$dir" -name "main.py" -o -name "app.py" | head -5
            grep -l "FastAPI()" "$dir"/*.py 2>/dev/null | head -5
            ;;
        flask)
            # Look for app.py or files with Flask() instantiation
            find "$dir" -name "app.py" -o -name "application.py" | head -5
            grep -l "Flask(__name__)" "$dir"/*.py 2>/dev/null | head -5
            ;;
        python-cli)
            # Look for CLI entry points
            find "$dir" -name "cli.py" -o -name "__main__.py" | head -5
            grep -l "if __name__ == ['\"]__main__['\"]" "$dir"/*.py 2>/dev/null | head -5
            ;;
        nodejs)
            # Look for index.js, app.js, or server.js
            find "$dir" -name "index.js" -o -name "app.js" -o -name "server.js" | head -5
            ;;
    esac
}

# Create template from directory
buildme_starter_init_from_dir() {
    local name="$1"
    local source_dir="$2"
    local instructions="$3"
    
    if [[ ! -d "$source_dir" ]]; then
        echo "❌ Source directory not found: $source_dir"
        return 1
    fi
    
    # 1. Analyze project
    echo "🔍 Analyzing project..."
    local project_type=$(identify_project_type "$source_dir")
    local deps=$(extract_dependencies "$source_dir" "$project_type")
    local main_files=$(identify_main_files "$source_dir" "$project_type")
    local structure=$(generate_treemap "$source_dir")
    
    # 2. Generate template with LLM
    echo "🧠 Generating template..."
    local template_prompt="You are a template generator. Your job is to analyze a project structure and create a reusable bash script template that can generate similar projects.

CONTEXT:
I'm giving you information about a $project_type project. You need to create a bash script that can generate new projects with the same structure and dependencies, but with configurable names and options.

PROJECT ANALYSIS:
Type: $project_type
Dependencies found:
$deps

Main application files:
$main_files

Project structure:
$structure

YOUR TASK:
1. Create a bash script that generates this type of project
2. Make project names configurable (replace specific names with variables)
3. Include all necessary dependencies with their versions
4. Create the same directory structure
5. Generate starter/boilerplate code for main files
6. Remove any project-specific business logic
7. Keep only the structural patterns and setup

REQUIREMENTS FOR THE SCRIPT:
- Start with: #!/usr/bin/env bash
- Include: set -euo pipefail
- Accept TARGET_DIR as \$1
- Use mkdir -p for directories
- Use cat with heredocs for file creation
- Include success message at the end
- Add comments explaining each section

Output ONLY the bash script, no explanations or markdown."
    
    echo "Template Prompt Sent to LLM:"
    echo "$template_prompt"
    
    local template=$(buildme_generate "$template_prompt" "$(get_api_key)")
    
    # 3. Save template
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
type: $project_type
author: $USER
EOF
    
    echo "✅ Template created: $target_dir"
    echo "📝 You can now use: buildme starter new $name <project-name>"
}

# Create template from GitHub
buildme_starter_init_from_github() {
    local name="$1"
    local repo="$2"
    local temp_dir="/tmp/buildme_github_$name"
    
    echo "📥 Cloning repository..."
    git clone "https://github.com/$repo.git" "$temp_dir" || {
        echo "❌ Failed to clone repository"
        return 1
    }
    
    buildme_starter_init_from_dir "$name" "$temp_dir"
    
    # Cleanup
    rm -rf "$temp_dir"
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
        echo "📥 Cloning repository..."
        git clone "https://github.com/$repo.git" "$temp_dir" || return 1
        buildme_starter_init_from_dir "$name" "$temp_dir" "$instructions"
        rm -rf "$temp_dir"
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