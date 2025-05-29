# buildme_history.zsh

# Initialize history file
BUILDME_HISTORY_FILE="$HOME/.buildme_history"
touch "$BUILDME_HISTORY_FILE"

# Function to deduplicate history
buildme_dedupe_history() {
    if [[ -f "$BUILDME_HISTORY_FILE" ]]; then
        # Create a temporary file with unique commands (keeping the latest timestamp for each)
        awk -F'|' '!seen[$2]++ {latest[$2] = $0} seen[$2] == 1 {delete latest[$2]; latest[$2] = $0} END {for (cmd in latest) print latest[cmd]}' "$BUILDME_HISTORY_FILE" | sort -t'|' -k1 > "${BUILDME_HISTORY_FILE}.tmp"
        mv "${BUILDME_HISTORY_FILE}.tmp" "$BUILDME_HISTORY_FILE"
    fi
}

# Function to track commands
buildme_track_command() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local command="$1"
    
    # Skip if the exact same command was run in the last 5 seconds
    if [[ -f "$BUILDME_HISTORY_FILE" ]]; then
        local last_entry=$(tail -n 1 "$BUILDME_HISTORY_FILE")
        if [[ "$last_entry" == *"|$command" ]]; then
            return 0  # Skip duplicate
        fi
    fi
    
    echo "$timestamp|$command" >> "$BUILDME_HISTORY_FILE"
    
    # Occasionally clean up duplicates and limit size
    if (( RANDOM % 20 == 0 )); then
        buildme_dedupe_history
        
        # Keep only last 500 commands after deduplication
        if [[ $(wc -l < "$BUILDME_HISTORY_FILE") -gt 500 ]]; then
            tail -n 500 "$BUILDME_HISTORY_FILE" > "${BUILDME_HISTORY_FILE}.tmp"
            mv "${BUILDME_HISTORY_FILE}.tmp" "$BUILDME_HISTORY_FILE"
        fi
    fi
}

# The precmd hook function
buildme_precmd() {
    if [[ -n "$BUILDME_HISTORY_FILE" ]]; then
        local last_cmd=$(fc -ln -1)
        # Only track if it's not a buildme command and not a space-prefixed command
        [[ "$last_cmd" != buildme* && "$last_cmd" != " "* ]] && buildme_track_command "$last_cmd"
    fi
}

# Register the precmd hook
autoload -Uz add-zsh-hook
add-zsh-hook precmd buildme_precmd

# History management functions
buildme_history() {
    if [[ ! -f "$BUILDME_HISTORY_FILE" ]]; then
        echo "⚠️  No command history found."
        return 1
    fi
    
    # Show last N commands (default 10)
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

# New function to clean history without clearing it completely
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

# New function for undo from history
buildme_undo_from_history() {
    if [[ ! -f "$BUILDME_HISTORY_FILE" ]]; then
        echo "⚠️  No command history found."
        return 1
    fi

    # Get the last N commands from history (default 10)
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