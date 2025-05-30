#!/usr/bin/env bash

# --- snapshots.zsh ---
#
# This script provides functions for creating, listing, deleting, and restoring
# snapshots of the current directory. Snapshots are stored as compressed tar
# archives, allowing users to capture and restore the state of a project at
# specific points in time.
#
# Features:
# - `buildme_snapshot_create`: Creates a snapshot of the current directory.
# - `buildme_snapshot_list`: Lists all available snapshots.
# - `buildme_snapshot_delete`: Deletes a specified snapshot.
# - `buildme_snapshot_restore`: Restores a snapshot to a specified directory.
# - Supports platform detection for timestamp formatting.
#
# Usage:
# - Use `buildme snapshot <name>` to create a snapshot.
# - Use `buildme snapshot list` to view available snapshots.
# - Use `buildme snapshot delete <name>` to remove a snapshot.
# - Use `buildme restore <name|path> [--to <path>] [--overwrite] [--dry-run]` to restore a snapshot.
#
# Dependencies:
# - Requires `tar` for creating and extracting archives.
# - Assumes a writable home directory for storing snapshots.

SNAPSHOT_DIR="$HOME/.buildme_snapshots"

detect_platform() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*)  echo "linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

format_timestamp() {
    local timestamp="$1"
    local platform=$(detect_platform)
    
    if [[ "$timestamp" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        case "$platform" in
            macos)
                date -j -f "%Y%m%d_%H%M%S" "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp"
                ;;
            linux|windows)
                date -d "${timestamp:0:8} ${timestamp:9:2}:${timestamp:11:2}:${timestamp:13:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp"
                ;;
            *)
                echo "$timestamp"
                ;;
        esac
    else
        echo "$timestamp"
    fi
}

create_tar_archive() {
    local filepath="$1"
    local platform=$(detect_platform)
    
    if tar --version 2>/dev/null | grep -q "GNU tar"; then
        tar -czf "$filepath" \
            --exclude='.git' \
            --exclude='node_modules' \
            --exclude='__pycache__' \
            --exclude='*.pyc' \
            --exclude='.DS_Store' \
            --exclude='build' \
            --exclude='dist' \
            --exclude='.buildme_snapshots' \
            . 2>/dev/null
    else
        tar -czf "$filepath" \
            --exclude '.git' \
            --exclude 'node_modules' \
            --exclude '__pycache__' \
            --exclude '*.pyc' \
            --exclude '.DS_Store' \
            --exclude 'build' \
            --exclude 'dist' \
            --exclude '.buildme_snapshots' \
            . 2>/dev/null
    fi
}

buildme_ensure_snapshot_dir() {
    local snapshot_dir="${SNAPSHOT_DIR:-$HOME/.buildme_snapshots}"
    if [[ ! -d "$snapshot_dir" ]]; then
        mkdir -p "$snapshot_dir" || {
            echo "❌ Failed to create snapshot directory: $snapshot_dir"
            return 1
        }
    fi
}

buildme_get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

