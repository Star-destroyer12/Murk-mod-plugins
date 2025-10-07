#!/usr/bin/env bash
# Murk Manager - simple terminal file manager / editor
# Author: Star
# Version: 1

set -euo pipefail

PLUGIN_NAME="Murk Manager"
PLUGIN_FUNCTION="A robust file manager with navigation, file operations, and context menus"
PLUGIN_DESCRIPTION="File manager with copy, move, delete, rename, search, file preview, permissions management, and a custom editor"
PLUGIN_AUTHOR="Star"
PLUGIN_VERSION=1

# --- Configuration ---
START_DIR="${1:-.}"

# --- sanity checks ---
for cmd in realpath ls cp mv rm mkdir rmdir less sed awk find date whoami clear nano stat chmod chown mktemp tput; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    sleep 2
    exit 1
  fi
done

# --- ensure we restore terminal state ---
cleanup() {
  show_cursor
  stty sane >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- UI helpers ---
cls(){ clear; }
move_cursor(){ printf "\033[%s;%sH" "$1" "$2"; }
hide_cursor(){ printf '\e[?25l'; }
show_cursor(){ printf '\e[?25h'; }

# Read a single key (handles arrows and escape sequences)
read_key(){
  local key rest
  IFS= read -rsn1 key 2>/dev/null || key=''
  if [[ $key == $'\x1b' ]]; then
    # possible escape sequence (read remaining bytes non-blocking)
    IFS= read -rsn2 -t 0.0005 rest 2>/dev/null || rest=''
    key+="$rest"
  fi
  printf '%s' "$key"
}

# --- Confirmation prompt used by delete ---
confirm_prompt(){
  local prompt="${1:-Are you sure? (y/N): }"
  read -rp "$prompt" yn
  case "$yn" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# --- File list management ---
CURRENT_DIR="$(realpath "$START_DIR")"
cd "$CURRENT_DIR" || exit 1

ENTRIES=()
ENTRIES_TOTAL=0

refresh_entries(){
  # list entries without colors; if none, produce empty array
  mapfile -t ENTRIES < <(ls -A --color=never 2>/dev/null || true)
  # sort directories first
  local dirs=() files=() e
  for e in "${ENTRIES[@]}"; do
    if [[ -d "$e" ]]; then dirs+=("$e"); else files+=("$e"); fi
  done
  ENTRIES=( "${dirs[@]}" "${files[@]}" )
  ENTRIES_TOTAL=${#ENTRIES[@]}
}

# Render the UI
render_ui(){
  cls
  local header="Murk Manager  —  cwd: $(pwd)"
  echo "$header"
  printf '%s\n\n' "Use ↑/↓ to move • ← parent • → enter • Enter view • c:copy m:move d:delete e:edit n:mkdir r:rename s:search q:quit p:permissions x:context"
  local cols rows
  cols=$(tput cols); rows=$(tput lines)
  local body_rows=$((rows-6))
  [[ $body_rows -lt 1 ]] && body_rows=1

  # protect start/end bounds
  local start=$((scroll_offset))
  local end=$((start + body_rows - 1))
  (( end >= ENTRIES_TOTAL )) && end=$((ENTRIES_TOTAL - 1))
  if (( ENTRIES_TOTAL == 0 )); then
    echo "(empty directory)"
  else
    local i
    for i in $(seq $start $end); do
      local idx_display=$((i+1))
      local name="${ENTRIES[i]}"
      local indicator=' '
      [[ -d "$name" ]] && indicator='d'
      if [[ $i -eq $cursor ]]; then
        # highlighted
        printf "\e[7m %3s %s\e[0m\n" "[$idx_display]" "$indicator $name"
      else
        printf " %3s %s\n" "[$idx_display]" "$indicator $name"
      fi
    done
  fi

  # footer
  printf "\nEntries: %d    Selected: %s\n" "$ENTRIES_TOTAL" "${ENTRIES[cursor]:-}"
}

# utilities for scrolling
ensure_visible(){
  local rows
  rows=$(tput lines)
  local body_rows=$((rows-6))
  (( body_rows < 1 )) && body_rows=1
  if (( cursor < scroll_offset )); then scroll_offset=$cursor; fi
  if (( cursor > scroll_offset + body_rows -1 )); then scroll_offset=$((cursor - body_rows +1)); fi
  (( scroll_offset < 0 )) && scroll_offset=0
}

# action functions
action_enter(){
  local sel="${ENTRIES[cursor]:-}" || return
  [[ -z "$sel" ]] && return
  if [[ -d "$sel" ]]; then
    cd -- "$sel" || return
    cursor=0; scroll_offset=0
    refresh_entries
  else
    less -- "$sel"
  fi
}

action_parent(){
  cd .. || return
  cursor=0; scroll_offset=0
  refresh_entries
}

# --- Context Menu for File Actions ---
context_menu() {
  local sel="${ENTRIES[cursor]:-}"
  if [[ -z "$sel" ]]; then return; fi
  echo -e "\nContext menu for: $sel"
  echo "1) Rename"
  echo "2) Move"
  echo "3) Delete"
  echo "4) Open in Editor"
  echo "5) Copy"
  echo "6) Permissions"
  echo "7) Quit Context Menu"
  read -rp "Select an action [1-7]: " action

  case "$action" in
    1) action_rename ;;
    2) action_move ;;
    3) action_delete ;;
    4) action_edit "${sel}" ;;  # Open the custom editor
    5) action_copy ;;
    6) action_permissions ;;
    7) return ;;
    *) echo "Invalid option."; sleep 1 ;;
  esac
}

