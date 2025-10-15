#!/bin/bash
set -e

# Mount the file system in read-write mode
mount -o remount,rw /

# Start the main operation
echo "Starting replacement of 'crosh' with the modified MushM script..."
echo "You will still be able to use all original functions and plugins."
echo

target_dir="/usr/bin"
target_file="crosh"
temp_file="mushm.sh"
url="https://raw.githubusercontent.com/Star-destroyer12/Murk-mod-plugins/main/utils/mushm.sh"
backup_dir="/mnt/stateful_partition/murkmod/mush/backups"

# Create backup directory if it doesn't exist
mkdir -p "$backup_dir"
echo "Backup directory: $backup_dir"
echo

# Navigate to target directory
cd "$target_dir" || { echo "Failed to change directory to $target_dir"; exit 1; }
echo "Changed directory to $target_dir"
echo

# Download the script
echo -n "Downloading mushm.sh... "
curl -fsSLo "$temp_file" "$url" || { echo "Failed to download mushm.sh from $url"; exit 1; }
echo "done!"

# Backup original file if it exists
if [[ -f "$target_file" ]]; then
    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_file="$backup_dir/${target_file}_backup_$timestamp.bak"
    echo -n "Backing up '$target_file'... "
    cp "$target_file" "$backup_file" || { echo "Backup failed"; exit 1; }
    echo "done! Backup saved as '$backup_file'"
else
    echo "No existing '$target_file' found. Skipping backup."
fi
echo

# Replace the target file with the modified script
echo -n "Replacing '$target_file' with the new script... "
cat "$temp_file" > "$target_file"
chmod +x "$target_file"
rm -f "$temp_file"
echo "done!"

echo
echo "Replacement complete!"
if [[ -n "$backup_file" ]]; then
    echo "Backup saved to: $backup_file"
else
    echo "No backup was made, since the target file wasn't present."
fi
