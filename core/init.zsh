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