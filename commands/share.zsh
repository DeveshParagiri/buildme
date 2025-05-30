# --- share.zsh ---

buildme_share() {
    local workflow_name=""
    local use_session=false
    local use_history=false
    local history_lines=10
    local target_os=""
    local format="markdown"
    local include_env=true
    local include_output=false
    local no_ai_summary=false
    local dry_run=false
    local filter_meaningful=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --session|--last-session)
                use_session=true
                shift
                ;;
            --history)
                use_history=true
                if [[ "$2" =~ ^[0-9]+$ ]]; then
                    history_lines="$2"
                    shift
                fi
                shift
                ;;
            --convert)
                if [[ -n "$2" ]]; then
                    target_os="$2"
                    shift
                else
                    echo "❌ --convert requires OS target (macos|linux|windows|ubuntu|centos)"
                    return 1
                fi
                shift
                ;;
            --format)
                if [[ -n "$2" ]]; then
                    format="$2"
                    shift
                else
                    echo "❌ --format requires type (markdown|json)"
                    return 1
                fi
                shift
                ;;
            --no-ai-summary)
                no_ai_summary=true
                shift
                ;;
            --include-env)
                include_env=true
                shift
                ;;
            --include-output)
                include_output=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --filter-meaningful)
                filter_meaningful=true
                shift
                ;;
            --no-filter)
                filter_meaningful=false
                shift
                ;;
            -*|--*)
                echo "❌ Unknown option: $1"
                return 1
                ;;
            *)
                if [[ -z "$workflow_name" ]]; then
                    workflow_name="$1"
                else
                    echo "❌ Multiple workflow names specified"
                    return 1
                fi
                shift
                ;;
        esac
    done
    
    local source_count=0
    [[ -n "$workflow_name" ]] && ((source_count++))
    [[ "$use_session" == true ]] && ((source_count++))
    [[ "$use_history" == true ]] && ((source_count++))
    
    if [[ $source_count -eq 0 ]]; then
        echo "❌ No source specified. Use workflow name, --session, or --history N"
        echo "💡 Available workflows:"
        list_available_workflows
        return 1
    elif [[ $source_count -gt 1 ]]; then
        echo "❌ Multiple sources specified. Choose one: workflow name, --session, or --history"
        return 1
    fi
    
    local workflow_data=""
    local workflow_title=""
    local data_source=""
    
    if [[ -n "$workflow_name" ]]; then
        workflow_data=$(extract_recorded_workflow "$workflow_name")
        workflow_title="$workflow_name"
        data_source="Recorded Workflow"
    elif [[ "$use_session" == true ]]; then
        workflow_data=$(extract_recent_session)
        workflow_title="buildme-session"
        data_source="Recent buildme Session"
    elif [[ "$use_history" == true ]]; then
        workflow_data=$(extract_terminal_history "$history_lines" "$filter_meaningful")
        workflow_title="terminal-history"
        data_source="Terminal History ($history_lines commands)"
    fi
    
    if [[ -z "$workflow_data" ]]; then
        echo "❌ No workflow data available"
        return 1
    fi
    
    local conversion_notes=""
    if [[ -n "$target_os" ]]; then
        local original_os=$(detect_current_os)
        echo "🔄 Converting commands from $original_os to $target_os..."
        workflow_data=$(convert_commands_for_os "$target_os" "$workflow_data" "$original_os")
        if [[ $? -eq 0 ]]; then
            conversion_notes="Commands converted from $original_os to $target_os"
        else
            conversion_notes="Some commands may not have direct equivalents on $target_os"
        fi
    fi
    
    echo "📝 Generating documentation in $format format..."
    
    local markdown_content
    if [[ "$format" == "markdown" ]]; then
        markdown_content=$(generate_workflow_markdown "$workflow_data" "$workflow_title" "$data_source" "$include_env" "$include_output" "$no_ai_summary" "$target_os" "$conversion_notes")
    elif [[ "$format" == "json" ]]; then
        markdown_content=$(generate_workflow_json "$workflow_data" "$workflow_title" "$data_source" "$include_env" "$include_output")
    fi
    
    if [[ "$dry_run" == true ]]; then
        echo "🔍 Dry run - would share:"
        echo "──────────────────────────────"
        echo "$markdown_content" | head -n 20
        echo "... (truncated)"
        echo "──────────────────────────────"
        return 0
    fi
    
    local timestamp=$(date +"%Y-%m-%d-%H-%M")
    local filename="$workflow_title-$timestamp.md"
    local filepath="./buildme-workflows/$filename"
    
    mkdir -p "./buildme-workflows"
    echo "$markdown_content" > "$filepath"
    
    copy_to_clipboard "$markdown_content"
    
    echo "✅ Workflow exported successfully!"
    echo "📁 Saved to: $filepath"
    echo "📋 Copied to clipboard - ready to paste anywhere!"
    
    echo "💡 Paste into:"
    echo "   • Slack/Discord messages"
    echo "   • Email compose window"
    echo "   • GitHub issues/discussions"
    echo "   • Team documentation"
    echo "   • Any messaging platform"
}


