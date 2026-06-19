#!/bin/bash

LIBRARY_FILE="library_books.txt"
REQUEST_FILE="book_requests.txt"
LOG_FILE="library_log.txt"

touch "$LIBRARY_FILE" "$REQUEST_FILE" "$LOG_FILE"

log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

view_books() {
    echo -e "\nAvailable Books:"
    if [ ! -s "$LIBRARY_FILE" ]; then
        echo "No books in library!"
        return
    fi
    printf "%-15s %-25s %-20s\n" "ISBN" "Title" "Author"
    printf "%-15s %-25s %-20s\n" "----" "-----" "------"
    while IFS='|' read -r isbn title author; do
        if [ -n "$isbn" ] && [ -n "$title" ] && [ -n "$author" ]; then
            printf "%-15s %-25s %-20s\n" "$isbn" "$title" "$author"
        fi
    done < "$LIBRARY_FILE"
}

add_book() {
    read -p "Enter ISBN: " isbn
    read -p "Enter Title: " title
    read -p "Enter Author: " author
    
    # Validate inputs
    if [ -z "$isbn" ] || [ -z "$title" ] || [ -z "$author" ]; then
        echo "Error: All fields are required!"
        log_action "ADD_FAILED: Missing required fields"
        return 1
    fi
    
    # Check for pipes in input (would break format)
    if [[ "$isbn" == *"|"* ]] || [[ "$title" == *"|"* ]] || [[ "$author" == *"|"* ]]; then
        echo "Error: Fields cannot contain pipe (|) character!"
        log_action "ADD_FAILED: Invalid characters in input"
        return 1
    fi
    
    if grep -q "^$isbn|" "$LIBRARY_FILE"; then
        echo "Error: Book with ISBN $isbn already exists!"
        log_action "ADD_FAILED: Duplicate ISBN $isbn"
        return 1
    fi
    
    echo "$isbn|$title|$author" >> "$LIBRARY_FILE"
    echo "Book added successfully!"
    log_action "ADDED: $isbn|$title|$author"
}

request_book() {
    read -p "Enter Student ID: " student_id
    read -p "Enter Book ISBN: " isbn
    
    # Validate inputs
    if [ -z "$student_id" ] || [ -z "$isbn" ]; then
        echo "Error: Student ID and ISBN are required!"
        log_action "REQUEST_FAILED: Missing required fields"
        return 1
    fi
    
    # Check for pipes in input
    if [[ "$student_id" == *"|"* ]] || [[ "$isbn" == *"|"* ]]; then
        echo "Error: Fields cannot contain pipe (|) character!"
        log_action "REQUEST_FAILED: Invalid characters in input"
        return 1
    fi
    
    # Validate book exists
    if ! grep -q "^$isbn|" "$LIBRARY_FILE"; then
        echo "Error: Book with ISBN $isbn not found!"
        log_action "REQUEST_FAILED: Invalid ISBN $isbn by $student_id"
        return 1
    fi

    # Check for duplicate request (more precise pattern)
    if grep -q "|$student_id|$isbn|" "$REQUEST_FILE"; then
        echo "Error: Student $student_id already requested book $isbn!"
        log_action "REQUEST_FAILED: Duplicate request by $student_id for $isbn"
        return 1
    fi
    
    # Processing type menu
    echo -e "\nSelect processing type:"
    echo "1. FIFO (First-In-First-Out)"
    echo "2. Priority (Higher priority first)"
    read -p "Choose [1-2]: " processing_type
    
    case "$processing_type" in
        1) priority=0 ;;
        2)
            read -p "Enter priority (1-10): " priority
            if ! [[ "$priority" =~ ^[0-9]+$ ]] || (( priority < 1 || priority > 10 )); then
                echo "Invalid priority! Using default 5."
                priority=5
                log_action "REQUEST: Invalid priority input, using default 5"
            fi
            ;;
        *)
            echo "Invalid choice! Using FIFO."
            priority=0
            ;;
    esac
    
    timestamp=$(date +%s)
    echo "$timestamp|$student_id|$isbn|$priority" >> "$REQUEST_FILE"
    echo "Request submitted successfully!"
    log_action "REQUEST: $student_id|$isbn|$priority"
}

