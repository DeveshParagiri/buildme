# --- buildme.plugin.zsh ---

# Source the history tracking file
source "${0:A:h}/buildme_history.zsh"
# Source the starter functionality
source "${0:A:h}/buildme_starter.zsh"

# starter_dir="$HOME/.buildme_starters"
# mkdir -p "$starter_dir"

get_openai_key() {
  if [[ -n "$OPENAI_API_KEY" ]]; then
    echo "$OPENAI_API_KEY"
  elif command -v security &>/dev/null; then
    security find-generic-password -a "$USER" -s "openai_api_key" -w 2>/dev/null
  elif [[ -f "$HOME/.openai" ]]; then
    grep -E "^OPENAI_API_KEY=" "$HOME/.openai" | cut -d= -f2-
  else
    return 1
  fi
}

get_deepseek_key() {
  if [[ -n "$DEEPSEEK_API_KEY" ]]; then
    echo "$DEEPSEEK_API_KEY"
  elif [[ -f "$HOME/.deepseek" ]]; then
    grep -E "^DEEPSEEK_API_KEY=" "$HOME/.deepseek" | cut -d= -f2-
  else
    return 1
  fi
}

get_api_key() {
  local provider="$1"
  if [[ "$provider" == "deepseek" ]]; then
    get_deepseek_key
  else
    get_openai_key
  fi
}

buildme_init() {
  echo "🧠 Which provider do you want to set up?"
  echo "1) OpenAI only"
  echo "2) DeepSeek only"
  echo "3) Both"
  echo "4) Cancel"
  read -r "?Choose 1, 2, 3, or 4: " choice

  if [[ "$choice" == "1" || "$choice" == "3" ]]; then
    echo ""
    echo "🔐 Setting up OpenAI API key."
    read -r "?Enter your OpenAI API key: " openai_key

    echo "Where do you want to store it?"
    echo "1) macOS Keychain (recommended)"
    echo "2) Plaintext file at ~/.openai"
    echo "3) Just export manually"
    read -r "?Choose 1, 2 or 3: " store_choice

    case "$store_choice" in
      1)
        security add-generic-password -a "$USER" -s "openai_api_key" -w "$openai_key"
        echo "✅ Saved in macOS Keychain."
        ;;
      2)
        echo "OPENAI_API_KEY=$openai_key" > ~/.openai
        chmod 600 ~/.openai
        echo "✅ Saved to ~/.openai"
        ;;
      *)
        echo "❗ Remember to export OPENAI_API_KEY manually."
        ;;
    esac
  fi

  if [[ "$choice" == "2" || "$choice" == "3" ]]; then
    echo ""
    echo "🔐 Setting up DeepSeek API key."
    read -r "?Enter your DeepSeek API key: " deepseek_key
    echo "DEEPSEEK_API_KEY=$deepseek_key" > ~/.deepseek
    chmod 600 ~/.deepseek
    echo "✅ Saved to ~/.deepseek"
  fi

  if [[ "$choice" == "4" ]]; then
    echo "🚫 Cancelled setup."
    return 1
  fi
}

