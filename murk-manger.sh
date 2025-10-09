#!/bin/bash

PLUGIN_NAME="Murk Manager"
PLUGIN_FUNCTION="Simple file manager with navigation and file operations"
PLUGIN_DESCRIPTION="File manager with copy, move, delete, rename, search, permissions management, and custom text editor."
PLUGIN_AUTHOR="Star"
PLUGIN_VERSION="2.3"

START_DIR="${1:-.}"

for cmd in ls cp mv rm mkdir rmdir sed chmod chown find clear tput; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    sleep 2
    exit 1
  fi
done

cls() { clear; }
move_cursor() { printf "\033[%s;%sH" "$1" "$2"; }

read_key(){
  IFS= read -rsn1 key 2>/dev/null
  if [[ $key == $'\x1b' ]]; then
    IFS= read -rsn2 -t 0.001 rest 2>/dev/null || rest=''
    key+="$rest"
  fi
  printf '%s' "$key"
}

CURRENT_DIR="$(realpath "$START_DIR")"
cd "$CURRENT_DIR" || exit 1

refresh_entries(){
  mapfile -t ENTRIES < <(ls -A --color=never 2>/dev/null || true)
  local dirs=(); local files=()
  for e in "${ENTRIES[@]}"; do
    [[ -d "$e" ]] && dirs+=("$e") || files+=("$e")
  done
  ENTRIES=( "${dirs[@]}" "${files[@]}" )
  ENTRIES_TOTAL=${#ENTRIES[@]}
  # Clamp cursor after refresh
  if (( cursor >= ENTRIES_TOTAL )); then
    cursor=$((ENTRIES_TOTAL - 1))
  fi
  (( cursor < 0 )) && cursor=0
}

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
    local color_reset='\033[0m'
    local color_code=''

    if [[ -d "$name" ]]; then
      indicator='d'
      color_code='\033[34m'  # Blue for directories
    elif [[ "$name" == *.sh ]]; then
      color_code='\033[33m'  # Yellow for .sh files
    else
      color_code='\033[32m'  # Green for other files
    fi

    if [[ $i -eq $cursor ]]; then
      # Inverse color + color code for selected
      printf "\e[7m%3s %b%s%b\e[0m\n" "[$idx_display]" "$color_code" "$indicator $name" "$color_reset"
    else
      printf " %3s %b%s%b\n" "[$idx_display]" "$color_code" "$indicator $name" "$color_reset"
    fi
  done
  printf "\nEntries: %d    Selected: %s\n" "$ENTRIES_TOTAL" "${ENTRIES[cursor]:-}"
}

action_enter(){
  local sel="${ENTRIES[cursor]:-}" || return
  [[ -z "$sel" ]] && return
  if [[ -d "$sel" ]]; then
    cd -- "$sel" || return
    cursor=0; scroll_offset=0
    refresh_entries
  else
    view_file "$sel"
  fi
}

action_parent(){
  cd .. || return
  cursor=0; scroll_offset=0
  refresh_entries
}

action_copy(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Copy '$src' to (path): " dst
  [[ -z "$dst" ]] && return
  cp -a -- "$src" "$dst" 2>/dev/null
  refresh_entries
}

action_move(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Move '$src' to (path): " dst
  [[ -z "$dst" ]] && return
  mv -- "$src" "$dst" 2>/dev/null
  refresh_entries
}

action_delete(){
  local tgt="${ENTRIES[cursor]:-}" || return
  [[ -z "$tgt" ]] && return
  read -rp "Are you sure you want to delete '$tgt'? (y/n): " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -rf -- "$tgt"
    refresh_entries
  fi
}

action_rename(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Rename '$src' to: " new_name
  [[ -z "$new_name" ]] && return
  mv -- "$src" "$new_name" 2>/dev/null
  refresh_entries
}

view_file(){
  local file="$1"
  [[ ! -f "$file" ]] && return
  clear
  echo "Viewing: $file (Press any key to go back)"
  cat "$file"
  read -rn1 _
}

edit_file(){
  local file="$1"
  [[ -z "$file" || ! -f "$file" ]] && echo "File not found: $file" && return

  local temp_file=$(mktemp)
  cp -- "$file" "$temp_file"

  local cursor_pos=0

  while :; do
    clear
    echo "Editing: $file (s=save, x=save+quit, q=quit no save, ↑/↓=move, Enter=edit line)"
    local i=0
    while IFS= read -r line || [[ -n $line ]]; do
      if (( i == cursor_pos )); then
        printf "\e[7m%3d  %s\e[0m\n" $((i+1)) "$line"
      else
        printf "%3d  %s\n" $((i+1)) "$line"
      fi
      ((i++))
    done < "$temp_file"

    IFS= read -rsn1 key
    if [[ $key == $'\x1b' ]]; then
      IFS= read -rsn2 -t 0.1 rest 2>/dev/null || rest=''
      key+="$rest"
    fi

    case "$key" in
      $'\x1b[A') # Up arrow
        ((cursor_pos > 0)) && ((cursor_pos--))
        ;;
      $'\x1b[B') # Down arrow
        local linecount=$(wc -l < "$temp_file")
        ((cursor_pos < linecount - 1)) && ((cursor_pos++))
        ;;
      '') # Enter key
        read -rp "Edit Line $((cursor_pos+1)): " new_line
        # Escape backslashes and slashes for sed
        local escaped_line=$(printf '%s\n' "$new_line" | sed -e 's/[\/&]/\\&/g' -e 's/\\/\\\\/g')
        sed -i "$((cursor_pos+1))s/.*/$escaped_line/" "$temp_file"
        ;;
      's') # Save
        cp "$temp_file" "$file"
        echo "Saved."
        sleep 1
        ;;
      'x') # Save and quit
        cp "$temp_file" "$file"
        rm "$temp_file"
        echo "Saved and exiting editor."
        sleep 1
        return
        ;;
      'q') # Quit without save
        rm "$temp_file"
        echo "Exiting editor without saving."
        sleep 1
        return
        ;;
    esac
  done
}

action_edit(){
  local file="${ENTRIES[cursor]}"
  edit_file "$file"
}

action_permissions(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Change permissions for '$src'. Enter mode (e.g., 755): " perms
  chmod "$perms" "$src" 2>/dev/null
  refresh_entries
}

action_search(){
  read -rp "Search for file (name pattern): " pattern
  if [[ -n "$pattern" ]]; then
    find . -type f -name "*$pattern*" -print
    echo "Done searching."
  fi
}

action_mkdir(){
  read -rp "Enter directory name: " dir_name
  if [[ -n "$dir_name" ]]; then
    mkdir -- "$dir_name"
    refresh_entries
  fi
}

cursor=0
scroll_offset=0
refresh_entries

while :; do
  render_ui

  # Clamp cursor to valid range
  if (( cursor < 0 )); then
    cursor=0
  elif (( cursor >= ENTRIES_TOTAL )); then
    cursor=$((ENTRIES_TOTAL - 1))
  fi

  local rows=$(tput lines)
  local body_rows=$((rows-6))

  # Adjust scroll offset to keep cursor visible
  if (( cursor < scroll_offset )); then
    scroll_offset=$cursor
  elif (( cursor >= scroll_offset + body_rows )); then
    scroll_offset=$((cursor - body_rows + 1))
  fi

  key=$(read_key)
  case "$key" in
    $'\x1b[A')  # Up arrow
      ((cursor--))
      ;;
    $'\x1b[B')  # Down arrow
      ((cursor++))
      ;;
    $'\x1b[C')  # Right arrow (Enter directory or open file)
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
