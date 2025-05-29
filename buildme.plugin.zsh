#!/usr/bin/env zsh

# --- buildme.plugin.zsh ---


BUILDME_PLUGIN_DIR="${${(%):-%x}:A:h}"

source "$BUILDME_PLUGIN_DIR/commands/history.zsh"
source "$BUILDME_PLUGIN_DIR/commands/starter.zsh"
source "$BUILDME_PLUGIN_DIR/commands/record.zsh"
source "$BUILDME_PLUGIN_DIR/commands/snapshots.zsh"
source "$BUILDME_PLUGIN_DIR/core/models.zsh"
source "$BUILDME_PLUGIN_DIR/core/generate.zsh"
source "$BUILDME_PLUGIN_DIR/core/init.zsh"
source "$BUILDME_PLUGIN_DIR/core/run.zsh"
source "$BUILDME_PLUGIN_DIR/commands/undo.zsh"


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

  if [[ "$1" == "clean-history" ]]; then
    buildme_clean_history
    return 0
  fi

  if [[ "$1" == "starter" ]]; then
    shift
    buildme_starter "$@"
    return 0
  fi

  if [[ "$1" == "model" ]]; then
    shift
    case "$1" in
      list)
        buildme_model_list
        return 0
        ;;
      set)
        shift
        set_default_model "$1"
        return 0
        ;;
      status)
        show_model_status
        return 0
        ;;
      clear)
        clear_all_keys
        return 0
        ;;
      "")
        show_model_status
        return 0
        ;;
      *)
        echo "❌ Unknown model command: $1"
        echo "Available commands:"
        echo "  buildme model [status]    Show current model configuration"
        echo "  buildme model list        List all available models"
        echo "  buildme model set <name>  Set default model"
        echo "  buildme model clear       Clear all API keys and reset config"
        return 1
        ;;
    esac
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

  if [[ "$1" == "record" ]]; then
    shift
    case "$1" in
      start) shift; buildme_record_start "$@" ;;
      stop) buildme_record_stop ;;
      list) buildme_record_list ;;
      replay) shift; buildme_record_replay "$@" ;;
      delete) shift; buildme_record_delete "$@" ;;
      clear) buildme_record_clear ;;
      rename) shift; buildme_record_rename "$@" ;;
      *) echo "❌ Usage: buildme record {start [name]|stop|list|replay [--run|--step] <name>|delete <name>|clear|rename <old> <new>}" ;;
    esac
    return 0
  fi

  if [[ "$1" == "snapshot" ]]; then
    shift
    buildme_snapshot "$@"
    return 0
  fi

  if [[ "$1" == "restore" ]]; then
    shift
    buildme_snapshot_restore "$@"
    return 0
  fi

  if [[ "$1" == "help" || "$1" == "--help" ]]; then
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
  clean-history        Remove duplicate commands from history
  model list           Show all available models and their status
  record {start|stop|replay <file>}
                      Manage terminal command recording
  snapshot {<name>|list|delete <name>}
                      Manage directory snapshots
  restore <name|path> [--to <path>] [--overwrite] [--dry-run]
                      Restore a directory snapshot
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
  model [status]       Show current model configuration and API key status
  model list           Show all available models and their status
  model set <name>     Set default model (gpt-4o, gpt-4o-mini, deepseek, local, etc.)
  model clear          Clear all stored API keys and reset configuration

Record Commands:
  record start         Start recording terminal commands to a timestamped file
  record stop          Stop recording and show where the session was saved
  record replay <file> Show commands from a recorded session file

Snapshot Commands:
  snapshot <name>      Create a snapshot of the current directory
  snapshot list        List all available snapshots
  snapshot delete <name>
                      Delete a snapshot by name
  restore <name|path>  Restore a snapshot to ./restored_<name>/
  restore <name> --to <path>
                      Restore a snapshot to a specific directory
  restore <name> --overwrite
                      Restore a snapshot to the current directory
  restore <name> --dry-run
                      List snapshot contents without extracting

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
  buildme clean-history
  
  # Record examples
  buildme record start <name>
  buildme record stop
  buildme record list
  buildme record replay <name>
  buildme record rename <old> <new>
  
  # Snapshot examples
  buildme snapshot before-changes
  buildme snapshot list
  buildme restore before-changes
  buildme restore before-changes --to ~/backup/
  buildme restore before-changes --dry-run
  buildme snapshot delete old-snapshot

EOF
    return 0
  fi

  local run=1
  local step=0
  local model=$(get_default_model)
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

  echo "🧠 Thinking... (using $model)"
  local commands=$(buildme_generate "$prompt" "$key" "$model")

  echo ""
  echo "💡 Suggested commands:"
  echo "──────────────────────────────"
  echo "$commands" \
    | sed 's/^```bash//; s/^```//g' \
    | sed 's/^`\(.*\)`$/\1/' \
    | tr '&' '\n' \
    | sed 's/&&/&&/g' \
    | sed '/^$/d' \
    | sed 's/^ */  /'
  echo "──────────────────────────────"

  if [[ "$run" -eq 1 ]]; then
    if [[ "$step" -eq 1 ]]; then
      buildme_run_stepwise "$commands" "$prompt"
    else
      buildme_run "$commands" "$prompt"
    fi
  fi
}