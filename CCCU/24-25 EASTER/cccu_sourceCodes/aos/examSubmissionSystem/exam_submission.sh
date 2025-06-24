#!/bin/bash

SUBMISSION_DIR="submissions"
LOG_FILE="submission_log.txt"
HASH_DB="file_hashes.db"

mkdir -p "$SUBMISSION_DIR"
touch "$LOG_FILE" "$HASH_DB"

log_submission() {
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local student="$1"
    local filename="$2"
    local size="$3"
    local status="$4"
    local hash="$5"
    
    # Escape any pipe characters in the data to prevent log corruption
    student="${student//|/_}"
    filename="${filename//|/_}"
    
    echo "$timestamp|Student:$student|File:$filename|Size:$size|Status:$status|Hash:$hash" >> "$LOG_FILE"
}

validate_student_id() {
    local student_id="$1"
    
    if [ -z "$student_id" ]; then
        echo "Error: Student ID cannot be empty!"
        return 1
    fi
    
    # Basic student ID format validation (adjust pattern as needed)
    if ! [[ "$student_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "Error: Student ID contains invalid characters!"
        return 1
    fi
    
    return 0
}

validate_file() {
    local file="$1"
    local student_id="$2"
    
    # Check if file exists and is readable
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        echo "Error: File not found or not readable!"
        log_submission "$student_id" "$(basename "$file")" "NA" "REJECTED_NOT_FOUND" "NA"
        return 1
    fi
    
    # Get file size
    local size=$(stat -c%s "$file" 2>/dev/null) || {
        echo "Error: Cannot determine file size!"
        log_submission "$student_id" "$(basename "$file")" "NA" "REJECTED_STAT_ERROR" "NA"
        return 1
    }
    
    # Size check (5MB limit)
    if (( size > 5242880 )); then
        echo "Error: File too large! Maximum 5MB allowed."
        log_submission "$student_id" "$(basename "$file")" "$size" "REJECTED_SIZE" "NA"
        return 2
    fi
    
    # Enhanced file type validation - check actual file content, not just extension
    local filename=$(basename "$file")
    local extension="${filename##*.}"
    extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
    
    case "$extension" in
        pdf)
            # Check if it's actually a PDF by looking at file header
            if ! head -c 4 "$file" | grep -q "^%PDF"; then
                echo "Error: File is not a valid PDF!"
                log_submission "$student_id" "$filename" "$size" "REJECTED_INVALID_PDF" "NA"
                return 3
            fi
            ;;
        docx)
            # DOCX files are ZIP archives, check for ZIP signature
            if ! head -c 4 "$file" | grep -q "^PK"; then
                echo "Error: File is not a valid DOCX!"
                log_submission "$student_id" "$filename" "$size" "REJECTED_INVALID_DOCX" "NA"
                return 3
            fi
            ;;
        *)
            echo "Error: Invalid format! Only PDF and DOCX files are allowed."
            log_submission "$student_id" "$filename" "$size" "REJECTED_FORMAT" "NA"
            return 3
            ;;
    esac
    
    return 0
}

check_duplicates() {
    local file="$1"
    local student_id="$2"
    local filename=$(basename "$file")
    
    # Calculate file hash
    local file_hash=$(md5sum "$file" 2>/dev/null | cut -d' ' -f1) || {
        echo "Error: Cannot calculate file hash!"
        log_submission "$student_id" "$filename" "NA" "REJECTED_HASH_ERROR" "NA"
        return 1
    }
    
    # Filename duplicate check in submission directory
    if [ -f "$SUBMISSION_DIR/$filename" ]; then
        echo "Error: A file with this name already exists!"
        log_submission "$student_id" "$filename" "NA" "REJECTED_NAME_DUP" "$file_hash"
        return 2
    fi
    
    # Content duplicate check using file hash
    if grep -q "^$file_hash$" "$HASH_DB" 2>/dev/null; then
        echo "Error: This file content has already been submitted!"
        local original_submission=$(grep "$file_hash" "$LOG_FILE" | head -1)
        echo "Original submission: $original_submission"
        log_submission "$student_id" "$filename" "NA" "REJECTED_CONTENT_DUP" "$file_hash"
        return 3
    fi
    
    # Store the hash for future reference (but only after successful submission)
    echo "$file_hash" > /tmp/pending_hash_$$
    echo "$file_hash"
    return 0
}

