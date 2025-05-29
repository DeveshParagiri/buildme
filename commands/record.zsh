#!/usr/bin/env zsh
# buildme_record.zsh - Simple terminal command recording

# Define the hook function outside to avoid redefinition
buildme_record_hook() {
  # Skip recording buildme record commands to avoid recursion
  [[ "$1" =~ ^buildme[[:space:]]+record ]] && return
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$BUILDME_RECORD_FILE"
}

buildme_record_start() {
  # Check if already recording
  if [[ -n "$BUILDME_RECORD_FILE" ]]; then
    echo "⚠️  Already recording to: $BUILDME_RECORD_FILE"
    return 1
  fi
  
  local session_name="$1"
  local timestamp=$(date +%s)
  
  echo "🎥 Recording started. All terminal commands will be logged."
  
  # Create filename with optional name
  if [[ -n "$session_name" ]]; then
    # Sanitize the session name (remove spaces, special chars)
    session_name=$(echo "$session_name" | sed 's/[^a-zA-Z0-9_-]/_/g')
    export BUILDME_RECORD_FILE="$HOME/.buildme_record_${session_name}_${timestamp}.sh"
    echo "📝 Session name: $session_name"
  else
    export BUILDME_RECORD_FILE="$HOME/.buildme_record_${timestamp}.sh"
  fi
  
  echo "📁 File: $BUILDME_RECORD_FILE"
  
  # Add to zsh's preexec_functions array if not already there
  if [[ -z "${preexec_functions[(r)buildme_record_hook]}" ]]; then
    preexec_functions+=(buildme_record_hook)
  fi
}

