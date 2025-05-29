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
  local input="$1"
  if [[ -z "$input" ]]; then
    echo "❌ Usage: buildme record replay <name_or_file>"
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
  
  echo "🔁 Commands from $(basename "$file"):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
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
      
      echo "➡️  $cmd"
    fi
  done < "$file"
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
