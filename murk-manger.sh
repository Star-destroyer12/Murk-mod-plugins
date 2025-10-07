#!/bin/bash

# --- Plugin Metadata ---
PLUGIN_NAME="Murk Manager"
PLUGIN_FUNCTION="Simple file manager with navigation and file operations"
PLUGIN_DESCRIPTION="File manager with copy, move, delete, rename, search, permissions management, and custom text editor."
PLUGIN_AUTHOR="Star"
PLUGIN_VERSION="1.0"

# --- Configuration ---
START_DIR="${1:-.}"

# --- Sanity Checks ---
for cmd in ls cp mv rm mkdir rmdir less sed chmod chown find; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    sleep 2
    exit 1
  fi
done

# --- UI Helpers ---
cls() { clear; }
move_cursor() { printf "\033[%s;%sH" "$1" "$2"; }

# Read a single key (handles arrows)
read_key(){
  IFS= read -rsn1 key 2>/dev/null
  if [[ $key == $'\x1b' ]]; then
    IFS= read -rsn2 -t 0.001 rest 2>/dev/null || rest=''
    key+="$rest"
  fi
  printf '%s' "$key"
}

# --- File List Management ---
CURRENT_DIR="$(realpath "$START_DIR")"
cd "$CURRENT_DIR" || exit 1

refresh_entries(){
  mapfile -t ENTRIES < <(ls -A --color=never 2>/dev/null || true)
  # Sort directories first
  local dirs=(); local files=()
  for e in "${ENTRIES[@]}"; do
    [[ -d "$e" ]] && dirs+=("$e") || files+=("$e")
  done
  ENTRIES=( "${dirs[@]}" "${files[@]}" )
  ENTRIES_TOTAL=${#ENTRIES[@]}
}

# Render the UI
render_ui(){
  cls
  local header="Murk Manager  —  cwd: $(pwd)"
  echo "$header"
  printf '%s\n\n' "Use ↑/↓ to move • ← parent • → enter • Enter view • c:copy m:move d:delete e:edit n:mkdir r:rename s:search q:quit p:permissions"
  local cols=$(tput cols)
  local rows=$(tput lines)
  local body_rows=$((rows-6))
  local start=$((scroll_offset))
  local end=$((start + body_rows -1))
  ((end >= ENTRIES_TOTAL)) && end=$((ENTRIES_TOTAL-1))
  for i in $(seq $start $end); do
    local idx_display=$((i+1))
    local name="${ENTRIES[i]}"
    local indicator=' '
    [[ -d "$name" ]] && indicator='d'
    if [[ $i -eq $cursor ]]; then
      # Highlight the selected entry
      printf "\e[7m %3s %s\e[0m\n" "[$idx_display]" "$indicator $name"
    else
      printf " %3s %s\n" "[$idx_display]" "$indicator $name"
    fi
  done
  # Footer
  printf "\nEntries: %d    Selected: %s\n" "$ENTRIES_TOTAL" "${ENTRIES[cursor]:-}"
}

# --- File Actions ---
action_enter(){
  local sel="${ENTRIES[cursor]:-}" || return
  [[ -z "$sel" ]] && return
  if [[ -d "$sel" ]]; then
    cd -- "$sel" || return
    cursor=0; scroll_offset=0
    refresh_entries
  else
    less "$sel"
  fi
}

action_parent(){
  cd .. || return
  cursor=0; scroll_offset=0
  refresh_entries
}

# --- File Operations ---
action_copy(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Copy '$src' to (path): " dst
  [[ -z "$dst" ]] && return
  cp -a -- "$src" "$dst" 2>/dev/null
  read -rp "Done. Press any key." -n1 _
  refresh_entries
}

action_move(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Move '$src' to (path): " dst
  [[ -z "$dst" ]] && return
  mv -- "$src" "$dst" 2>/dev/null
  read -rp "Done. Press any key." -n1 _
  refresh_entries
}

action_delete(){
  local tgt="${ENTRIES[cursor]:-}" || return
  [[ -z "$tgt" ]] && return
  read -rp "Are you sure you want to delete '$tgt'? (y/n): " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -rf -- "$tgt"
    read -rp "Done. Press any key." -n1 _
    refresh_entries
  fi
}

action_rename(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Rename '$src' to: " new_name
  [[ -z "$new_name" ]] && return
  mv -- "$src" "$new_name" 2>/dev/null
  read -rp "Done. Press any key." -n1 _
  refresh_entries
}

# --- Custom File Editor ---
edit_file(){
  local file="$1"
  [[ -z "$file" || ! -f "$file" ]] && echo "File not found: $file" && return

  local temp_file=$(mktemp)  # Temporary file to store edited content
  cp -- "$file" "$temp_file"  # Copy the file content to temp

  local cursor_pos=0
  local rows cols
  rows=$(tput lines)
  cols=$(tput cols)

  clear
  echo "Editing: $file (Press Ctrl+X to save and quit)"

  while :; do
    clear
    # Display the file content with line numbers
    local i=0
    while IFS= read -r line; do
      printf "%3d  %s\n" "$((i+1))" "$line"
      ((i++))
    done < "$temp_file"

    # Display cursor position
    echo -e "\nCursor at Line: $((cursor_pos + 1))"

    # Get user input (key press)
    read -rsn1 key

    case "$key" in
      # Quit the editor (save if changes are made)
      $'\x18')  # Ctrl+X
        read -p "Save changes? (Y/n): " save
        if [[ "$save" != "n" && "$save" != "N" ]]; then
          cp "$temp_file" "$file"
          echo "Changes saved."
        fi
        break
        ;;
      $'\x1b[A')  # Up arrow
        ((cursor_pos > 0)) && ((cursor_pos--))
        ;;
      $'\x1b[B')  # Down arrow
        ((cursor_pos < $(wc -l < "$temp_file") - 1)) && ((cursor_pos++))
        ;;
      $'\x0a')  # Enter key
        # Allow editing of text at the cursor position
        read -p "Edit Line $((cursor_pos + 1)): " new_line
        sed -i "${cursor_pos + 1}s/.*/$new_line/" "$temp_file"
        ;;
      *)
        continue
        ;;
    esac
  done
}