extract_recorded_workflow() {
    local workflow_name="$1"
    local workflow_file=""
    
    local found_files=()
    for f in "$HOME"/.buildme_record_*"$workflow_name"*_*.sh; do
        if [[ -f "$f" ]]; then
            found_files+=("$f")
        fi
    done
    
    if [[ ${#found_files[@]} -eq 0 ]]; then
        echo "❌ Workflow '$workflow_name' not found." >&2
        echo "💡 Available workflows:" >&2
        list_available_workflows >&2
        return 1
    fi
    
    workflow_file="${found_files[1]}"
    
    local workflow_data=""
    local start_time=""
    local end_time=""
    local command_count=0
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})\ (.+)$ ]]; then
            local timestamp="${match[1]}"
            local command="${match[2]}"
            
            if [[ "$command" =~ ^buildme\ record ]]; then
                continue
            fi
            
            [[ -z "$start_time" ]] && start_time="$timestamp"
            end_time="$timestamp"
            
            workflow_data+="COMMAND:$command\n"
            workflow_data+="STATUS:executed\n"
            workflow_data+="TIMESTAMP:$timestamp\n"
            ((command_count++))
        else
            echo "Line did not match expected format: $line" >&2
        fi
    done < "$workflow_file"
    
    if [[ $command_count -eq 0 ]]; then
        echo "❌ No commands found in recording" >&2
        return 1
    fi
    
    workflow_data+="START_TIME:$start_time\n"
    workflow_data+="END_TIME:$end_time\n"
    workflow_data+="DIRECTORY:$(pwd)\n"
    
    echo "$workflow_data"
}


