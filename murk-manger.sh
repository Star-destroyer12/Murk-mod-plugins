#!/bin/bash

START_DIR="${1:-.}"

for cmd in ls cp mv rm mkdir rmdir sed chmod find tput head; do
  command -v "$cmd" >/dev/null || { echo "Missing: $cmd"; sleep 2; exit 1; }
done

cls() { clear; }

read_key() {
  IFS= read -rsn1 key 2>/dev/null
  if [ "$key" = $'\x1b' ]; then
    IFS= read -rsn2 -t 0.001 rest 2>/dev/null || rest=''
    key+="$rest"
  fi
  printf '%s' "$key"
}

CURRENT_DIR="$START_DIR"
cd "$CURRENT_DIR" || exit 1

refresh_entries() {
  ENTRIES=()
  for item in $(ls -A); do
    [ -d "$item" ] && ENTRIES+=("$item")
  done
  for item in $(ls -A); do
    [ -f "$item" ] && ENTRIES+=("$item")
  done
  ENTRIES_TOTAL=${#ENTRIES[@]}
}

render_ui() {
  cls
  echo "Murk Manager — cwd: $(pwd)"
  echo
  echo "↑↓ move • ← parent • →/Enter open • c copy • m move • d delete • e edit • n mkdir • r rename • s search • p perms • q quit"
  rows=$(tput lines)
  body_rows=$((rows-6))
  start=$scroll_offset
  end=$((start + body_rows - 1))
  [ "$end" -ge "$ENTRIES_TOTAL" ] && end=$((ENTRIES_TOTAL - 1))
  for i in $(seq "$start" "$end"); do
    name="${ENTRIES[i]}"
    [ -z "$name" ] && continue
    indicator=' '
    [ -d "$name" ] && indicator='d'
    if [ "$i" -eq "$cursor" ]; then
      printf "\e[7m [%3d] %s %s\e[0m\n" "$((i + 1))" "$indicator" "$name"
    else
      printf " [%3d] %s %s\n" "$((i + 1))" "$indicator" "$name"
    fi
  done
  echo
  echo "Entries: $ENTRIES_TOTAL  Selected: ${ENTRIES[cursor]}"
}

action_enter() {
  sel="${ENTRIES[cursor]}"
  [ -z "$sel" ] && return
  if [ -d "$sel" ]; then
    cd "$sel" || return
    cursor=0; scroll_offset=0
    refresh_entries
  else
    cls
    echo "Viewing: $sel"
    echo "----------------------------"
    head -n $(( $(tput lines) - 5 )) "$sel" 2>/dev/null || echo "[Cannot display file]"
    echo "----------------------------"
    read -n1 -s _
  fi
}

action_parent() {
  cd .. || return
  cursor=0; scroll_offset=0
  refresh_entries
}

action_copy() {
  src="${ENTRIES[cursor]}"
  [ -z "$src" ] && return
  read -p "Copy '$src' to: " dst
  [ -z "$dst" ] && return
  cp -r "$src" "$dst" 2>/dev/null
  read -n1 -s -p "Done."
  refresh_entries
}

action_move() {
  src="${ENTRIES[cursor]}"
  [ -z "$src" ] && return
  read -p "Move '$src' to: " dst
  [ -z "$dst" ] && return
  mv "$src" "$dst" 2>/dev/null
  read -n1 -s -p "Done."
  refresh_entries
}

action_delete() {
  tgt="${ENTRIES[cursor]}"
  [ -z "$tgt" ] && return
  read -p "Delete '$tgt'? (y/n): " confirm
  [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || return
  rm -rf "$tgt"
  read -n1 -s -p "Deleted."
  refresh_entries
}

action_rename() {
  src="${ENTRIES[cursor]}"
  [ -z "$src" ] && return
  read -p "Rename '$src' to: " new_name
  [ -z "$new_name" ] && return
  mv "$src" "$new_name"
  read -n1 -s -p "Renamed."
  refresh_entries
}

simple_editor() {
  local file="$1"
  [ ! -f "$file" ] && echo "Not a file." && read -n1 -s && return

  local tmp=$(mktemp)
  cp "$file" "$tmp"

  local cursor=0
  local lines total

  while :; do
    clear
    echo "Editing: $file"
    echo "(↑/↓ to move, Enter to edit, Ctrl+X to save and exit)"
    echo "------------------------------------"

    mapfile -t lines < "$tmp"
    total=${#lines[@]}

    for i in "${!lines[@]}"; do
      if [ "$i" -eq "$cursor" ]; then
        printf "\e[7m%3d: %s\e[0m\n" "$((i+1))" "${lines[i]}"
      else
        printf "%3d: %s\n" "$((i+1))" "${lines[i]}"
      fi
    done

    echo "------------------------------------"
    echo "Line: $((cursor + 1)) / $total"

    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 rest || true
        key+="$rest"
        ;;
    esac

    case "$key" in
      $'\x1b[A') ((cursor > 0)) && ((cursor--)) ;;
      $'\x1b[B') ((cursor < total - 1)) && ((cursor++)) ;;
      $'\x0a')
        read -e -p "Edit Line $((cursor+1)): " new_line
        sed -i "$((cursor+1))s/.*/$new_line/" "$tmp"
        ;;
      $'\x18')
        cp "$tmp" "$file"
        echo "Saved."
        sleep 1
        break
        ;;
    esac
  done
}

action_edit() {
  local file="${ENTRIES[cursor]}"
  simple_editor "$file"
  refresh_entries
}

action_permissions() {
  src="${ENTRIES[cursor]}"
  [ -z "$src" ] && return
  read -p "Set permissions (e.g., 755): " perms
  chmod "$perms" "$src"
  read -n1 -s -p "Done."
  refresh_entries
}

action_search() {
  read -p "Search (pattern): " pattern
  [ -z "$pattern" ] && return
  find . -name "*$pattern*" 2>/dev/null
  read -n1 -s -p "Press any key."
}

action_mkdir() {
  read -p "New directory name: " dir_name
  [ -z "$dir_name" ] && return
  mkdir "$dir_name"
  refresh_entries
}

cursor=0
scroll_offset=0
refresh_entries

while :; do
  render_ui
  [ "$cursor" -lt "$scroll_offset" ] && scroll_offset=$cursor
  rows=$(tput lines)
  body_rows=$((rows - 6))
  [ "$cursor" -ge $((scroll_offset + body_rows)) ] && scroll_offset=$((cursor - body_rows + 1))
  key=$(read_key)
  case "$key" in
    $'\x1b[A') cursor=$((cursor - 1)); [ "$cursor" -lt 0 ] && cursor=0 ;;
    $'\x1b[B') cursor=$((cursor + 1)); [ "$cursor" -ge "$ENTRIES_TOTAL" ] && cursor=$((ENTRIES_TOTAL - 1)) ;;
    $'\x1b[C') action_enter ;;
    $'\x1b[D') action_parent ;;
    '') action_enter ;;
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