action_copy(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Copy '$src' to (path): " dst
  [[ -z "$dst" ]] && return
  cp -a -- "$src" "$dst" 2>/dev/null || echo "Copy failed"
  read -rp "Done. Press any key." -n1 _
  refresh_entries
}

action_move(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Move '$src' to (path): " dst
  [[ -z "$dst" ]] && return
  mv -- "$src" "$dst" 2>/dev/null || echo "Move failed"
  read -rp "Done. Press any key." -n1 _
  refresh_entries
}

action_delete(){
  local tgt="${ENTRIES[cursor]:-}" || return
  [[ -z "$tgt" ]] && return
  if confirm_prompt "Delete '$tgt' and its contents? (y/N): "; then
    rm -rf -- "$tgt" 2>/dev/null || echo "Delete failed"
  else
    echo "Aborted."
  fi
  read -rp "Press any key." -n1 _
  refresh_entries
}

action_rename(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Rename '$src' to: " new_name
  [[ -z "$new_name" ]] && return
  mv -- "$src" "$new_name" 2>/dev/null || echo "Rename failed"
  read -rp "Done. Press any key." -n1 _
  refresh_entries
}

action_edit(){
  local file="$1"
  edit_file "$file"
}

action_permissions(){
  local src="${ENTRIES[cursor]:-}" || return
  [[ -z "$src" ]] && return
  read -rp "Change permissions for '$src'. Enter mode (e.g., 755): " perms
  chmod "$perms" "$src" 2>/dev/null || echo "chmod failed"
  read -rp "Done. Press any key." -n1 _
  refresh_entries
}

