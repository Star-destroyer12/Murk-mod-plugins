#!/bin/bash
set -e

echo "Replacing 'crosh' with modified MushM script..."
echo "You will still be able to use all original functions and plugins."

target_dir="/usr/bin"
target_file="crosh"
temp_file="/tmp/mushm.sh"
url="https://raw.githubusercontent.com/Star-destroyer12/Murk-mod-plugins/main/utils/mushm.sh"
backup_dir="/mnt/stateful_partition/murkmod/backups"

mkdir -p "$backup_dir"

cd "$target_dir" || { echo "Failed to change directory to $target_dir"; exit 1; }

echo "Downloading mushm.sh..."
curl -fsSLo "$temp_file" "$url" || { echo "Failed to download mushm.sh from $url"; exit 1; }

if [[ -f "$target_file" ]]; then
    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_file="$backup_dir/${target_file}_backup_$timestamp.bak"
    echo "Backing up '$target_file' to '$backup_file'..."
    cp "$target_file" "$backup_file" || { echo "Backup failed"; exit 1; }
fi

echo "Replacing '$target_file'..."
cat "$temp_file" > "$target_file"
chmod +x "$target_file"
rm -f "$temp_file"

echo "Replacement complete."
if [[ -n "$backup_file" ]]; then
    echo "Backup saved to: $backup_file"
else
    echo "No previous file found, no backup made."
fi