buildme_generate() {
  local prompt="$1"
  local key="$2"
  local model="${3:-gpt-4o-mini}"

  [[ "$model" == "openai" ]] && model="gpt-4o-mini"

  local system_prompt="You are a helpful CLI assistant. Convert natural language prompts into accurate, minimal shell commands. Output only the commands. Important rules:
1. Combine all commands into a single line using && between commands
2. Never use shell-switching commands like 'source venv/bin/activate'
3. Use comments like '# activate the virtual environment manually' instead
4. Never split commands across multiple lines"

  if [[ "$model" == "deepseek" ]]; then
    jq -n \
      --arg model "deepseek-chat" \
      --arg system "$system_prompt" \
      --arg user "$prompt" \
      '{model: $model, stream: false, messages: [{role: "system", content: $system}, {role: "user", content: $user}]}' \
      | curl -s https://api.deepseek.com/chat/completions \
          -H "Authorization: Bearer $key" \
          -H "Content-Type: application/json" \
          -d @- | jq -r '.choices[0].message.content'
  elif [[ "$model" == "local" ]]; then
    # Use a simplified but effective system prompt for local models
    local local_system_prompt="You are a CLI command generator. Generate ONLY shell commands.

RULES:
- Output format: command_here
- NO explanations or extra text
- Use full paths when needed
- For Oh My Zsh: ~/.oh-my-zsh/ is the base path
- macOS user, use brew for packages
- Multiple commands: join with &&

EXAMPLES:
change directory to home: cd ~
list files: ls -la
install package: brew install package_name
go to oh-my-zsh custom plugins: cd ~/.oh-my-zsh/custom/plugins

Generate the command:"

    # Create JSON manually to avoid escaping issues
    local temp_file=$(mktemp)
    cat > "$temp_file" << EOF
{
  "model": "TheBloke/phi-2-GGUF",
  "temperature": 0.1,
  "max_tokens": 100,
  "stream": false,
  "messages": [
    {
      "role": "system",
      "content": "$(echo "$local_system_prompt" | sed 's/"/\\"/g' | tr '\n' ' ')"
    },
    {
      "role": "user",
      "content": "$prompt"
    }
  ]
}
EOF
    
    local response
    response=$(curl -s http://localhost:1234/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d @"$temp_file")
    
    # Clean up temp file
    rm -f "$temp_file"
    
    # Extract and clean the response
    local content
    content=$(echo "$response" | jq -r '.choices[0].message.content // empty')
    
    # Clean up the response (remove any extra formatting)
    echo "$content" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | head -n 1
  else
    jq -n \
      --arg model "$model" \
      --arg system "$system_prompt" \
      --arg user "$prompt" \
      '{model: $model, temperature: 0.4, messages: [{role: "system", content: $system}, {role: "user", content: $user}]}' \
      | curl -s https://api.openai.com/v1/chat/completions \
          -H "Authorization: Bearer $key" \
          -H "Content-Type: application/json" \
          -d @- | jq -r '.choices[0].message.content'
  fi
}

buildme_run() {
  local script="$1"
  echo ""
  echo "❓ Do you want to run these commands? [y/N]"
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo ""
    echo "$(date '+%Y-%m-%d %H:%M:%S')|$script" > ~/.last_buildme_commands.sh
    # zsh -i -c "$script"
    eval "$script"
  else
    echo "🚫 Skipped running commands."
  fi
}

buildme_run_stepwise() {
  local script="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S')|$script" > ~/.last_buildme_commands.sh

  exec 3<&0
  local run_all=0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    echo "➡️  $line"

    if [[ "$run_all" -eq 1 ]]; then
      # zsh -i -c "$line"
      eval "$line"
      continue
    fi

    echo -n "?Run this? [y/n/a/q] "
    read -r confirm <&3

    case "$confirm" in
      [Yy]|"") eval "$line" ;;
      [Nn]) echo "⏭️  Skipped." ;;
      [Aa]) run_all=1; eval "$line" ;;
      [Qq]) echo "👋 Exiting."; break ;;
      *) echo "❓ Unknown choice, skipping." ;;
    esac
  done <<< "$script"

  exec 0<&3
}

