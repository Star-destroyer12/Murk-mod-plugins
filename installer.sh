#!/bin/bash

echo "This will overwrite the 'crosh' file with a modified 'mush' script named 'MushM'."
echo "You will still be able to use all original functions and plugins."
echo "Only the mush script is being replaced."
read -p "Are you sure you want to continue? [y/N]: " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Operation cancelled."
    exit 0
fi

target_dir="/usr/bin"
target_file="crosh"
temp_file="mushm.sh"
url="https://raw.githubusercontent.com/Star-destroyer12/Murk-mod-plugins/refs/heads/main/utils/mushm.sh"
backup_dir="/mnt/stateful_partition/murkmod/backups"

if [[ ! -d "$target_dir" ]]; then
    echo "Error: Target directory '$target_dir' does not exist." >&2
    exit 1
fi

if [[ ! -d "$backup_dir" ]]; then
    echo "Creating backup directory at $backup_dir"
    if ! mkdir -p "$backup_dir"; then
        echo "Error: Failed to create backup directory." >&2
        exit 1
    fi
fi

cd "$target_dir" || { echo "Failed to change directory to $target_dir"; exit 1; }

echo "Downloading mushm.sh..."
if ! curl -fsSL -o "$temp_file" "$url"; then
    echo "Error: Failed to download mush.sh from $url" >&2
    exit 1
fi

if [[ -f "$target_file" ]]; then
    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_file="$backup_dir/${target_file}_backup_$timestamp.bak"
    echo "Backing up existing '$target_file' to '$backup_file'..."
    if ! cp "$target_file" "$backup_file"; then
        echo "Backup failed." >&2
        exit 1
    fi
fi

echo "Replacing '$target_file' with contents of '$temp_file'..."
if ! cat "$temp_file" > "$target_file"; then
    echo "Error: Failed to overwrite $target_file" >&2
    exit 1
fi

rm -f "$temp_file"

echo "Replacement complete. '$target_file' has been updated successfully."
echo "Backup saved to: $backup_file"