submit_assignment() {
    read -p "Enter Student ID: " student_id
    
    # Validate student ID
    if ! validate_student_id "$student_id"; then
        return 1
    fi
    
    read -p "Enter file path: " file_path
    
    # Security: Remove any path traversal attempts
    file_path=$(realpath "$file_path" 2>/dev/null) || {
        echo "Error: Invalid file path!"
        return 1
    }
    
    # Validate file
    if ! validate_file "$file_path" "$student_id"; then
        return 1
    fi
    
    # Check for duplicates
    local file_hash
    if ! file_hash=$(check_duplicates "$file_path" "$student_id"); then
        return 1
    fi
    
    # Perform the actual submission
    local filename=$(basename "$file_path")
    local file_size=$(stat -c%s "$file_path")
    local target_path="$SUBMISSION_DIR/$filename"
    
    # Create a temporary copy first for atomic operation
    local temp_file="$SUBMISSION_DIR/.tmp_${filename}_$$"
    
    if cp "$file_path" "$temp_file" 2>/dev/null; then
        # Atomic move to final location
        if mv "$temp_file" "$target_path" 2>/dev/null; then
            # Only now add the hash to the database
            cat /tmp/pending_hash_$$ >> "$HASH_DB" 2>/dev/null
            rm -f /tmp/pending_hash_$$
            
            log_submission "$student_id" "$filename" "$file_size" "ACCEPTED" "$file_hash"
            echo "Submission successful!"
            echo "File: $filename"
            echo "Size: $file_size bytes"
            echo "Hash: $file_hash"
        else
            echo "Error: Failed to finalize submission!"
            rm -f "$temp_file"
            rm -f /tmp/pending_hash_$$
            log_submission "$student_id" "$filename" "$file_size" "REJECTED_COPY_ERROR" "$file_hash"
            return 1
        fi
    else
        echo "Error: Failed to copy file!"
        rm -f /tmp/pending_hash_$$
        log_submission "$student_id" "$filename" "$file_size" "REJECTED_COPY_ERROR" "$file_hash"
        return 1
    fi
}

check_submission() {
    read -p "Enter filename to check: " filename
    
    if [ -z "$filename" ]; then
        echo "Error: Filename cannot be empty!"
        return 1
    fi
    
    # Security: prevent path traversal
    filename=$(basename "$filename")
    
    local found_file="$SUBMISSION_DIR/$filename"
    if [ -f "$found_file" ]; then
        echo "File found: $found_file"
        local size=$(stat -c%s "$found_file" 2>/dev/null)
        local hash=$(md5sum "$found_file" 2>/dev/null | cut -d' ' -f1)
        echo "Size: $size bytes"
        echo "Hash: $hash"
        
        # Show submission details from log
        echo -e "\nSubmission details:"
        grep "|File:$filename|" "$LOG_FILE" | tail -1
    else
        echo "File not found in submissions directory."
    fi
}

view_history() {
    read -p "Enter Student ID: " student_id
    
    if [ -z "$student_id" ]; then
        echo "Error: Student ID cannot be empty!"
        return 1
    fi
    
    echo -e "\nSubmission History for Student: $student_id"
    echo "=================================================================="
    
    local found=false
    while IFS='|' read -r timestamp student file size status hash; do
        if [[ "$student" == "Student:$student_id" ]]; then
            found=true
            # Clean up the field values
            file="${file#File:}"
            size="${size#Size:}"
            status="${status#Status:}"
            hash="${hash#Hash:}"
            
            printf "%-20s | %-15s | %-10s | %-20s | %-32s\n" \
                "$timestamp" "$file" "$size" "$status" "$hash"
        fi
    done < "$LOG_FILE"
    
    if [ "$found" = false ]; then
        echo "No submissions found for student: $student_id"
    fi
}