buildme_undo() {
    local user_instruction="$*"
    user_instruction="${user_instruction#undo}"
    
    # Get both contexts
    local buildme_cmds=""
    local history_cmds=""
    
    if [[ -f ~/.last_buildme_commands.sh ]]; then
        buildme_cmds="Last buildme commands:\n$(cat ~/.last_buildme_commands.sh)"
    fi
    
    if [[ -f "$BUILDME_HISTORY_FILE" ]]; then
        history_cmds="Recent terminal history:\n$(tail -n 10 "$BUILDME_HISTORY_FILE")"
    fi
    
    # If no history at all
    if [[ -z "$buildme_cmds" && -z "$history_cmds" ]]; then
        echo "⚠️  No command history found."
        return 1
    fi
    
    # Construct the prompt with both contexts
    local undo_prompt="You are a helpful CLI assistant that generates commands to undo previous actions. 
Given the following command history, generate shell commands to reverse actions you think the user wants to undo based on the commands history.

IMPORTANT RULES:
1. Output only the shell commands needed to undo the actions
2. Combine commands with && when appropriate
3. Be careful with file/directory operations
4. If the user provides specific instructions, follow them exactly
5. If the user mentions 'terminal history' or 'from history', ONLY use commands from the 'Recent terminal history' section
6. If the user mentions 'buildme' or 'last buildme', ONLY use commands from the 'Last buildme commands' section
7. If no specific instructions, use the most recent commands from either section based on timestamps and undo what you think the user might want to undo
8. Always check timestamps to determine the most recent commands
9. Do not mix commands from different sections unless explicitly requested

User instruction: $user_instruction

Command history:
$buildme_cmds

$history_cmds"

    # Debug print
    echo "🔍 Debug: Prompt being sent to model:"
    echo "──────────────────────────────"
    echo "$undo_prompt"
    echo "──────────────────────────────"
    echo ""

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

buildme_model_list() {
  echo "🤖 Available Models:"
  echo "══════════════════════════════════════════════════════════════"
  
  # Check OpenAI models
  local openai_key=$(get_openai_key 2>/dev/null)
  if [[ -n "$openai_key" ]]; then
    echo "✅ OpenAI Models (configured):"
    echo "   • gpt-4o-mini (default)"
    echo "   • gpt-4o"
    echo "   • gpt-3.5-turbo"
    echo "   • gpt-4-turbo"
  else
    echo "❌ OpenAI Models (not configured):"
    echo "   • gpt-4o-mini, gpt-4o, gpt-3.5-turbo, gpt-4-turbo"
    echo "   💡 Run 'buildme init' to configure"
  fi
  
  echo ""
  
  # Check DeepSeek model
  local deepseek_key=$(get_deepseek_key 2>/dev/null)
  if [[ -n "$deepseek_key" ]]; then
    echo "✅ DeepSeek Model (configured):"
    echo "   • deepseek"
  else
    echo "❌ DeepSeek Model (not configured):"
    echo "   • deepseek"
    echo "   💡 Run 'buildme init' to configure"
  fi
  
  echo ""
  
  # Check Local model
  if curl -s --connect-timeout 2 http://localhost:1234/v1/models >/dev/null 2>&1; then
    echo "✅ Local Model (available):"
    echo "   • local (running on localhost:1234)"
    
    # Try to get the actual model name
    local model_info
    model_info=$(curl -s --connect-timeout 2 http://localhost:1234/v1/models 2>/dev/null | jq -r '.data[0].id // empty' 2>/dev/null)
    if [[ -n "$model_info" && "$model_info" != "null" ]]; then
      echo "   📋 Current model: $model_info"
    fi
  else
    echo "❌ Local Model (not available):"
    echo "   • local (no server detected on localhost:1234)"
    echo "   💡 Start your local LLM server (e.g., LM Studio, Ollama)"
  fi
  
  echo ""
  echo "Usage: buildme --model <model_name> \"your prompt\""
  echo "Example: buildme --model deepseek \"create a python file\""
}

buildme() {
  if [[ "$1" == "init" ]]; then
    buildme_init
    return 0
  fi

  if [[ "$1" == "history" ]]; then
    shift
    buildme_history "$@"
    return 0
  fi

  if [[ "$1" == "clear-history" ]]; then
    buildme_clear_history
    return 0
  fi

  if [[ "$1" == "starter" ]]; then
    shift
    buildme_starter "$@"
    return 0
  fi

  if [[ "$1" == "model" ]]; then
    shift
    if [[ "$1" == "list" ]]; then
      buildme_model_list
      return 0
    else
      echo "❌ Unknown model command. Use: buildme model list"
      return 1
    fi
  fi

  if [[ "$1" == "undo" ]]; then
    shift
    if [[ "$1" == "--from-history" ]]; then
        shift
        buildme_undo_from_history "$@"
    else
        buildme_undo "$@"
    fi
    return 0
  fi

  if [[ "$1" == "--help" ]]; then
    cat <<EOF

🔧 buildme – generate shell workflows using AI

Usage:
  buildme [options] "your task description"

Options:
  -r, --run            Auto-run the generated commands after confirmation
  --step               Run each command one-by-one with confirmation
  --model <name>       Choose model (gpt-4o-mini, deepseek, local, gpt-3.5-turbo, etc.)
  init                 Interactive setup for API keys (OpenAI / DeepSeek)
  undo [description]   Try to undo last buildme command with optional guidance
  starter <cmd>        Manage project starters
  history [n]          Show last n commands (default: 10)
  clear-history        Clear command history
  model list           Show all available models and their status
  --help               Show this help message

Starter Commands:
  starter list         List all available starters (built-in and custom)
  starter new <name> <target> [--var=value]
                      Create new project from a starter template
  starter init <name> <source> [--instructions="..."]
                      Create a starter from GitHub repo or local directory
  starter delete <name>
                      Delete a starter template

Model Commands:
  model list           Show all configured models and their availability

Examples:
  buildme "create and activate a python virtualenv"
  buildme --step "install packages and update requirements"
  buildme --model deepseek "set up a React project"
  buildme --model local "change to home directory"
  buildme model list
  buildme undo "remove the files we just created"
  
  # Starter examples
  buildme starter list
  buildme starter new fastapi my-api
  buildme starter init my-template ./existing-project
  buildme starter init fastapi-starter https://github.com/user/repo
  buildme starter delete old-template
  
  # History examples
  buildme history 20
  buildme clear-history

EOF
    return 0
  fi

  local run=1
  local step=0
  local model="gpt-4o-mini"
  local prompt=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--run) run=1; shift ;;
      --step) step=1; shift ;;
      --model) model="$2"; shift 2 ;;
      *) prompt+="$1 "; shift ;;
    esac
  done

  [[ -z "$prompt" ]] && echo "❌ No prompt provided." && return 1

  local key=$(get_api_key "$model")
  [[ -z "$key" ]] && echo "❌ API key not found. Run: buildme init" && return 1

  echo "🧠 Thinking..."
  local commands=$(buildme_generate "$prompt" "$key" "$model")

  echo ""
  echo "💡 Suggested commands:"
  echo "──────────────────────────────"
  echo "$commands" \
    | sed 's/^```bash//; s/^```//g' \
    | tr '&' '\n' \
    | sed 's/&&/&&/g' \
    | sed '/^$/d' \
    | sed 's/^ */  /'
  echo "──────────────────────────────"

  if [[ "$run" -eq 1 ]]; then
    if [[ "$step" -eq 1 ]]; then
      buildme_run_stepwise "$commands"
    else
      buildme_run "$commands"
    fi
  fi
}