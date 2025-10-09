#!/bin/bash

PLUGIN_NAME="Murk Manager"
PLUGIN_FUNCTION="Simple file manager with navigation and file operations"
PLUGIN_DESCRIPTION="File manager with copy, move, delete, rename, search, permissions management, and custom text editor."
PLUGIN_AUTHOR="Star"
PLUGIN_VERSION="1.0"

START_DIR="${1:-.}"

for cmd in ls cp mv rm mkdir rmdir less sed chmod chown find; do
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
}

render_ui(){
  cls
  echo "Murk Manager  —  cwd: $(pwd)"
  echo "Use ↑/↓ to move • ← parent • → enter • Enter view • c:copy m:move d:delete e:edit n:mkdir r:rename s:search q:quit p:permissions"
  local cols=$(tput cols)
  local rows=$(tput lines)
  local body_rows=$((rows-6))
  local start=$scroll_offset
  local end=$((start + body_rows -1))
  ((end >= ENTRIES_TOTAL)) && end=$((ENTRIES_TOTAL-1))
  for i in $(seq $start $end); do
    local idx_display=$((i+1))
    local name="${ENTRIES[i]}"
    local indicator=' '
    [[ -d "$name" ]] && indicator='d'
    if [[ $i -eq $cursor ]]; then
      printf "\e[7m %3s %s\e[0m\n" "[$idx_display]" "$indicator $name"
    else
      printf " %3s %s\n" "[$idx_display]" "$indicator $name"
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
    less "$sel"
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
  read -rp "Delete '$tgt'? (y/n): " confirm
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

edit_file(){
  local file="$1"
  [[ -z "$file" || ! -f "$file" ]] && echo "File not found: $file" && return

  local temp_file=$(mktemp)
  cp -- "$file" "$temp_file"

  local cursor_pos=0
  local rows cols
  rows=$(tput lines)
  cols=$(tput cols)

  clear
  echo "Editing: $file (Ctrl+S to save, Ctrl+Q to quit)"

  while :; do
    clear
    local i=0
    while IFS= read -r line; do
      if (( i == cursor_pos )); then
        printf "\e[7m%3d  %s\e[0m\n" $((i+1)) "$line"
      else
        printf "%3d  %s\n" $((i+1)) "$line"
      fi
      ((i++))
    done < "$temp_file"
    echo -e "\nUse ↑/↓ to move, Enter to edit line, Ctrl+S save, Ctrl+Q quit"

    IFS= read -rsn1 key
    if [[ $key == $'\x1b' ]]; then
      IFS= read -rsn2 -t 0.001 rest 2>/dev/null || rest=''
      key+="$rest"
    fi

    case "$key" in
      $'\x1b[A') (( cursor_pos > 0 )) && ((cursor_pos--)) ;; # up
      $'\x1b[B') (( cursor_pos < $(wc -l < "$temp_file") - 1 )) && ((cursor_pos++)) ;; # down
      '') # Enter
        read -rp "Edit Line $((cursor_pos+1)): " new_line
        sed -i "$((cursor_pos+1))s/.*/$new_line/" "$temp_file"
        ;;
      $'\x13') # Ctrl+S save
        cp "$temp_file" "$file"
        echo "Saved."
        read -rp "Press any key to continue." -n1 _
        ;;
      $'\x11') # Ctrl+Q quit
        break
        ;;
    esac
  done
  rm "$temp_file"
}

action_edit(){
  local file="${ENTRIES[cursor]}"
  edit_file "$file"
}

action_permissions(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Permissions for '$src' (e.g. 755): " perms
  chmod "$perms" "$src" 2>/dev/null
  read -rp "Done. Press any key." -n1 _
  refresh_entries
}

action_search(){
  read -rp "Search filename pattern: " pattern
  if [[ -n "$pattern" ]]; then
    find . -type f -name "*$pattern*" -print
    read -rp "Done. Press any key." -n1 _
  fi
}

action_mkdir(){
  read -rp "New directory name: " dir_name
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
  [ "$cursor" -lt "$scroll_offset" ] && scroll_offset=$cursor
  rows=$(tput lines)
  body_rows=$((rows-6))
  [ "$cursor" -ge $((scroll_offset + body_rows)) ] && scroll_offset=$((cursor - body_rows + 1))

  key=$(read_key)

  case "$key" in
    $'\x1b[A') # up
      ((cursor > 0)) && ((cursor--))
      ;;
    $'\x1b[B') # down
      ((cursor < ENTRIES_TOTAL - 1)) && ((cursor++))
      ;;
    $'\x1b[C') # right
      action_enter
      ;;
    $'\x1b[D') # left
      action_parent
      ;;
    '') # enter
      action_enter
      ;;
    'q') break ;;
    'c') action_copy ;;
    'm') action_move ;;
    'd') action_delete ;;
    'e') action_edit ;;
    'n') action_mkdir ;;
    'r') action_rename ;;
    's') action_search ;;
    'p') action_permissions ;;
  esac
done
