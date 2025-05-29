buildme_generate() {
  local prompt="$1"
  local key="$2"
  local model="${3:-gpt-4o-mini}"

  [[ "$model" == "openai" ]] && model="gpt-4o-mini"

  local system_prompt="You are an expert DevOps assistant that converts natural language into intelligent shell command workflows. You understand development workflows, git practices, and common automation patterns.

CORE INTELLIGENCE:
- Analyze the intent behind user requests, not just literal words
- Understand git workflows, development patterns, and automation tasks
- Provide contextually appropriate commands that follow best practices
- Keep commands simple and practical

GIT & DEVELOPMENT INTELLIGENCE:
- 'write good git commit' → just the commit command with a descriptive message
- 'deploy' → understand build processes and deployment patterns  
- 'setup project' → recognize tech stacks and create proper initialization
- 'clean up' → understand context-appropriate cleanup
- 'fix issues' → run appropriate diagnostic and fix commands

COMMAND GENERATION RULES:
1. Output only shell commands, one per line
2. Use && only for simple 2-3 command chains when truly needed
3. Keep commands minimal and focused
4. Don't add extra steps unless specifically requested
5. Focus on the exact action requested

EXAMPLES OF SMART INTERPRETATION:
- 'write good git commit' → git commit -m "Improve core functionality"
- 'deploy to production' → git push && npm run build
- 'clean up branches' → git branch -d feature-branch
- 'setup react project' → npx create-react-app my-app
- 'run tests' → npm test
- 'check git status' → git status

Be minimal and focused on the exact request."

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
    local local_system_prompt="You are an intelligent CLI command generator that understands development workflows.

INTELLIGENCE:
- Understand git workflows: 'good commit' means just the commit command with good message
- Recognize project types and suggest appropriate tools
- Provide minimal, focused commands
- Be context-aware about what developers actually need

RULES:
- Output only shell commands, one per line
- Use && only when truly needed for workflow
- NO explanations or markdown
- Keep commands minimal and focused
- Don't add extra steps unless requested

EXAMPLES:
write good git commit: git commit -m \"Improve core functionality\"
setup react project: npx create-react-app my-app
deploy: npm run build && npm run deploy
run tests: npm test
clean up: git clean -fd

Generate minimal, focused commands:"

    # Create JSON manually to avoid escaping issues
    local temp_file=$(mktemp)
    cat > "$temp_file" << EOF
{
  "model": "TheBloke/phi-2-GGUF",
  "temperature": 0.1,
  "max_tokens": 150,
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