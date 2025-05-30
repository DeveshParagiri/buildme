# --- undo.zsh ---
# 
# This script defines the `buildme_undo` function, which provides a mechanism
# to undo the most recent meaningful operation performed by the user. It
# intelligently determines whether to undo a recent 'buildme' session or a
# terminal command based on available history.
#
# Features:
# - Retrieves recent 'buildme' session commands and terminal history.
# - Uses an LLM to suggest precise undo commands for the most recent action.
# - Provides a user prompt to confirm execution of the suggested undo commands.
# - Handles file and directory removals, and package uninstalls.
#
# Usage:
# - Invoke `buildme_undo` to attempt to undo the last significant action.
# - The function will prompt for confirmation before executing any undo commands.
#
# Dependencies:
# - Requires access to session and command history files.
# - Utilizes an LLM API for generating undo suggestions.


buildme_undo() {
    local user_instruction="$*"
    user_instruction="${user_instruction#undo}"
    
    local buildme_cmds=""
    local history_cmds=""
    
    if [[ -f ~/.last_buildme_session.sh ]]; then
        local session_content=$(tail -n 20 ~/.last_buildme_session.sh | grep -E "(ORIGINAL_REQUEST|GENERATED_COMMANDS|TIMESTAMP)" | tail -n 9)
        if [[ -n "$session_content" ]]; then
            buildme_cmds="Recent buildme sessions:
$session_content"
        fi
    elif [[ -f ~/.last_buildme_commands.sh ]]; then
        local last_buildme=$(cat ~/.last_buildme_commands.sh | cut -d'|' -f2- 2>/dev/null | head -n 1)
        if [[ -n "$last_buildme" && "$last_buildme" != "head: |: No such file or directory" ]]; then
            buildme_cmds="Last buildme command:\n$last_buildme"
        fi
    fi
    
    if [[ -f "$BUILDME_HISTORY_FILE" ]]; then
        local recent_cmd=$(tail -n 10 "$BUILDME_HISTORY_FILE" | cut -d'|' -f2- | grep -v "^buildme" | grep -v "source ~/.zshrc" | grep -v "cat ~/.last_buildme" | grep -v "rm ~/.last_buildme" | tail -n 1)
        if [[ -n "$recent_cmd" ]]; then
            history_cmds="Most recent command: $recent_cmd"
        fi
    fi
    
    if [[ -z "$buildme_cmds" && -z "$history_cmds" ]]; then
        echo "⚠️  No useful command history found."
        echo "💡 Try running some commands first, then use undo"
        return 1
    fi
    
    local undo_prompt="You are a shell expert. Undo ONLY the most recent meaningful operation.

RULES:
- Output 1-2 shell commands maximum, one per line
- No explanations, no markdown  
- Focus ONLY on the single most recent meaningful change
- If there's a buildme session, undo that. Otherwise undo the most recent terminal command
- Don't undo multiple operations - be surgical and precise
- For file creation: suggest rm
- For directory creation: suggest rm -rf  
- For package installs: suggest uninstall (but only if very recent)
- Skip anything older than the last meaningful operation

Context: ${user_instruction:-"undo the most recent action"}

$buildme_cmds

$history_cmds"

    echo "🧠 Asking LLM to suggest undo steps..."
    local key=$(get_api_key "gpt")
    local undo_commands=$(buildme_generate "$undo_prompt" "$key" "gpt-4o-mini")

    undo_commands=$(echo "$undo_commands" | \
        sed -e 's/^```[a-zA-Z]*//g' \
            -e 's/^```//g' \
            -e 's/[[:space:]]*#.*$//g' \
            -e 's/^[[:space:]]*//g' \
            -e 's/[[:space:]]*$//g' \
            -e '/^[[:space:]]*$/d' | \
        grep -v '^#' | \
        grep -v '^Here' | \
        grep -v '^To undo' | \
        grep -v '^You can' | \
        grep -E '^[a-zA-Z_./]' | \
        head -n 1)
    
    undo_commands=$(echo "$undo_commands" | sed 's/ && /\
/g')

    if [[ -z "$undo_commands" ]] || [[ $(echo "$undo_commands" | wc -l | tr -d ' ') -eq 0 ]]; then
        echo "❌ Could not generate safe undo commands"
        echo "💡 Recent commands don't seem to need undoing, or try being more specific:"
        echo "💡 buildme undo \"remove the files I just created\""
        return 1
    fi

    echo ""
    echo "❗ Proposed undo:"
    echo "──────────────────────────────"
    echo "$undo_commands"
    echo "──────────────────────────────"
    
    read -r "?Run these undo commands? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "$undo_commands" | while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue
            echo "🔄 Running: $cmd"
            if eval "$cmd"; then
                echo "✅ Success"
            else
                echo "❌ Failed: $cmd"
            fi
        done
        echo "✅ Undo complete."
    else
        echo "⏭️  Undo cancelled."
    fi
}