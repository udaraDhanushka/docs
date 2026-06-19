#!/bin/bash

initial_dir=$(pwd)
BACKUP_DIR="$initial_dir/Backup"
LOG_FILE="$initial_dir/backup_log.txt"
current_dir="$initial_dir"

mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

log_operation() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1: $2" >> "$LOG_FILE"
}

list_files() {
    echo -e "\nCurrent directory: $current_dir"
    for file in "$current_dir"/*; do
        if [ -e "$file" ]; then
            file_name=$(basename "$file")
            file_size=$(stat -c%s "$file")
            file_date=$(stat -c%y "$file" | cut -d'.' -f1)
            printf "%-25s %-10s %-20s\n" "$file_name" "$file_size" "$file_date"
        fi
    done
}

move_file() {
    read -p "Enter source filename: " src_file
    file_path="$current_dir/$src_file"

    if [ ! -e "$file_path" ]; then
        echo "Error: Source file not found!"
        return 1
    fi

    read -p "Enter target path (directory or filename): " target_path
    full_target_path="$current_dir/$target_path"

    # Create parent directory if needed
    mkdir -p "$(dirname "$full_target_path")"

    # Check if target is directory
    if [ -d "$full_target_path" ]; then
        full_target_path="$full_target_path/$(basename "$file_path")"
    fi

    if [ "$file_path" = "$full_target_path" ]; then
        echo "Error: Cannot move to the same location!"
        return 1
    fi

    # POSIX-compliant space check
    target_dir=$(dirname "$full_target_path")
    file_size=$(stat -c%s "$file_path" 2>/dev/null) || {
        echo "Error: Failed to get file size"
        return 1
    }

    available_blocks=$(df -P "$target_dir" | tail -1 | tr -s ' ' | cut -d ' ' -f4)
    available_bytes=$((available_blocks * 1024))

    if [ "$available_bytes" -lt "$file_size" ]; then
        echo "Error: Not enough space in $target_dir (needs $file_size bytes)"
        return 1
    fi

    if mv "$file_path" "$full_target_path"; then
        echo "File moved successfully!"
        log_operation "MOVED" "$file_path to $full_target_path"
    else
        echo "Move operation failed"
        log_operation "MOVE FAILED" "$file_path"
        return 1
    fi
}

rename_file() {
    read -p "Enter current filename: " old_name
    old_path="$current_dir/$old_name"
    
    if [ ! -e "$old_path" ]; then
        echo "File/directory not found!"
        return
    fi

    read -p "Enter new filename: " new_name
    new_path="$current_dir/$new_name"

    if [ -e "$new_path" ]; then
        echo "Error: '$new_name' already exists! Please choose a different name."
        log_operation "RENAME FAILED" "Duplicate target $new_path"
        return
    fi

    if mv "$old_path" "$new_path"; then
        echo "File renamed successfully!"
        log_operation "RENAMED" "$old_name to $new_name"
    else
        echo "Rename operation failed"
        log_operation "RENAME FAILED" "$old_name to $new_name"
    fi
}

backup_file() {
    read -p "Enter filename to backup: " file
    file_path="$current_dir/$file"
    
    if [ ! -e "$file_path" ]; then
        echo "File/directory not found!"
        return
    fi

    timestamp=$(date +%Y%m%d%H%M%S)
    backup_name="${timestamp}_$(basename "$file_path")"
    backup_path="$BACKUP_DIR/$backup_name"

    if rsync -a -- "$file_path" "$backup_path"; then
        echo "File backed up successfully!"
        log_operation "BACKED UP" "$file_path to $backup_path"
        
      
        backup_size=$(du -sb "$BACKUP_DIR" | cut -f1)
        if [ "$backup_size" -gt 524288000 ]; then
            echo "WARNING: Backup directory exceeds 500MB! Removing oldest backup."
            oldest=$(ls -t "$BACKUP_DIR" | tail -1)
            rm -rf "$BACKUP_DIR/$oldest"
            log_operation "CLEANUP" "Removed $oldest"
        fi
    else
        echo "Backup operation failed"
        log_operation "BACKUP FAILED" "$file_path"
    fi
}

navigate() {
    echo -e "\nNavigation options:"
    echo "1. Enter directory path"
    echo "2. Go up one level (..)"
    echo "3. Return to root directory ($initial_dir)"
    
    read -p "Choose option [1-3]: " nav_choice
    case $nav_choice in
        1)
            read -p "Enter directory path: " dir
            if [[ "$dir" == /* ]]; then
                new_dir="$dir"
            else
                new_dir="$current_dir/$dir"
            fi
            ;;
        2)
            new_dir=$(dirname "$current_dir")
            ;;
        3)
            new_dir="$initial_dir"
            ;;
        *)
            echo "Invalid choice"
            return
            ;;
    esac

    if [ -d "$new_dir" ]; then
        current_dir="$new_dir"
        echo "Now in: $current_dir"
        log_operation "NAVIGATED" "to $current_dir"
    else
        echo "Invalid directory: $new_dir"
    fi
}

delete_file() {
    read -p "Enter filename to delete: " file
    file_path="$current_dir/$file"
    
    if [ ! -e "$file_path" ]; then
        echo "File/directory not found!"
        return
    fi

    read -p "Are you sure you want to delete? (Y/N): " confirm
    if [[ "$confirm" =~ [Yy] ]]; then
        rm -rf "$file_path"
        echo "Deleted permanently!"
        log_operation "DELETED" "$file_path"
    else
        echo "Deletion canceled"
    fi
}

exit_script() {
    read -p "Are you sure you want to exit? (Y/N): " confirm
    [[ "$confirm" =~ [Yy] ]] && exit 0
}

while true; do
    echo -e "\nUniversity File Management System"
    echo "1. List files"
    echo "2. Navigate directories"
    echo "3. Move file"
    echo "4. Rename file"
    echo "5. Delete file"
    echo "6. Backup file"
    echo "7. Exit"
    
    read -p "Choose an option [1-7]: " choice
    case $choice in
        1) list_files ;;
        2) navigate ;;
        3) move_file ;;
        4) rename_file ;;
        5) delete_file ;;
        6) backup_file ;;
        7) exit_script ;;
        *) echo "Invalid choice" ;;
    esac
done