view_requests() {
    if [ ! -s "$REQUEST_FILE" ]; then
        echo -e "\nNo pending requests!"
        return
    fi
    
    echo -e "\nPending Requests (Oldest First):"
    printf "%-12s %-12s %-15s %-10s\n" "Time" "Student" "ISBN" "Priority"
    printf "%-12s %-12s %-15s %-10s\n" "----" "-------" "----" "--------"
    
    while IFS='|' read -r ts student isbn pri; do
        if [ -n "$ts" ] && [ -n "$student" ] && [ -n "$isbn" ] && [ -n "$pri" ]; then
            # Convert timestamp to readable time (POSIX compliant)
            time_str=$(date -d "@$ts" '+%H:%M:%S' 2>/dev/null || date -r "$ts" '+%H:%M:%S' 2>/dev/null || echo "$ts")
            printf "%-12s %-12s %-15s %-10s\n" "$time_str" "$student" "$isbn" "$pri"
        fi
    done < "$REQUEST_FILE"
}

process_fifo() {
    if [ ! -s "$REQUEST_FILE" ]; then
        echo "No requests to process!"
        return
    fi
    
    # Read first request
    IFS='|' read -r ts student_id isbn priority < "$REQUEST_FILE"
    
    if [ -z "$student_id" ] || [ -z "$isbn" ]; then
        echo "Error: Invalid request format!"
        log_action "PROCESS_FIFO_FAILED: Invalid format"
        return 1
    fi
    
    echo "Processing FIFO request for Student $student_id (Book ISBN: $isbn)"
    
    # Safely remove first line
    temp_file=$(mktemp) || {
        echo "Error: Cannot create temporary file!"
        return 1
    }
    
    if tail -n +2 "$REQUEST_FILE" > "$temp_file" && mv "$temp_file" "$REQUEST_FILE"; then
        echo "Request processed successfully!"
        log_action "PROCESSED_FIFO: $student_id|$isbn"
    else
        echo "Error: Failed to process request!"
        rm -f "$temp_file"
        log_action "PROCESS_FIFO_FAILED: File operation error"
        return 1
    fi
}

process_priority() {
    if [ ! -s "$REQUEST_FILE" ]; then
        echo "No requests to process!"
        return
    fi
    
    temp_file=$(mktemp) || {
        echo "Error: Cannot create temporary file!"
        return 1
    }
    
    # Sort by priority (descending) then by timestamp (ascending)
    if ! sort -t'|' -k4nr -k1n "$REQUEST_FILE" > "$temp_file"; then
        echo "Error: Failed to sort requests!"
        rm -f "$temp_file"
        log_action "PROCESS_PRIORITY_FAILED: Sort error"
        return 1
    fi
    
    # Read highest priority request
    IFS='|' read -r ts student_id isbn priority < "$temp_file"
    
    if [ -z "$student_id" ] || [ -z "$isbn" ]; then
        echo "Error: Invalid request format!"
        rm -f "$temp_file"
        log_action "PROCESS_PRIORITY_FAILED: Invalid format"
        return 1
    fi
    
    echo "Processing priority request for Student $student_id (Priority: $priority, Book ISBN: $isbn)"
    
    # Remove processed request and update file
    if tail -n +2 "$temp_file" > "$REQUEST_FILE"; then
        echo "Request processed successfully!"
        log_action "PROCESSED_PRIORITY: $student_id|$isbn|$priority"
    else
        echo "Error: Failed to update request file!"
        log_action "PROCESS_PRIORITY_FAILED: File update error"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
}

exit_system() {
    read -p "Are you sure you want to exit? (Y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Goodbye!"
        log_action "SYSTEM_EXIT"
        exit 0
    fi
}

# Main menu loop
while true; do
    echo -e "\nLibrary Queue Management System"
    echo "1. View Books"
    echo "2. Add Book"
    echo "3. Request Book"
    echo "4. View Pending Requests"
    echo "5. Process FIFO"
    echo "6. Process Priority"
    echo "7. Exit"
    
    read -p "Choose [1-7]: " choice
    case $choice in
        1) view_books ;;
        2) add_book ;;
        3) request_book ;;
        4) view_requests ;;
        5) process_fifo ;;
        6) process_priority ;;
        7) exit_system ;;
        *) echo "Invalid choice! Please select 1-7." ;;
    esac
done
