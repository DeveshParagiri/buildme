buildme_run() {
  local script="$1"
  echo ""
  echo "❓ Do you want to run these commands? [y/N]"
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo ""
    echo "$(date '+%Y-%m-%d %H:%M:%S')|$script" > ~/.last_buildme_commands.sh
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