buildme_record_stop() {
  if [[ -z "$BUILDME_RECORD_FILE" ]]; then
    echo "⚠️  No active recording session."
    return 1
  fi
  
  # Remove our hook
  preexec_functions=(${preexec_functions[@]:#buildme_record_hook})
  
  echo "⏹️ Recording stopped. Saved to: $BUILDME_RECORD_FILE"
  unset BUILDME_RECORD_FILE
}

buildme_record_list() {
  echo "📋 Available recordings:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  local found=0
  # Use nullglob to prevent error when no matches
  setopt local_options nullglob
  
  for file in "$HOME"/.buildme_record_*.sh; do
    if [[ -f "$file" ]]; then
      found=1
      local basename=$(basename "$file")
      local name_part=""
      
      # Extract name from filename
      if [[ "$basename" =~ ^\.buildme_record_(.+)_[0-9]+\.sh$ ]]; then
        name_part="${match[1]}"
        echo "📝 $name_part"
      else
        # For files without names, show timestamp
        if [[ "$basename" =~ ^\.buildme_record_([0-9]+)\.sh$ ]]; then
          local timestamp="${match[1]}"
          local date_str=$(date -r "$timestamp" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
          echo "📝 (unnamed-$timestamp) - $date_str"
        fi
      fi
    fi
  done
  
  if [[ $found -eq 0 ]]; then
    echo "📭 No recordings found."
    echo "💡 Create one with: buildme record start [name]"
  fi
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

buildme_record_replay() {
  local input=""
  local run_mode=false
  local step_mode=false
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run) run_mode=true; shift ;;
      --step) step_mode=true; shift ;;
      *) input="$1"; shift ;;
    esac
  done
  
  if [[ -z "$input" ]]; then
    echo "❌ Usage: buildme record replay [--run|--step] <name>"
    echo "💡 Use: buildme record list to see available recordings"
    return 1
  fi
  
  local file=""
  
  # Check if it's a full file path
  if [[ -f "$input" ]]; then
    file="$input"
  else
    # Try to find by name
    local found_files=()
    for f in "$HOME"/.buildme_record_*"$input"*_*.sh; do
      if [[ -f "$f" ]]; then
        found_files+=("$f")
      fi
    done
    
    if [[ ${#found_files[@]} -eq 0 ]]; then
      echo "❌ No recording found matching: $input"
      echo "💡 Use: buildme record list to see available recordings"
      return 1
    elif [[ ${#found_files[@]} -gt 1 ]]; then
      echo "❌ Multiple recordings match '$input':"
      for f in "${found_files[@]}"; do
        echo "   $(basename "$f")"
      done
      echo "💡 Be more specific or use the full filename"
      return 1
    else
      file="${found_files[1]}"
    fi
  fi
  
  # Extract commands
  local commands=()
  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Extract command part (after timestamp)
    if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+(.*) ]]; then
      local cmd="${match[1]}"
      
      # Skip empty or malformed commands
      if [[ -z "$cmd" || "$cmd" =~ ^[[:space:]]*$ ]]; then
        continue
      fi
      
      # Skip partial commands (lines that start with spaces, dashes, or braces)
      if [[ "$cmd" =~ ^[[:space:]]*[-{}] ]] || [[ "$cmd" =~ ^[[:space:]]*[\"\'\\] ]]; then
        continue
      fi
      
      commands+=("$cmd")
    fi
  done < "$file"
  
  if [[ ${#commands[@]} -eq 0 ]]; then
    echo "❌ No commands found in recording"
    return 1
  fi
  
  # Show preview
  echo "🔁 Commands from $(basename "$file"):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  for cmd in "${commands[@]}"; do
    echo "➡️  $cmd"
  done
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Handle execution
  if [[ "$run_mode" == true ]]; then
    # Run mode: execute all with single confirmation
    echo ""
    echo "❓ Execute all ${#commands[@]} commands? [y/N]"
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      for cmd in "${commands[@]}"; do
        echo "🚀 $cmd"
        if eval "$cmd"; then
          echo ""  # Add space before success
          echo "✅ Success"
        else
          echo ""  # Add space before failure
          echo "❌ Command failed: $cmd"
        fi
      done
      echo "🏁 All commands completed"
    else
      echo "🚫 Execution cancelled"
    fi
  else
    # Default/step mode: step-by-step with confirmation
    echo ""
    local run_all=0
    
    for cmd in "${commands[@]}"; do
      echo "➡️  $cmd"
      
      if [[ "$run_all" -eq 1 ]]; then
        eval "$cmd"
        echo ""
        echo "✅ Success"
        echo ""
        continue
      fi
      
      echo -n "❓ Run this? [y/N/a/q] "
      read -r confirm
      
      case "$confirm" in
        [Yy]*)
          if eval "$cmd"; then
            echo ""
            echo "✅ Success"
          else
            echo ""
            echo "❌ Command failed"
          fi
          ;;
        [Aa]*)
          run_all=1
          if eval "$cmd"; then
            echo ""
            echo "✅ Success"
          else
            echo ""
            echo "❌ Command failed"
          fi
          ;;
        [Qq]*)
          echo "👋 Exiting"
          return 0
          ;;
        *)
          echo "⏭️  Skipped"
          ;;
      esac
      echo ""
    done
  fi
}

buildme_record_delete() {
  local input="$1"
  if [[ -z "$input" ]]; then
    echo "❌ Usage: buildme record delete <name_or_file>"
    echo "💡 Use: buildme record list to see available recordings"
    return 1
  fi
  
  local file=""
  
  # Check if it's a full file path
  if [[ -f "$input" ]]; then
    file="$input"
  else
    # Try to find by name
    local found_files=()
    for f in "$HOME"/.buildme_record_*"$input"*_*.sh; do
      if [[ -f "$f" ]]; then
        found_files+=("$f")
      fi
    done
    
    if [[ ${#found_files[@]} -eq 0 ]]; then
      echo "❌ No recording found matching: $input"
      echo "💡 Use: buildme record list to see available recordings"
      return 1
    elif [[ ${#found_files[@]} -gt 1 ]]; then
      echo "❌ Multiple recordings match '$input':"
      for f in "${found_files[@]}"; do
        echo "   $(basename "$f")"
      done
      echo "💡 Be more specific or use the full filename"
      return 1
    else
      file="${found_files[1]}"
    fi
  fi
  
  # Confirm deletion
  echo "❓ Delete recording: $(basename "$file")? [y/N]"
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm "$file"
    echo "🗑️  Deleted: $(basename "$file")"
  else
    echo "❌ Deletion cancelled"
  fi
}

buildme_record_clear() {
  local count=$(ls "$HOME"/.buildme_record_*.sh 2>/dev/null | wc -l | tr -d ' ')
  
  if [[ "$count" -eq 0 ]]; then
    echo "📭 No recordings to delete"
    return 0
  fi
  
  echo "⚠️  Delete ALL $count recordings? [y/N]"
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm "$HOME"/.buildme_record_*.sh 2>/dev/null
    echo "🗑️  Deleted all recordings"
  else
    echo "❌ Deletion cancelled"
  fi
}

buildme_record_rename() {
  local input="$1"
  local new_name="$2"
  
  if [[ -z "$input" ]]; then
    echo "❌ Usage: buildme record rename <current_name> <new_name>"
    return 1
  fi
  
  if [[ -z "$new_name" ]]; then
    echo "❌ Please provide a new name"
    return 1
  fi
  
  # Find the file
  local file=""
  local found_files=()
  for f in "$HOME"/.buildme_record_*"$input"*_*.sh; do
    if [[ -f "$f" ]]; then
      found_files+=("$f")
    fi
  done
  
  if [[ ${#found_files[@]} -eq 0 ]]; then
    echo "❌ No recording found matching: $input"
    return 1
  elif [[ ${#found_files[@]} -gt 1 ]]; then
    echo "❌ Multiple recordings match '$input'"
    return 1
  else
    file="${found_files[1]}"
  fi
  
  # Extract timestamp from old filename
  local basename=$(basename "$file")
  if [[ "$basename" =~ ^\.buildme_record_(.+)_([0-9]+)\.sh$ ]]; then
    local timestamp="${match[2]}"
    new_name=$(echo "$new_name" | sed 's/[^a-zA-Z0-9_-]/_/g')  # sanitize
    local new_file="$HOME/.buildme_record_${new_name}_${timestamp}.sh"
    
    mv "$file" "$new_file"
    echo "📝 Renamed to: $new_name"
  else
    echo "❌ Could not parse filename format"
    return 1
  fi
}
