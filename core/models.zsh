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