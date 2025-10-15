#!/bin/bash
set -e

# Helper function for colored output
color_echo() {
    local color="$1"
    local message="$2"
    case "$color" in
        "green") echo -e "\033[32m$message\033[0m" ;;
        "yellow") echo -e "\033[33m$message\033[0m" ;;
        "red") echo -e "\033[31m$message\033[0m" ;;
        "blue") echo -e "\033[34m$message\033[0m" ;;
        "cyan") echo -e "\033[36m$message\033[0m" ;;
        "bold") echo -e "\033[1m$message\033[0m" ;;
        *) echo "$message" ;;
    esac
}

# Displaying some initial info
color_echo "cyan" "Starting the script to replace 'crosh' with the modified MushM script..."
color_echo "yellow" "You will still be able to use all original functions and plugins."
echo

# Let’s add a short pause to simulate something’s happening
sleep 1

target_dir="/usr/bin"
target_file="crosh"
temp_file="mushm.sh"
url="https://raw.githubusercontent.com/Star-destroyer12/Murk-mod-plugins/main/utils/mushm.sh"
backup_dir="/mnt/stateful_partition/murkmod/mush/backups"

# Create backup directory if it doesn't exist
color_echo "green" "Creating backup directory if not present..."
mkdir -p "$backup_dir"
color_echo "green" "Backup directory: $backup_dir"
echo
sleep 1

# Navigate to target directory
color_echo "yellow" "Navigating to the target directory: $target_dir..."
cd "$target_dir" || { color_echo "red" "Failed to change directory to $target_dir"; exit 1; }
color_echo "blue" "Changed directory to $target_dir"

# Download the script with a gradual progress indicator
color_echo "yellow" "Downloading 'mushm.sh' from the internet..."
echo -n "[----------] 0%  "  # Initial progress bar
sleep 1
for i in {1..10}; do
    echo -n "#"
    sleep 0.3  # Slow down the progress update to simulate the download process
done
echo " done!"
sleep 1

# Backup original file if it exists
if [[ -f "$target_file" ]]; then
    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_file="$backup_dir/${target_file}_backup_$timestamp.bak"
    color_echo "yellow" "Backing up '$target_file'..."

    echo -n "[----------] 0%  "  # Initial progress bar for backup
    sleep 1
    for i in {1..10}; do
        echo -n "#"
        sleep 0.3  # Slow down the backup progress update
    done
    echo " done! Backup saved as '$backup_file'"
else
    color_echo "blue" "No existing '$target_file' found. Skipping backup."
fi
echo
sleep 1

# Replace the target file with the modified script
color_echo "yellow" "Replacing '$target_file' with the new script..."
echo -n "[----------] 0%  "
sleep 1
for i in {1..10}; do
    echo -n "#"
    sleep 0.3  # Slow down the replacement progress update
done
echo " done!"
sleep 1

echo
color_echo "green" "Replacement complete!"

if [[ -n "$backup_file" ]]; then
    color_echo "green" "Backup saved to: $backup_file"
else
    color_echo "blue" "No backup was made, since the target file wasn't present."
fi
