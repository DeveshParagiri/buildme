# --- models.zsh ---
#
# This script provides functions for managing API keys and model configurations
# for the 'buildme' tool. It supports OpenAI and DeepSeek API keys, as well as
# local model configurations.
#
# Features:
# - Retrieve and manage OpenAI and DeepSeek API keys from environment variables,
#   macOS Keychain, or configuration files.
# - List available models and indicate their configuration status.
# - Set and get the default model for the 'buildme' tool.
# - Clear all stored API keys and reset configurations.
# - Check the status of local model servers.
#
# Usage:
# - Use `get_api_key` to retrieve API keys for a specified provider.
# - Use `buildme_model_list` to list all available models.
# - Use `set_default_model` to set the default model.
# - Use `show_model_status` to display the current model configuration.
# - Use `clear_all_keys` to remove all stored API keys and reset configurations.
#
# Dependencies:
# - Requires macOS for Keychain operations.
# - Assumes access to `security` command for Keychain operations.
# - Uses `curl` for checking local server status.
# - Uses `jq` for parsing JSON responses from local servers.

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
  
  local default_model=$(get_default_model)
  
  local openai_key=$(get_openai_key 2>/dev/null)
  if [[ -n "$openai_key" ]]; then
    echo "✅ OpenAI Models (configured):"
    for model in "gpt-4o-mini" "gpt-4o" "gpt-3.5-turbo" "gpt-4-turbo"; do
      if [[ "$model" == "$default_model" ]]; then
        echo "   • $model (default)"
      else
        echo "   • $model"
      fi
    done
  else
    echo "❌ OpenAI Models (not configured):"
    echo "   • gpt-4o-mini, gpt-4o, gpt-3.5-turbo, gpt-4-turbo"
    echo "   💡 Run 'buildme init' to configure"
  fi
  
  echo ""
  
  local deepseek_key=$(get_deepseek_key 2>/dev/null)
  if [[ -n "$deepseek_key" ]]; then
    echo "✅ DeepSeek Model (configured):"
    if [[ "$default_model" == "deepseek" ]]; then
      echo "   • deepseek (default)"
    else
      echo "   • deepseek"
    fi
  else
    echo "❌ DeepSeek Model (not configured):"
    echo "   • deepseek"
    echo "   💡 Run 'buildme init' to configure"
  fi
  
  echo ""
  
  if curl -s --connect-timeout 2 http://localhost:1234/v1/models >/dev/null 2>&1; then
    echo "✅ Local Model (available):"
    if [[ "$default_model" == "local" ]]; then
      echo "   • local (running on localhost:1234) (default)"
    else
      echo "   • local (running on localhost:1234)"
    fi
    
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

get_default_model() {
  if [[ -f "$HOME/.buildme_config" ]]; then
    grep -E "^DEFAULT_MODEL=" "$HOME/.buildme_config" | cut -d= -f2-
  else
    echo "gpt-4o-mini"  # fallback default
  fi
}

set_default_model() {
  local model="$1"
  [[ -z "$model" ]] && echo "❌ Model name required" && return 1
  
  case "$model" in
    gpt-4o-mini|gpt-4o|gpt-3.5-turbo|gpt-4-turbo|deepseek|local)
      ;;
    *)
      echo "❌ Invalid model: $model"
      echo "Valid models: gpt-4o-mini, gpt-4o, gpt-3.5-turbo, gpt-4-turbo, deepseek, local"
      return 1
      ;;
  esac
  
  if [[ -f "$HOME/.buildme_config" ]]; then
    if grep -q "^DEFAULT_MODEL=" "$HOME/.buildme_config"; then
      sed -i.bak "s/^DEFAULT_MODEL=.*/DEFAULT_MODEL=$model/" "$HOME/.buildme_config"
      rm "$HOME/.buildme_config.bak" 2>/dev/null
    else
      echo "DEFAULT_MODEL=$model" >> "$HOME/.buildme_config"
    fi
  else
    echo "DEFAULT_MODEL=$model" > "$HOME/.buildme_config"
  fi
  
  echo "✅ Default model set to: $model"
}

show_model_status() {
  local default_model=$(get_default_model)
  echo "🤖 Current Model Configuration:"
  echo "══════════════════════════════"
  echo "📌 Default model: $default_model"
  echo ""
  
  if get_openai_key >/dev/null 2>&1; then
    echo "🔑 OpenAI API: ✅ Configured"
  else
    echo "🔑 OpenAI API: ❌ Not configured"
  fi
  
  if get_deepseek_key >/dev/null 2>&1; then
    echo "🔑 DeepSeek API: ✅ Configured"
  else
    echo "🔑 DeepSeek API: ❌ Not configured"
  fi
  
  if curl -s --connect-timeout 2 http://localhost:1234/v1/models >/dev/null 2>&1; then
    echo "🔑 Local Server: ✅ Running on localhost:1234"
    
    local model_info
    model_info=$(curl -s --connect-timeout 2 http://localhost:1234/v1/models 2>/dev/null | jq -r '.data[0].id // empty' 2>/dev/null)
    if [[ -n "$model_info" && "$model_info" != "null" ]]; then
      echo "   📋 Current model: $model_info"
    fi
  else
    echo "🔑 Local Server: ❌ Not available on localhost:1234"
  fi
  
  echo ""
  echo "Commands:"
  echo "  buildme model set <name>     Set default model"
  echo "  buildme model list           List all available models"
  echo "  buildme model clear          Clear all API keys and reset config"
  echo "  buildme --model <name> ...   Use specific model for one command"
}

clear_all_keys() {
  echo "🧹 Clearing all API keys and configuration..."
  
  local cleared_count=0
  
  if command -v security &>/dev/null; then
    if security find-generic-password -a "$USER" -s "openai_api_key" &>/dev/null; then
      security delete-generic-password -a "$USER" -s "openai_api_key" 2>/dev/null
      echo "✅ Removed OpenAI key from macOS Keychain"
      ((cleared_count++))
    fi
  fi
  
  if [[ -f "$HOME/.openai" ]]; then
    rm "$HOME/.openai"
    echo "✅ Removed ~/.openai file"
    ((cleared_count++))
  fi
  
  if [[ -f "$HOME/.deepseek" ]]; then
    rm "$HOME/.deepseek"
    echo "✅ Removed ~/.deepseek file"
    ((cleared_count++))
  fi
  
  if [[ -f "$HOME/.buildme_config" ]]; then
    rm "$HOME/.buildme_config"
    echo "✅ Removed ~/.buildme_config file (reset to gpt-4o-mini default)"
    ((cleared_count++))
  fi
  
  if [[ $cleared_count -eq 0 ]]; then
    echo "💡 No stored API keys or config found to clear"
  else
    echo ""
    echo "🔄 Cleared $cleared_count items"
    echo "📝 Note: Environment variables (OPENAI_API_KEY, DEEPSEEK_API_KEY) are not affected"
    echo "💡 Run 'buildme init' to reconfigure API keys"
  fi
}