# --- Custom File Editor ---
edit_file() {
  local file="$1"
  if [[ -z "$file" || ! -e "$file" ]]; then
    echo "File not found: $file"
    read -rp "Press any key." -n1 _
    return
  fi

  # if directory, open nothing
  if [[ -d "$file" ]]; then
    echo "'$file' is a directory."
    read -rp "Press any key." -n1 _
    return
  fi

  local temp_file
  temp_file="$(mktemp)" || { echo "Failed to create temp file"; return; }
  cp -- "$file" "$temp_file"

  local cursor_pos=0
  local rows cols
  rows=$(tput lines)
  cols=$(tput cols)

  clear
  echo "Editing: $file (Press Ctrl+X to save and quit)"
  hide_cursor

  while :; do
    clear
    echo "Editing: $file (Ctrl+X to save and quit)"
    echo "----------------------------------------"
    # Display the file content with line numbers
    local i=0
    while IFS= read -r line; do
      # truncate long lines to terminal width for nicer display
      local disp="${line}"
      if (( ${#disp} > cols - 8 )); then
        disp="${disp:0:cols-11}..."
      fi
      printf "%4d  %s\n" "$((i+1))" "$disp"
      ((i++))
    done < "$temp_file"

    echo -e "\nCursor at Line: $((cursor_pos + 1))"
    echo "Commands: ↑/↓ move • Enter edit line • Ctrl+X save+quit"

    # read a key (handle arrows)
    local key rest
    IFS= read -rsn1 key || key=''
    if [[ $key == $'\x1b' ]]; then
      IFS= read -rsn2 -t 0.0005 rest 2>/dev/null || rest=''
      key+="$rest"
    fi

    case "$key" in
      $'\x18')  # Ctrl+X
        # save?
        read -rp "Save changes? (Y/n): " save
        if [[ "$save" != "n" && "$save" != "N" ]]; then
          cp -- "$temp_file" "$file"
          echo "Changes saved."
        else
          echo "Changes discarded."
        fi
        sleep 0.5
        break
        ;;
      $'\x1b[A')  # Up arrow
        ((cursor_pos > 0)) && ((cursor_pos--))
        ;;
      $'\x1b[B')  # Down arrow
        local line_count
        line_count=$(wc -l < "$temp_file")
        ((cursor_pos < line_count - 1)) && ((cursor_pos++))
        ;;
      $'\x0a')  # Enter key -> edit current line
        read -rp "Edit Line $((cursor_pos + 1)): " new_line
        # safe replacement using awk to handle arbitrary contents
        awk -v ln=$((cursor_pos+1)) -v nl="$new_line" 'NR==ln{print nl; next} {print}' "$temp_file" > "${temp_file}.new" && mv "${temp_file}.new" "$temp_file"
        ;;
      *)
        # ignore others
        continue
        ;;
    esac
  done

  show_cursor
  rm -f -- "$temp_file" 2>/dev/null || true
}

# --- Search function (simple substring search) ---
search_entries(){
  read -rp "Search substring: " query
  [[ -z "$query" ]] && return
  local i
  for i in "${!ENTRIES[@]}"; do
    if [[ "${ENTRIES[i]}" == *"$query"* ]]; then
      cursor=$i
      ensure_visible
      return
    fi
  done
  echo "No match found for '$query'"
  read -rp "Press any key." -n1 _
}

# --- Main Loop ---
cursor=0
scroll_offset=0
refresh_entries

# A simple wrapper to run privileged commands remotely (kept from your snippet).
# Note: This runs ssh to 127.0.0.1 on port 1337 with a root key; use with care.
doas() {
  ssh -t -p 1337 -i /rootkey -oStrictHostKeyChecking=no root@127.0.0.1 "$@"
}

hide_cursor
while :; do
  render_ui
  ensure_visible

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
    $'\x1b[C')  # Right arrow (Enter directory or view file)
      action_enter
      ;;
    $'\x1b[D')  # Left arrow (Go to parent)
      action_parent
      ;;
    $'\x0a')  # Enter key -> view or enter
      action_enter
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
      action_edit "${ENTRIES[cursor]:-}"
      ;;
    'n')  # Create new directory
      read -rp "Enter directory name: " dir_name
      [[ -n "$dir_name" ]] && mkdir -- "$dir_name"
      refresh_entries
      ;;
    'p')  # Permissions
      action_permissions
      ;;
    's')  # Search
      search_entries
      ;;
    'x')  # Context menu
      context_menu
      ;;
    *) continue
      ;;
  esac
done

show_cursor
exit 0
