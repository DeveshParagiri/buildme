# buildme_history.zsh

# Initialize history file
BUILDME_HISTORY_FILE="$HOME/.buildme_history"
touch "$BUILDME_HISTORY_FILE"

# Function to track commands
buildme_track_command() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp|$1" >> "$BUILDME_HISTORY_FILE"
    
    # Keep only last 1000 commands (with basic concurrency safety)
    if (( RANDOM % 10 == 0 )); then
        if [[ $(wc -l < "$BUILDME_HISTORY_FILE") -gt 1000 ]]; then
            tail -n 1000 "$BUILDME_HISTORY_FILE" > "${BUILDME_HISTORY_FILE}.tmp"
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