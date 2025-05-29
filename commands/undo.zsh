buildme_undo() {
    local user_instruction="$*"
    user_instruction="${user_instruction#undo}"
    
    # Get both contexts with better parsing
    local buildme_cmds=""
    local history_cmds=""
    
    if [[ -f ~/.last_buildme_commands.sh ]]; then
        # Extract just the command part after the timestamp and pipe
        local last_buildme=$(cat ~/.last_buildme_commands.sh | cut -d'|' -f2- 2>/dev/null | head -n 1)
        if [[ -n "$last_buildme" && "$last_buildme" != "head: |: No such file or directory" ]]; then
            buildme_cmds="Last buildme command:\n$last_buildme"
        fi
    fi
    
    if [[ -f "$BUILDME_HISTORY_FILE" ]]; then
        # Get unique recent commands, exclude buildme commands to avoid confusion
        history_cmds="Recent terminal history:\n$(tail -n 20 "$BUILDME_HISTORY_FILE" | cut -d'|' -f2- | grep -v "^buildme" | tail -n 5)"
    fi
    
    # If no useful history at all
    if [[ -z "$buildme_cmds" && -z "$history_cmds" ]]; then
        echo "⚠️  No useful command history found."
        echo "💡 Try running some commands first, then use undo"
        return 1
    fi
    
    # More focused prompt that avoids confusion
    local undo_prompt="You are a shell expert. Look at the command history and suggest commands to undo the most recent operations.

RULES:
- Output 1-5 shell commands only, one per line
- No explanations, comments, or markdown
- Focus on the MOST RECENT operations only  
- For file/directory creation (mkdir, touch): suggest removal (rm -rf, rmdir)
- For file removal (rm): warn that files cannot be restored or suggest trash recovery
- For directory changes (cd): suggest returning to previous location
- For git operations: suggest appropriate git undo (reset, revert, etc.)
- For package installs (pip, npm, brew): suggest uninstall commands
- For service operations: suggest opposite operation (start→stop, enable→disable)
- For file copies/moves: suggest removal or reverse operation
- For configuration changes: suggest restoring previous state
- If snapshots were restored: suggest removing the restored directory
- Be conservative but comprehensive - cover all types of state changes

Context: ${user_instruction:-"undo recent actions"}

$buildme_cmds

$history_cmds"

    echo "🧠 Asking LLM to suggest undo steps..."
    
    local key=$(get_api_key "gpt")
    local undo_commands=$(buildme_generate "$undo_prompt" "$key" "gpt-4o-mini")

    # Clean and validate the output - allow any reasonable shell commands
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
    
    # Split && chains into separate commands for display and safety
    undo_commands=$(echo "$undo_commands" | sed 's/ && /\
/g')

    # Validate that we have reasonable commands
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
        # Execute commands one by one for safety
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