#!/bin/bash
set -e

# Define a simple error handler
error_exit() {
    echo "$1" 1>&2
    exit 1
}

# Prompt user for confirmation (yes or no)
confirm_action() {
    while true; do
        read -p "$1 (y/n): " choice
        case "$choice" in
            [Yy]* ) return 0;;  # Yes
            [Nn]* ) return 1;;  # No
            * ) echo "Please answer with 'y' or 'n'.";;
        esac
    done
}

# Remount root filesystem as read-write (if required)
mount -o remount,rw / || error_exit "Failed to remount root filesystem as read-write."

echo "Replacing 'crosh' with modified MushM script..."
echo "You will still be able to use all original functions and plugins."

# Setup variables
target_dir="/usr/bin"
target_file="crosh"
temp_file="mushm.sh"
url="https://raw.githubusercontent.com/Star-destroyer12/Murk-mod-plugins/main/utils/mushm.sh"
backup_dir="/mnt/stateful_partition/murkmod/mush/backups"

# Create backup directory if it doesn't exist
mkdir -p "$backup_dir" || error_exit "Failed to create backup directory."

# Navigate to target directory
cd "$target_dir" || error_exit "Failed to change directory to $target_dir."

# Ensure curl is available
command -v curl >/dev/null 2>&1 || error_exit "'curl' is required but not installed."

# Download the new mushm.sh script
echo "Downloading mushm.sh..."
curl -fsSLo "$temp_file" "$url" || error_exit "Failed to download mushm.sh from $url."

# Ask for confirmation before backing up the file
if [[ -f "$target_file" ]]; then
    echo "Warning: This will back up your current '$target_file' before replacing it with the new script."
    if confirm_action "Are you sure you want to continue with backing up '$target_file'?"; then
        timestamp=$(date +"%Y%m%d_%H%M%S")
        backup_file="$backup_dir/${target_file}_backup_$timestamp.bak"
        echo "Backing up '$target_file' to '$backup_file'..."

        # Check available space before backup
        available_space=$(df "$backup_dir" | tail -1 | awk '{print $4}')
        if (( available_space < 1000 )); then
            error_exit "Insufficient space in backup directory. Aborting."
        fi

        # Perform backup
        cp "$target_file" "$backup_file" || error_exit "Backup failed."
    else
        echo "Backup skipped."
        backup_file=""
    fi
fi

# Ask for confirmation before replacing the file
echo "Warning: This will replace your current '$target_file' with the modified script. This action cannot be undone!"
if confirm_action "Are you sure you want to replace '$target_file'?"; then
    echo "Replacing '$target_file' with the modified MushM script..."
    cat "$temp_file" > "$target_file" && chmod +x "$target_file" || error_exit "Failed to replace '$target_file'."

    # Clean up temporary file
    rm -f "$temp_file" || error_exit "Failed to remove temporary file."

    echo "Replacement complete."
else
    echo "Replacement aborted by user."
    exit 0
fi

# Report backup status
if [[ -n "$backup_file" ]]; then
    echo "Backup saved to: $backup_file"
else
    echo "No previous file found, no backup made."
fi
