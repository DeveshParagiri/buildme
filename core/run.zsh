buildme_run() {
  local script="$1"
  local original_request="$2"  # New parameter for original user request
  echo ""
  echo "❓ Do you want to run these commands? [y/N]"
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo ""
    # Append to session file to track multiple related buildme commands
    cat >> ~/.last_buildme_session.sh << EOF
# Session entry $(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
ORIGINAL_REQUEST="$original_request"
GENERATED_COMMANDS="$script"

EOF
    eval "$script"
  else
    echo "🚫 Skipped running commands."
  fi
}

buildme_run_stepwise() {
  local script="$1"
  local original_request="$2"  # New parameter for original user request
  
  # Append to session file to track multiple related buildme commands
  cat >> ~/.last_buildme_session.sh << EOF
# Session entry $(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
ORIGINAL_REQUEST="$original_request"
GENERATED_COMMANDS="$script"

EOF

  exec 3<&0
  local run_all=0

  # Split commands on && and process each one
  echo "$script" | sed 's/ && /\n/g' | while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Clean up any leading/trailing whitespace
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$line" ]] && continue

    echo "➡️  $line"
    echo -n "❓ Run this? [y/N/a/q] "
    read -r confirm <&3

    case "$confirm" in
      [Yy]|"") eval "$line" ;;
      [Nn]) echo "⏭️  Skipped." ;;
      [Aa]) run_all=1; eval "$line" ;;
      [Qq]) echo "👋 Exiting"; break ;;
      *) echo "❓ Unknown choice, skipping." ;;
    esac
    echo ""
  done

  exec 0<&3
}