extract_recent_session() {
    if [[ ! -f ~/.last_buildme_session.sh ]]; then
        echo "❌ No recent buildme session found." >&2
        echo "💡 Run a buildme command first, then try sharing." >&2
        return 1
    fi
    
    local session_data=""
    local original_request=""
    local timestamp=""
    local commands_found=false
    local temp_all_commands=$(mktemp)
    local temp_unique_commands=$(mktemp)

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        if [[ "$line" =~ ^TIMESTAMP=\"(.+)\"$ ]]; then
            timestamp="${match[1]}"
        elif [[ "$line" =~ ^ORIGINAL_REQUEST=\"(.+)\"$ ]]; then
            original_request="${match[1]}"
        elif [[ "$line" =~ ^GENERATED_COMMANDS=\"(.+)\"$ ]]; then
            local commands="${match[1]}"
            
            if [[ "$commands" == *"&&"* ]]; then
                local IFS='&&'
                local cmd_array=($commands)
                for cmd in "${cmd_array[@]}"; do
                    cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    if [[ -n "$cmd" ]]; then
                        echo "$cmd" >> "$temp_all_commands"
                        commands_found=true
                    fi
                done
            elif [[ "$commands" == *";"* ]]; then
                local IFS=';'
                local cmd_array=($commands)
                for cmd in "${cmd_array[@]}"; do
                    cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    if [[ -n "$cmd" ]]; then
                        echo "$cmd" >> "$temp_all_commands"
                        commands_found=true
                    fi
                done
            else
                cmd_to_check=$(echo "$commands" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [[ -n "$cmd_to_check" ]]; then
                    echo "$cmd_to_check" >> "$temp_all_commands"
                    commands_found=true
                fi
            fi
        fi
    done < ~/.last_buildme_session.sh
    
    if [[ "$commands_found" == false ]]; then
        rm -f "$temp_all_commands" "$temp_unique_commands"
        echo "❌ No commands found in session file" >&2
        return 1
    fi
    
    sort -u "$temp_all_commands" > "$temp_unique_commands"
    
    while IFS= read -r cmd; do
        [[ -n "$cmd" ]] || continue
        session_data+="COMMAND:$cmd\n"
        session_data+="STATUS:executed\n"
        session_data+="TIMESTAMP:$timestamp\n"
    done < "$temp_unique_commands"
    
    rm -f "$temp_all_commands" "$temp_unique_commands"
    
    session_data+="ORIGINAL_REQUEST:$original_request\n"
    session_data+="TIMESTAMP:$timestamp\n"
    session_data+="DIRECTORY:$(pwd)\n"
    
    echo "$session_data"
}

extract_terminal_history() {
    local lines="${1:-10}"
    local filter_meaningful="${2:-true}"
    
    if [[ ! -f "$BUILDME_HISTORY_FILE" ]]; then
        echo "❌ No command history available." >&2
        return 1
    fi
    
    local commands=""
    if [[ "$filter_meaningful" == "true" ]]; then
        commands=$(tail -n "$((lines * 3))" "$BUILDME_HISTORY_FILE" | \
                  cut -d'|' -f2- | \
                  grep -v "^buildme" | \
                  grep -v "^cd " | \
                  grep -v "^ls" | \
                  grep -v "^cat " | \
                  grep -v "^pwd" | \
                  grep -v "source ~/.zshrc" | \
                  tail -n "$lines")
    else
        commands=$(tail -n "$lines" "$BUILDME_HISTORY_FILE" | cut -d'|' -f2-)
    fi
    
    if [[ -z "$commands" ]]; then
        echo "❌ No meaningful commands found in recent history." >&2
        echo "💡 Try: buildme share --history $lines --no-filter" >&2
        return 1
    fi
    
    local history_data=""
    local counter=1
    
    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        history_data+="COMMAND:$cmd\n"
        history_data+="STATUS:executed\n"
        ((counter++))
    done <<< "$commands"
    
    history_data+="TIMESTAMP:$(date)\n"
    history_data+="DIRECTORY:$(pwd)\n"
    
    echo "$history_data"
}

list_available_workflows() {
    echo "Available recordings:"
    local found=0
    setopt local_options nullglob
    
    for file in "$HOME"/.buildme_record_*.sh; do
        if [[ -f "$file" ]]; then
            found=1
            local basename=$(basename "$file")
            local name_part=""
            
            # Match the same pattern as record.zsh
            if [[ "$basename" =~ ^\.buildme_record_(.+)_[0-9]+\.sh$ ]]; then
                name_part="${match[1]}"
                echo "  - $name_part"
            elif [[ "$basename" =~ ^\.buildme_record_([0-9]+)\.sh$ ]]; then
                local timestamp="${match[1]}"
                local date_str=$(date -r "$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
                echo "  - (unnamed-$timestamp) - $date_str"
            fi
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        echo "No recordings found"
    fi
}

copy_to_clipboard() {
    local content="$1"
    
    if command -v pbcopy >/dev/null 2>&1; then
        # macOS
        echo "$content" | pbcopy
    elif command -v xclip >/dev/null 2>&1; then
        # Linux with xclip
        echo "$content" | xclip -selection clipboard
    elif command -v xsel >/dev/null 2>&1; then
        # Linux with xsel
        echo "$content" | xsel --clipboard --input
    elif command -v clip.exe >/dev/null 2>&1; then
        # Windows (WSL)
        echo "$content" | clip.exe
    else
        echo "⚠️  Clipboard copy not available (install xclip, xsel, or pbcopy)"
        return 1
    fi
}

generate_workflow_markdown() {
    local workflow_data="$1"
    local workflow_title="$2"
    local data_source="$3"
    local include_env="$4"
    local include_output="$5"
    local no_ai_summary="$6"
    local target_os="$7"
    local conversion_notes="$8"
    
    local start_time=""
    local end_time=""
    local directory=""
    local original_request=""
    local commands_section=""
    local counter=1
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        if [[ "$line" =~ ^START_TIME:(.+)$ ]]; then
            start_time="${match[1]}"
        elif [[ "$line" =~ ^END_TIME:(.+)$ ]]; then
            end_time="${match[1]}"
        elif [[ "$line" =~ ^DIRECTORY:(.+)$ ]]; then
            directory="${match[1]}"
        elif [[ "$line" =~ ^ORIGINAL_REQUEST:(.+)$ ]]; then
            original_request="${match[1]}"
        elif [[ "$line" =~ ^COMMAND:(.+)$ ]]; then
            local command="${match[1]}"
            local cmd_status=""
            local output=""
            local timestamp=""
            
            if IFS= read -r next_line && [[ "$next_line" =~ ^STATUS:(.+)$ ]]; then
                cmd_status="${match[1]}"
            fi
            if [[ "$include_output" == "true" ]] && IFS= read -r next_line && [[ "$next_line" =~ ^OUTPUT:(.+)$ ]]; then
                output="${match[1]}"
            fi
            if IFS= read -r next_line && [[ "$next_line" =~ ^TIMESTAMP:(.+)$ ]]; then
                timestamp="${match[1]}"
            fi
            
            local status_icon="✅"
            local status_text="Success"
            if [[ "$cmd_status" == "failure" ]] || [[ "$cmd_status" == "error" ]]; then
                status_icon="❌"
                status_text="Failed"
            fi
            
            commands_section+="### $counter. Command execution\n"
            commands_section+="\`\`\`bash\n$command\n\`\`\`\n"
            commands_section+="$status_icon **$status_text**"
            
            if [[ -n "$output" && "$include_output" == "true" ]]; then
                commands_section+=" - Output: \`$output\`"
            fi
            
            commands_section+="\n\n"
            ((counter++))
        fi
    done <<< "$workflow_data"
    
    local duration=""
    if [[ -n "$start_time" && -n "$end_time" ]]; then
        duration="$(calculate_duration "$start_time" "$end_time")"
    fi
    
    local ai_summary=""
    if [[ "$no_ai_summary" != "true" ]]; then
        ai_summary=$(generate_ai_summary "$workflow_data" "$original_request")
    fi

    local env_info=""
    if [[ "$include_env" == "true" ]]; then
        env_info=$(detect_environment)
    fi
    
    local markdown=""
    
    markdown+="# 🚀 Workflow: $workflow_title\n\n"
    markdown+="**Shared by:** $(whoami)\n"
    markdown+="**Generated:** $(date)\n"
    markdown+="**Source:** $data_source"
    [[ -n "$duration" ]] && markdown+=" ($duration)"
    markdown+="\n"
    markdown+="**Working Directory:** ${directory:-$(pwd)}\n"
    markdown+="**Environment:** $(uname -s) ($(uname -r))\n\n"
    
    if [[ -n "$ai_summary" ]]; then
        markdown+="## 📋 Summary\n$ai_summary\n\n"
    fi
    
    if [[ -n "$conversion_notes" ]]; then
        markdown+="## 🔄 OS Conversion Notes\n"
        markdown+="$conversion_notes\n\n"
        markdown+="⚠️ **Note:** Some commands may require installation of equivalent tools on the target OS.\n\n"
    fi
    
    if [[ -n "$original_request" ]]; then
        markdown+="## 🤖 Original Request\n> $original_request\n\n"
    fi
    
    markdown+="## 🔧 Commands Executed\n\n$commands_section"
    
    if [[ -n "$env_info" ]]; then
        markdown+="## 🌍 Environment Information\n$env_info\n"
    fi
    
    markdown+="## 🔄 How to Reproduce\n\n"
    markdown+="### Prerequisites\n"
    markdown+="- Access to terminal/command line\n"
    markdown+="- Required tools and dependencies (see environment info above)\n"
    if [[ -n "$directory" && "$directory" != "$(pwd)" ]]; then
        markdown+="- Navigate to working directory: \`cd $directory\`\n"
    fi
    markdown+="\n### Steps\n"
    markdown+="1. Copy each command from the 'Commands Executed' section\n"
    markdown+="2. Run them in sequence in your terminal\n"
    markdown+="3. Verify each step completes successfully before proceeding\n\n"
    
    markdown+="## 🔗 Generated by buildme\n"
    markdown+="- **Tool:** buildme v$(get_buildme_version)\n"
    markdown+="- **Timestamp:** $(date)\n"
    markdown+="- **Share ID:** $(generate_share_id)\n\n"
    markdown+="---\n"
    markdown+="*Workflow saved to file and copied to clipboard*\n"
    
    echo "$markdown"
}

generate_ai_summary() {
    local workflow_data="$1"
    local original_request="$2"
    
    local commands_only=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^COMMAND:(.+)$ ]]; then
            commands_only+="${match[1]}\n"
        fi
    done <<< "$workflow_data"
    
    local summary_prompt="You are a technical documentation expert. Analyze this terminal workflow and provide a concise, helpful summary in 2-3 sentences.

Focus on:
- What the workflow accomplishes
- Key tools or technologies involved
- The main purpose or outcome

Commands executed:
$commands_only"

    if [[ -n "$original_request" ]]; then
        summary_prompt+="\n\nOriginal user request: $original_request"
    fi

    summary_prompt+="\n\nProvide only the summary, no extra formatting or explanations."
    
    local key=$(get_api_key "gpt" 2>/dev/null)
    if [[ -n "$key" ]]; then
        local summary=$(buildme_generate "$summary_prompt" "$key" "gpt-4o-mini" 2>/dev/null)
        echo "$summary"
    else
        echo "Workflow containing $(echo "$commands_only" | wc -l | tr -d ' ') terminal commands."
    fi
}

detect_environment() {
    local env_info=""
    
    env_info+="- **Operating System:** $(uname -s) $(uname -r)\n"
    
    if [[ -n "$SHELL" ]]; then
        local shell_version=""
        case "$(basename "$SHELL")" in
            "zsh")
                shell_version=$($SHELL --version 2>/dev/null | head -n1)
                ;;
            "bash")
                shell_version=$($SHELL --version 2>/dev/null | head -n1)
                ;;
        esac
        env_info+="- **Shell:** $SHELL ($shell_version)\n"
    fi
    
    env_info+="- **Working Directory:** $(pwd)\n"
    
    if command -v node >/dev/null 2>&1; then
        env_info+="- **Node.js:** $(node --version 2>/dev/null)\n"
    fi
    if command -v npm >/dev/null 2>&1; then
        env_info+="- **npm:** $(npm --version 2>/dev/null)\n"
    fi
    if command -v python3 >/dev/null 2>&1; then
        env_info+="- **Python:** $(python3 --version 2>/dev/null)\n"
    fi
    if command -v pip3 >/dev/null 2>&1; then
        env_info+="- **pip:** $(pip3 --version 2>/dev/null | cut -d' ' -f1-2)\n"
    fi
    if command -v docker >/dev/null 2>&1; then
        env_info+="- **Docker:** $(docker --version 2>/dev/null)\n"
    fi
    if command -v git >/dev/null 2>&1; then
        env_info+="- **Git:** $(git --version 2>/dev/null)\n"
    fi
    if command -v brew >/dev/null 2>&1; then
        env_info+="- **Homebrew:** $(brew --version 2>/dev/null | head -n1)\n"
    fi

    env_info+="- **buildme:** v$(get_buildme_version)\n"
    
    echo "$env_info"
}

detect_current_os() {
    case "$(uname -s)" in
        "Darwin")
            echo "macos"
            ;;
        "Linux")
            if command -v apt >/dev/null 2>&1; then
                echo "ubuntu"
            elif command -v yum >/dev/null 2>&1; then
                echo "centos"
            elif command -v dnf >/dev/null 2>&1; then
                echo "fedora"
            else
                echo "linux"
            fi
            ;;
        "MINGW"*|"CYGWIN"*|"MSYS"*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

calculate_duration() {
    local start_time="$1"
    local end_time="$2"
    
    if command -v date >/dev/null 2>&1; then
        local start_epoch=$(date -d "$start_time" +%s 2>/dev/null || echo "0")
        local end_epoch=$(date -d "$end_time" +%s 2>/dev/null || echo "0")
        
        if [[ "$start_epoch" -gt 0 && "$end_epoch" -gt 0 ]]; then
            local duration_seconds=$((end_epoch - start_epoch))
            if [[ $duration_seconds -lt 60 ]]; then
                echo "${duration_seconds}s"
            elif [[ $duration_seconds -lt 3600 ]]; then
                echo "$((duration_seconds / 60))m $((duration_seconds % 60))s"
            else
                echo "$((duration_seconds / 3600))h $((duration_seconds % 3600 / 60))m"
            fi
        fi
    fi
}

get_buildme_version() {
    echo "1.0.0"
}

generate_share_id() {
    echo "share-$(date +%s)-$(openssl rand -hex 4 2>/dev/null || echo $(( RANDOM * RANDOM )))"
}

convert_commands_for_os() {
    local target_os="$1"
    local workflow_data="$2"
    local source_os="$3"
    local converted_data=""
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        if [[ "$line" =~ ^COMMAND:(.+)$ ]]; then
            local command="${match[1]}"
            local converted_command=$(convert_single_command "$command" "$source_os" "$target_os")
            converted_data+="COMMAND:$converted_command\n"
        else
            converted_data+="$line\n"
        fi
    done <<< "$workflow_data"
    
    echo "$converted_data"
}

convert_single_command() {
    local command="$1"
    local source_os="$2"
    local target_os="$3"
    
    if [[ "$source_os" == "$target_os" ]]; then
        echo "$command"
        return 0
    fi
    
    local key=$(get_api_key "gpt" 2>/dev/null)
    if [[ -z "$key" ]]; then
        echo "⚠️ No API key available, using basic conversion" >&2
        convert_single_command_basic "$command" "$source_os" "$target_os"
        return $?
    fi
    
    local conversion_prompt="You are an expert system administrator familiar with commands across different operating systems.

Convert this $source_os command to work on $target_os:
\`$command\`

Requirements:
- Provide ONLY the converted command, no explanations
- Use the most appropriate equivalent for $target_os
- If multiple tools exist, choose the most commonly installed one
- Maintain the same functionality and behavior
- For package managers: $source_os → $target_os conversions:
  * macOS brew → Ubuntu/Linux apt-get or apt
  * macOS brew → CentOS/RHEL yum or dnf  
  * Ubuntu apt → macOS brew
  * Ubuntu apt → CentOS yum/dnf
- For clipboard: pbcopy/pbpaste → xclip or xsel on Linux
- For file operations: open → xdg-open on Linux, start on Windows
- If no direct equivalent exists, provide the closest alternative

Convert only the command itself. Output format: just the converted command."

    local converted=$(buildme_generate "$conversion_prompt" "$key" "gpt-4o-mini" 2>/dev/null)
    local llm_exit_code=$?
    
    if [[ $llm_exit_code -eq 0 && -n "$converted" ]]; then
        converted=$(echo "$converted" | sed 's/^```[a-z]*//; s/```$//; s/^`//; s/`$//' | tr -d '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        echo "$converted"
    else
        echo "⚠️ LLM conversion failed, using basic conversion" >&2
        convert_single_command_basic "$command" "$source_os" "$target_os"
    fi
}

convert_single_command_basic() {
    local command="$1"
    local source_os="$2"
    local target_os="$3"
    
    local converted="$command"
    
    case "$target_os" in
        "macos")
            case "$source_os" in
                "linux"|"ubuntu"|"centos"|"fedora")
                    converted=${converted//xclip -selection clipboard/pbcopy}
                    converted=${converted//xclip -selection clipboard -o/pbpaste}
                    converted=${converted//xsel --clipboard --input/pbcopy}
                    converted=${converted//xsel --clipboard --output/pbpaste}
                    converted=${converted//xdg-open/open}
                    converted=${converted//apt install/brew install}
                    converted=${converted//apt-get install/brew install}
                    converted=${converted//yum install/brew install}
                    converted=${converted//dnf install/brew install}
                    converted=${converted//systemctl/brew services}
                    converted=${converted//ls --color=auto/ls -G}
                    ;;
                "windows")          
                    converted=${converted//clip.exe/pbcopy}
                    converted=${converted//dir/ls}
                    converted=${converted//type/cat}
                    converted=${converted//start/open}
                    converted=${converted//del/rm}
                    converted=${converted//copy/cp}
                    converted=${converted//move/mv}
                    ;;
            esac
            ;;
        "linux"|"ubuntu")
            case "$source_os" in
                "macos")
                    converted=${converted//pbcopy/xclip -selection clipboard}
                    converted=${converted//pbpaste/xclip -selection clipboard -o}
                    converted=${converted//open/xdg-open}
                    converted=${converted//brew install/apt install}
                    converted=${converted//brew services/systemctl}
                    converted=${converted//ls -G/ls --color=auto}
                    ;;
                "windows")
                    converted=${converted//clip.exe/xclip -selection clipboard}
                    converted=${converted//dir/ls}
                    converted=${converted//type/cat}
                    converted=${converted//start/xdg-open}
                    converted=${converted//del/rm}
                    converted=${converted//copy/cp}
                    converted=${converted//move/mv}
                    ;;
            esac
            ;;
        "centos"|"fedora")
            case "$source_os" in
                "macos")
                    converted=${converted//pbcopy/xclip -selection clipboard}
                    converted=${converted//pbpaste/xclip -selection clipboard -o}
                    converted=${converted//open/xdg-open}
                    converted=${converted//brew install/yum install}
                    [[ "$target_os" == "fedora" ]] && converted=${converted//yum install/dnf install}
                    converted=${converted//brew services/systemctl}
                    converted=${converted//ls -G/ls --color=auto}
                    ;;
                "ubuntu"|"linux")
                    converted=${converted//apt install/yum install}
                    converted=${converted//apt-get install/yum install}
                    [[ "$target_os" == "fedora" ]] && converted=${converted//yum install/dnf install}
                    ;;
            esac
            ;;
        "windows")
            case "$source_os" in
                "macos")
                    converted=${converted//pbcopy/clip.exe}
                    converted=${converted//pbpaste/powershell Get-Clipboard}
                    converted=${converted//open/start}
                    converted=${converted//ls/dir}
                    converted=${converted//cat/type}
                    converted=${converted//rm/del}
                    converted=${converted//cp/copy}
                    converted=${converted//mv/move}
                    ;;
                "linux"|"ubuntu"|"centos"|"fedora") 
                    converted=${converted//xclip -selection clipboard/clip.exe}
                    converted=${converted//xdg-open/start}
                    converted=${converted//ls/dir}
                    converted=${converted//cat/type}
                    converted=${converted//rm/del}
                    converted=${converted//cp/copy}
                    converted=${converted//mv/move}
                    ;;
            esac
            ;;
    esac
    
    echo "$converted"
}