buildme_find_snapshot() {
    local name_or_path="$1"
    local snapshot_dir="${SNAPSHOT_DIR:-$HOME/.buildme_snapshots}"
    
    if [[ "$name_or_path" == *.tar.gz ]]; then
        echo "$name_or_path"
        return 0
    fi
    
    buildme_ensure_snapshot_dir
    
    local matches=()

    if cd "$snapshot_dir" 2>/dev/null; then
        for file in .buildme_snapshot_${name_or_path}_*.tar.gz; do
            if [[ -f "$file" ]]; then
                matches+=("$snapshot_dir/$file")
            fi
        done
        cd - >/dev/null
    fi
    
    if [[ ${#matches[@]} -gt 0 ]]; then
        printf '%s\n' "${matches[@]}" | sort -r | head -n1
        return 0
    fi
    
    return 1
}

buildme_snapshot_create() {
    local name="$1"
    [[ -z "$name" ]] && echo "❌ Snapshot name required" && return 1
    
    buildme_ensure_snapshot_dir || return 1
    
    echo "📁 Current directory: $(pwd)"
    local file_count
    file_count=$(find . -type f ! -path './.git/*' ! -path './node_modules/*' ! -path './__pycache__/*' ! -name '*.pyc' ! -name '.DS_Store' ! -path './build/*' ! -path './dist/*' ! -path './.buildme_snapshots/*' | wc -l | tr -d ' ')
    
    if [[ "$file_count" -eq 0 ]]; then
        echo "❌ No files found to snapshot in current directory"
        echo "💡 Make sure you're in a directory with actual files"
        echo "💡 Files excluded: .git/, node_modules/, __pycache__/, *.pyc, .DS_Store, build/, dist/"
        return 1
    fi
    
    echo "📊 Found $file_count files to snapshot"
    
    local snapshot_dir="${SNAPSHOT_DIR:-$HOME/.buildme_snapshots}"
    local timestamp=$(buildme_get_timestamp)
    local filename=".buildme_snapshot_${name}_${timestamp}.tar.gz"
    local filepath="$snapshot_dir/$filename"
    
    if buildme_find_snapshot "$name" >/dev/null 2>&1; then
        echo "⚠️  Snapshot with name '$name' already exists."
        read -r "?Continue anyway? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "🚫 Snapshot cancelled."
            return 1
        fi
    fi
    
    echo "📦 Creating snapshot '$name'..."
    echo "📁 Target: $filepath"
    
    if create_tar_archive "$filepath"; then
        
        if [[ ! -s "$filepath" ]]; then
            echo "❌ Snapshot file is empty. Check that your directory has files and isn't all excluded."
            rm -f "$filepath"
            return 1
        fi
        
        local archive_size
        archive_size=$(ls -lh "$filepath" | awk '{print $5}')
        local archive_files
        archive_files=$(tar -tzf "$filepath" 2>/dev/null | wc -l | tr -d ' ')
        
        echo "✅ Snapshot '$name' saved to $filename"
        echo "📏 Archive size: $archive_size"
        echo "📄 Files archived: $archive_files"
        
    else
        echo "❌ Failed to create snapshot"
        [[ -f "$filepath" ]] && rm -f "$filepath"
        return 1
    fi
}

buildme_snapshot_list() {
    buildme_ensure_snapshot_dir || return 1
    
    local snapshot_dir="${SNAPSHOT_DIR:-$HOME/.buildme_snapshots}"
    
    local snapshots=()
    
    if cd "$snapshot_dir" 2>/dev/null; then
        shopt -s nullglob 2>/dev/null || setopt nullglob 2>/dev/null || true
        for file in .buildme_snapshot_*.tar.gz; do
            [[ -f "$file" ]] && snapshots+=("$snapshot_dir/$file")
        done
        cd - >/dev/null
    fi
    
    if [[ ${#snapshots[@]} -eq 0 ]]; then
        echo ""
        echo "📦 No snapshots found"
        echo "💡 Create one with: buildme snapshot <name>"
        echo "📁 Snapshots are stored in: $snapshot_dir"
        echo ""
        return 0
    fi
    
    echo ""
    echo "📦 Available Snapshots (${#snapshots[@]})"
    echo "═══════════════════════════════════════════════════════════"
    
    for snapshot in "${snapshots[@]}"; do
        if [[ -f "$snapshot" ]]; then
            local basename=$(basename "$snapshot")      
            local name_and_timestamp=${basename#.buildme_snapshot_}
            local name_and_timestamp=${name_and_timestamp%.tar.gz}
            
            local name=${name_and_timestamp%_*}
            local timestamp=${name_and_timestamp##*_}
            
            local formatted_date=$(format_timestamp "$timestamp")
            
            local size=$(ls -lh "$snapshot" | awk '{print $5}')
            echo "🗂️  $name"
            echo "   📅 $formatted_date"
            echo "   📏 $size"
            echo "   🔧 Restore: buildme restore $name"
            echo ""
        fi
    done
    
    echo "Commands:"
    echo "  buildme restore <name> [--dry-run]    Restore a snapshot"  
    echo "  buildme snapshot delete <name>        Delete a snapshot"
    echo ""
}

buildme_snapshot_delete() {
    local name="$1"
    [[ -z "$name" ]] && echo "❌ Snapshot name required" && return 1
    
    local snapshot_file
    if ! snapshot_file=$(buildme_find_snapshot "$name"); then
        echo "❌ Snapshot '$name' not found"
        return 1
    fi
    
    echo "🗑️  Delete snapshot '$name'?"
    echo "   File: $(basename "$snapshot_file")"
    read -r "?Are you sure? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if rm -f "$snapshot_file"; then
            echo "✅ Snapshot '$name' deleted."
        else
            echo "❌ Failed to delete snapshot"
            return 1
        fi
    else
        echo "🚫 Delete cancelled."
    fi
}

buildme_snapshot_restore() {
    local name_or_path="$1"
    local target_dir=""
    local overwrite=0
    local dry_run=0
    
    [[ -z "$name_or_path" ]] && echo "❌ Snapshot name or path required" && return 1
    
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --to)
                target_dir="$2"
                shift 2
                ;;
            --overwrite)
                overwrite=1
                shift
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            *)
                echo "❌ Unknown option: $1"
                echo "Usage: buildme restore <name|path> [--to <path>] [--overwrite] [--dry-run]"
                return 1
                ;;
        esac
    done
    
    local snapshot_file
    if ! snapshot_file=$(buildme_find_snapshot "$name_or_path"); then
        echo "❌ Snapshot '$name_or_path' not found"
        return 1
    fi
    
    if [[ ! -f "$snapshot_file" || ! -r "$snapshot_file" ]]; then
        echo "❌ Snapshot file is not readable: $snapshot_file"
        return 1
    fi
    
    local basename=$(basename "$snapshot_file")
    local snapshot_name=${basename#.buildme_snapshot_}
    snapshot_name=${snapshot_name%_*.tar.gz}
    
    echo "📦 Restoring snapshot '$snapshot_name'"
    echo "📁 Source: $snapshot_file"
    
    if [[ "$dry_run" -eq 1 ]]; then
        echo "🧪 Dry run (listing contents):"
        echo "──────────────────────────────"
        if tar -tzf "$snapshot_file" 2>/dev/null | head -20; then
            local total_files=$(tar -tzf "$snapshot_file" 2>/dev/null | wc -l | tr -d ' ')
            if [[ "$total_files" -gt 20 ]]; then
                echo "... and $((total_files - 20)) more files"
            fi
        else
            echo "❌ Failed to list snapshot contents"
            return 1
        fi
        return 0
    fi
    
    if [[ "$overwrite" -eq 1 ]]; then
        target_dir="."
        echo "⚠️  WARNING: This will extract into the current directory!"
        echo "📁 Target: $(pwd)"
        read -r "?Continue? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "🚫 Restore cancelled."
            return 1
        fi
    elif [[ -n "$target_dir" ]]; then
        echo "📁 Target: $target_dir"   
        if [[ ! -d "$target_dir" ]]; then
            mkdir -p "$target_dir"
        fi
    else
        target_dir="./restored_$snapshot_name"
        echo "📁 Target: $target_dir"
        if [[ -d "$target_dir" ]]; then
            echo "⚠️  Directory '$target_dir' already exists."
            read -r "?Overwrite? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "🚫 Restore cancelled."
                return 1
            fi
        fi
        mkdir -p "$target_dir"
    fi
    
    echo "📦 Extracting..."
    if tar -xzf "$snapshot_file" -C "$target_dir" 2>/dev/null; then
        if [[ "$overwrite" -eq 1 ]]; then
            echo "✅ Extracted to current directory"
        else
            echo "✅ Extracted to $target_dir"
        fi
    else
        echo "❌ Failed to extract snapshot"
        return 1
    fi
}

buildme_snapshot() {
    case "${1:-}" in
        "")
            echo "❌ Usage: buildme snapshot {<name>|list|delete <name>}"
            echo ""
            echo "Commands:"
            echo "  buildme snapshot <name>        Create a snapshot"
            echo "  buildme snapshot list          List all snapshots"
            echo "  buildme snapshot delete <name> Delete a snapshot"
            echo ""
            echo "Restore command:"
            echo "  buildme restore <name|path> [--to <path>] [--overwrite] [--dry-run]"
            return 1
            ;;
        list)
            buildme_snapshot_list
            ;;
        delete)
            shift
            buildme_snapshot_delete "$@"
            ;;
        *)
            buildme_snapshot_create "$1"
            ;;
    esac
}
