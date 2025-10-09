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

get_color_for_file() {
  local file="$1"
  if [[ -d "$file" ]]; then
    printf '\e[34m'           # Blue for directories
  else
    case "${file,,}" in
      *.sh) printf '\e[33m' ;;                      # Yellow
      *.json) printf '\e[36m' ;;                    # Cyan
      *.txt|*.log) printf '\e[31m' ;;               # Red
      *.md) printf '\e[35m' ;;                       # Magenta
      *.pdf) printf '\e[97m' ;;                      # White
      *.jpg|*.jpeg|*.png|*.gif|*.bmp|*.svg|*.webp)  # Brown (38;5;94)
        printf '\e[38;5;94m' ;;
      *.mp3|*.mp4|*.mov|*.wav|*.avi|*.mkv|*.flac|*.m4a)  # Purple media files
        printf '\e[35m' ;;
      *) printf '\e[32m' ;;                          # Green for others
    esac
  fi
}

reset_color() { printf '\e[0m'; }

CURRENT_DIR="$(realpath "$START_DIR")"
cd "$CURRENT_DIR" || exit 1

refresh_entries(){
  mapfile -t ENTRIES < <(ls -A --color=never 2>/dev/null || true)
  local dirs=() files=()
  for e in "${ENTRIES[@]}"; do
    [[ -d "$e" ]] && dirs+=("$e") || files+=("$e")
  done
  ENTRIES=( "${dirs[@]}" "${files[@]}" )
  ENTRIES_TOTAL=${#ENTRIES[@]}
}

render_ui(){
  cls
  local header="Murk Manager  —  cwd: $(pwd)"
  echo "$header"
  echo "Use ↑/↓ to move • ← parent • → enter • Enter view • c:copy m:move d:delete e:edit n:mkdir r:rename s:search q:quit p:permissions"
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
      printf "\e[7m %3s " "[$idx_display]"
      get_color_for_file "$name"
      printf "%s %s" "$indicator" "$name"
      reset_color
      printf "\e[0m\n"
    else
      printf " %3s " "[$idx_display]"
      get_color_for_file "$name"
      printf "%s %s" "$indicator" "$name"
      reset_color
      printf "\n"
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
  echo "Copied '$src' to '$dst'."
  refresh_entries
}

action_move(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Move '$src' to (path): " dst
  [[ -z "$dst" ]] && return
  mv -- "$src" "$dst" 2>/dev/null
  echo "Moved '$src' to '$dst'."
  refresh_entries
}

action_delete(){
  local tgt="${ENTRIES[cursor]:-}" || return
  [[ -z "$tgt" ]] && return
  read -rp "Are you sure you want to delete '$tgt'? (y/n): " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -rf -- "$tgt"
    echo "Deleted '$tgt'."
    refresh_entries
  fi
}

action_rename(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Rename '$src' to: " new_name
  [[ -z "$new_name" ]] && return
  mv -- "$src" "$new_name" 2>/dev/null
  echo "Renamed '$src' to '$new_name'."
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

  local temp_file
  temp_file=$(mktemp)
  cp -- "$file" "$temp_file"

  local cursor_pos=0

  while :; do
    cls
    echo "Editing: $file (x=save & quit, q=quit, ↑/↓ navigate, Enter=edit line)"
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
        local linecount
        linecount=$(wc -l < "$temp_file")
        ((cursor_pos < linecount - 1)) && ((cursor_pos++))
        ;;
      '') # Enter key
        read -rp "Edit Line $((cursor_pos+1)): " new_line
        local escaped_line
        escaped_line=$(printf '%s\n' "$new_line" | sed -e 's/[\/&]/\\&/g' -e 's/\\/\\\\/g')
        sed -i "$((cursor_pos+1))s/.*/$escaped_line/" "$temp_file"
        ;;
      'x') # Save & Quit
        cp "$temp_file" "$file"
        echo "Saved."
        rm "$temp_file"
        read -rp "Press any key to continue." -n1 _
        break
        ;;
      'q') # Quit without saving
        rm "$temp_file"
        break
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
  echo "Permissions changed for '$src'."
  refresh_entries
}

action_search(){
  read -rp "Search for file (name pattern): " pattern
  if [[ -n "$pattern" ]]; then
    find . -type f -name "*$pattern*" -print
    read -rp "Press any key to continue." -n1 _
  fi
}

action_mkdir(){
  read -rp "Enter directory name: " dir_name
  if [[ -n "$dir_name" ]]; then
    mkdir -- "$dir_name"
    echo "Directory '$dir_name' created."
    refresh_entries
  fi
}

cursor=0
scroll_offset=0
refresh_entries

while :; do
  render_ui
  local rows cols
  rows=$(tput lines)
  cols=$(tput cols)
  local body_rows=$((rows-6))
  
  # Scroll management to always keep cursor visible
  if (( cursor < scroll_offset )); then
    scroll_offset=$cursor
  elif (( cursor >= scroll_offset + body_rows )); then
    scroll_offset=$((cursor - body_rows + 1))
  fi

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