action_edit(){
  local file="${ENTRIES[cursor]}"
  edit_file "$file"  # Custom editor
}

action_permissions(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Change permissions for '$src'. Enter mode (e.g., 755): " perms
  chmod "$perms" "$src" 2>/dev/null
  read -rp "Done. Press any key." -n1 _
  refresh_entries
}

# --- Search Functionality ---
action_search(){
  read -rp "Search for file (name pattern): " pattern
  if [[ -n "$pattern" ]]; then
    find . -type f -name "*$pattern*" -print
  fi
}

# --- Directory Creation ---
action_mkdir(){
  read -rp "Enter directory name: " dir_name
  if [[ -n "$dir_name" ]]; then
    mkdir -- "$dir_name"
    refresh_entries
  fi
}

# --- Main Loop ---
cursor=0
scroll_offset=0
refresh_entries

while :; do
  render_ui
  # Scroll if needed
  if (( cursor < scroll_offset )); then scroll_offset=$cursor; fi
  local rows=$(tput lines)
  local body_rows=$((rows-6))
  if (( cursor >= scroll_offset + body_rows )); then scroll_offset=$((cursor - body_rows + 1)); fi

  key=$(read_key)
  case "$key" in
    $'\x1b[A')  # Up arrow
      ((cursor--))
      ((cursor < 0)) && cursor=0
      ;;
    $'\x1b[B')  # Down arrow
      ((cursor++))
      ((cursor >= ENTRIES_TOTAL)) && cursor=$((ENTRIES_TOTAL - 1))
      ;;
    $'\x1b[C')  # Right arrow (Enter directory)
      action_enter
      ;;
    $'\x1b[D')  # Left arrow (Go to parent)
      action_parent
      ;;
    'q')  # Quit
      break
      ;;
    'r')  # Rename
      action_rename
      ;;
    'c')  # Copy
      action_copy
      ;;
    'm')  # Move
      action_move
      ;;
    'd')  # Delete
      action_delete
      ;;
    'e')  # Edit
      action_edit
      ;;
    'n')  # Create new directory
      action_mkdir
      ;;
    'p')  # Permissions
      action_permissions
      ;;
    's')  # Search
      action_search
      ;;
    *) continue
      ;;
  esac
done
