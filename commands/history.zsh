# --- history.zsh ---

# This script provides functions for managing and interacting with the command
# history of the 'buildme' tool. It allows users to track, deduplicate, and
# clean their command history, as well as undo recent commands.
#
# Features:
# - `buildme_track_command`: Tracks and logs executed commands.
# - `buildme_dedupe_history`: Removes duplicate entries from the history.
# - `buildme_history`: Displays the most recent commands from history.
# - `buildme_clear_history`: Clears the entire command history.
# - `buildme_clean_history`: Cleans the history by removing duplicates.
# - `buildme_undo_from_history`: Suggests undo commands for recent history.
#
# Usage:
# - Use `buildme history` to view recent command history.
# - Use `buildme clear_history` to clear all command history.
# - Use `buildme clean_history` to remove duplicate entries.
# - Use `buildme undo_from_history` to undo recent commands.
#
# Dependencies:
# - Assumes a writable home directory for storing command history.


BUILDME_HISTORY_FILE="$HOME/.buildme_history"
touch "$BUILDME_HISTORY_FILE"
buildme_dedupe_history() {
    if [[ -f "$BUILDME_HISTORY_FILE" ]]; then
        awk -F'|' '!seen[$2]++ {latest[$2] = $0} seen[$2] == 1 {delete latest[$2]; latest[$2] = $0} END {for (cmd in latest) print latest[cmd]}' "$BUILDME_HISTORY_FILE" | sort -t'|' -k1 > "${BUILDME_HISTORY_FILE}.tmp"
        mv "${BUILDME_HISTORY_FILE}.tmp" "$BUILDME_HISTORY_FILE"
    fi
}


buildme_track_command() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local command="$1"
    
    if [[ -f "$BUILDME_HISTORY_FILE" ]]; then
        local last_entry=$(tail -n 1 "$BUILDME_HISTORY_FILE")
        if [[ "$last_entry" == *"|$command" ]]; then
            return 0
        fi
    fi
    
    echo "$timestamp|$command" >> "$BUILDME_HISTORY_FILE"
    
    if (( RANDOM % 20 == 0 )); then
        buildme_dedupe_history
        
        if [[ $(wc -l < "$BUILDME_HISTORY_FILE") -gt 500 ]]; then
            tail -n 500 "$BUILDME_HISTORY_FILE" > "${BUILDME_HISTORY_FILE}.tmp"
            mv "${BUILDME_HISTORY_FILE}.tmp" "$BUILDME_HISTORY_FILE"
        fi
    fi
}

buildme_precmd() {
    if [[ -n "$BUILDME_HISTORY_FILE" ]]; then
        local last_cmd=$(fc -ln -1)
        [[ "$last_cmd" != buildme* && "$last_cmd" != " "* ]] && buildme_track_command "$last_cmd"
    fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd buildme_precmd

buildme_history() {
    if [[ ! -f "$BUILDME_HISTORY_FILE" ]]; then
        echo "⚠️  No command history found."
        return 1
    fi
    
    local n=${1:-10}
    tail -n "$n" "$BUILDME_HISTORY_FILE"
}

buildme_clear_history() {
    if [[ -f "$BUILDME_HISTORY_FILE" ]]; then
        rm "$BUILDME_HISTORY_FILE"
        touch "$BUILDME_HISTORY_FILE"
        echo "✅ Command history cleared."
    fi
}

buildme_clean_history() {
    if [[ ! -f "$BUILDME_HISTORY_FILE" ]]; then
        echo "⚠️  No command history found."
        return 1
    fi
    
    local original_count=$(wc -l < "$BUILDME_HISTORY_FILE")
    buildme_dedupe_history
    local new_count=$(wc -l < "$BUILDME_HISTORY_FILE")
    local removed=$((original_count - new_count))
    
    echo "✅ Command history cleaned."
    echo "📊 Removed $removed duplicate entries ($original_count → $new_count commands)"
}

buildme_undo_from_history() {
    if [[ ! -f "$BUILDME_HISTORY_FILE" ]]; then
        echo "⚠️  No command history found."
        return 1
    fi
    local n=10
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        n="$1"
        shift
    fi
    local last_commands=$(tail -n "$n" "$BUILDME_HISTORY_FILE" | cut -d'|' -f2-)
    
    local user_instruction="$*"
    
    local undo_prompt="Undo the following shell commands. Output only the shell commands needed to reverse these actions."
    [[ -n "$user_instruction" ]] && undo_prompt+=" $user_instruction"
    undo_prompt+="\n\n$last_commands"

    echo "🧠 Asking LLM to suggest undo steps..."
    local key=$(get_api_key "gpt")
    local undo_commands=$(buildme_generate "$undo_prompt" "$key" "gpt-4o-mini")

    echo ""
    echo "❗ Proposed undo:"
    echo "──────────────────────────────"
    echo "$undo_commands" \
        | sed -e 's/^```bash//' -e 's/^```//' -e '/^$/d'
    echo "──────────────────────────────"
    
    read -r "?Run these undo commands? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        zsh -i -c "$undo_commands"
        echo "✅ Undo complete."
    else
        echo "⏭️  Undo cancelled."
    fi
}