view_all_submissions() {
    echo -e "\nAll Submissions Report"
    echo "======================"
    
    if [ ! -s "$LOG_FILE" ]; then
        echo "No submissions found."
        return
    fi
    
    # Show filtering options
    echo "Filter options:"
    echo "1. Show all submissions"
    echo "2. Show only accepted submissions"
    echo "3. Show only rejected submissions"
    read -p "Choose filter [1-3]: " filter_choice
    
    local filter_pattern=""
    case $filter_choice in
        1) filter_pattern=".*" ;;
        2) filter_pattern="Status:ACCEPTED" ;;
        3) filter_pattern="Status:REJECTED" ;;
        *) 
            echo "Invalid choice, showing all submissions."
            filter_pattern=".*"
            ;;
    esac
    
    echo
    printf "%-20s | %-12s | %-25s | %-10s | %-15s | %-32s\n" \
        "Timestamp" "Student ID" "Filename" "Size" "Status" "Hash"
    echo "======================================================================================================"
    
    local count=0
    while IFS='|' read -r timestamp student file size status hash; do
        if [[ "$status" =~ $filter_pattern ]]; then
            # Clean up the field values
            student="${student#Student:}"
            file="${file#File:}"
            size="${size#Size:}"
            status="${status#Status:}"
            hash="${hash#Hash:}"
            
            # Truncate long filenames for display
            if [ ${#file} -gt 25 ]; then
                file="${file:0:22}..."
            fi
            
            # Format file size for better readability
            if [[ "$size" =~ ^[0-9]+$ ]]; then
                if (( size > 1048576 )); then
                    size="$((size / 1048576))MB"
                elif (( size > 1024 )); then
                    size="$((size / 1024))KB"
                else
                    size="${size}B"
                fi
            fi
            
            printf "%-20s | %-12s | %-25s | %-10s | %-15s | %-32s\n" \
                "$timestamp" "$student" "$file" "$size" "$status" "${hash:0:8}..."
            
            ((count++))
        fi
    done < "$LOG_FILE"
    
    echo "======================================================================================================"
    echo "Total submissions displayed: $count"
    
    # Show summary statistics
    if [ $filter_choice -eq 1 ]; then
        echo
        echo "Summary Statistics:"
        echo "-------------------"
        local total_accepted=$(grep "Status:ACCEPTED" "$LOG_FILE" | wc -l)
        local total_rejected=$(grep "Status:REJECTED" "$LOG_FILE" | wc -l)
        local total_students=$(grep "Status:ACCEPTED" "$LOG_FILE" | cut -d'|' -f2 | sort -u | wc -l)
        
        echo "Total accepted: $total_accepted"
        echo "Total rejected: $total_rejected"
        echo "Unique students: $total_students"
        
        # Show rejection reasons breakdown
        echo
        echo "Rejection Reasons:"
        echo "------------------"
        grep "Status:REJECTED" "$LOG_FILE" | cut -d'|' -f5 | cut -d':' -f2 | sort | uniq -c | while read count reason; do
            printf "%-20s: %d\n" "$reason" "$count"
        done
    fi
}

generate_report() {
    echo -e "\nDuplicate Content Analysis Report"
    echo "=================================="
    
    if [ ! -s "$HASH_DB" ]; then
        echo "No submissions found."
        return
    fi
    
    local temp_sorted=$(mktemp)
    local temp_duplicates=$(mktemp)
    
    # Find duplicate hashes
    sort "$HASH_DB" | uniq -d > "$temp_duplicates"
    
    if [ ! -s "$temp_duplicates" ]; then
        echo "No duplicate content detected."
    else
        echo "Duplicate content detected for the following hashes:"
        echo
        
        while read -r duplicate_hash; do
            echo "Hash: $duplicate_hash"
            echo "Associated submissions:"
            grep "$duplicate_hash" "$LOG_FILE" | while IFS='|' read -r timestamp student file size status hash; do
                student="${student#Student:}"
                file="${file#File:}"
                status="${status#Status:}"
                printf "  %-15s | %-20s | %-15s | %s\n" "$student" "$file" "$status" "$timestamp"
            done
            echo
        done < "$temp_duplicates"
    fi
    
    # Cleanup
    rm -f "$temp_sorted" "$temp_duplicates"
    
    # Summary statistics
    echo "Summary:"
    echo "--------"
    local total_submissions=$(grep "ACCEPTED" "$LOG_FILE" | wc -l)
    local total_rejections=$(grep -v "ACCEPTED" "$LOG_FILE" | grep "REJECTED" | wc -l)
    local duplicate_rejections=$(grep "REJECTED.*DUP" "$LOG_FILE" | wc -l)
    
    echo "Total successful submissions: $total_submissions"
    echo "Total rejections: $total_rejections"
    echo "Rejections due to duplicates: $duplicate_rejections"
}

exit_system() {
    read -p "Are you sure you want to exit? (Y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Cleanup any temporary files
        rm -f /tmp/pending_hash_$
        echo "Goodbye!"
        exit 0
    fi
}

# Main menu loop
while true; do
    echo -e "\nExamination Submission System"
    echo "============================="
    echo "1. Submit Assignment"
    echo "2. Check Submission"
    echo "3. View Student History"
    echo "4. View All Submissions"
    echo "5. Generate Duplicate Report"
    echo "6. Exit"
    
    read -p "Choose [1-6]: " choice
    case $choice in
        1) submit_assignment ;;
        2) check_submission ;;
        3) view_history ;;
        4) view_all_submissions ;;
        5) generate_report ;;
        6) exit_system ;;
        *) echo "Invalid choice! Please select 1-6." ;;
    esac
done
