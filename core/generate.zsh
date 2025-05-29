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