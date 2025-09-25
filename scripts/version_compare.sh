#!/bin/bash

# Version Comparison Utility Script
# Provides comprehensive comparison functionality between Notepad++ versions
# Used by the Jenkins pipeline for change detection

set -euo pipefail

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Function to generate detailed directory comparison report
compare_directories() {
    local previous_dir="$1"
    local current_dir="$2"
    local output_log="$3"
    
    log "Starting directory comparison"
    log "Previous: $previous_dir"
    log "Current: $current_dir"
    log "Output: $output_log"
    
    # Initialize the comparison report
    cat > "$output_log" << EOF
Notepad++ Version Comparison Report
Generated: $(date)
Previous version: $previous_dir
Current version: $current_dir

EOF
    
    # Check if previous directory exists and has content
    if [ ! -d "$previous_dir" ] || [ -z "$(ls -A "$previous_dir" 2>/dev/null)" ]; then
        cat >> "$output_log" << EOF
=== First Time Setup ===
No previous version found for comparison.
This appears to be the initial execution of the monitoring system.

Current version file inventory:
EOF
        if [ -d "$current_dir" ] && [ -n "$(ls -A "$current_dir" 2>/dev/null)" ]; then
            find "$current_dir" -type f | sort >> "$output_log"
        else
            echo "ERROR: Current directory is also empty or missing" >> "$output_log"
            return 1
        fi
        echo "FIRST_RUN"
        return 0
    fi
    
    # Check if current directory exists and has content
    if [ ! -d "$current_dir" ] || [ -z "$(ls -A "$current_dir" 2>/dev/null)" ]; then
        echo "ERROR: Current directory is empty or missing" >> "$output_log"
        return 1
    fi
    
    # Generate file count comparison
    local prev_count curr_count
    prev_count=$(find "$previous_dir" -type f | wc -l)
    curr_count=$(find "$current_dir" -type f | wc -l)
    
    cat >> "$output_log" << EOF
=== File Count Analysis ===
Previous version files: $prev_count
Current version files: $curr_count
Difference: $((curr_count - prev_count))

EOF
    
    # Generate size comparison
    local prev_size curr_size
    if command -v du >/dev/null 2>&1; then
        prev_size=$(du -sb "$previous_dir" 2>/dev/null | cut -f1 || echo "0")
        curr_size=$(du -sb "$current_dir" 2>/dev/null | cut -f1 || echo "0")
        
        cat >> "$output_log" << EOF
=== Directory Size Analysis ===
Previous version size: $prev_size bytes
Current version size: $curr_size bytes
Size difference: $((curr_size - prev_size)) bytes

EOF
    fi
    
    # Perform detailed file comparison
    echo "=== Detailed File Comparison ===" >> "$output_log"
    
    # Run diff and capture the result
    set +e
    diff -r "$previous_dir" "$current_dir" >> "$output_log" 2>&1
    local diff_result=$?
    set -e
    
    # Analyze diff result
    cat >> "$output_log" << EOF

=== Comparison Summary ===
Diff command exit code: $diff_result
EOF
    
    case $diff_result in
        0)
            echo "Result: No differences found between versions" >> "$output_log"
            echo "The current version appears to be identical to the previous version." >> "$output_log"
            echo "NO_CHANGES"
            ;;
        1)
            echo "Result: Differences detected between versions" >> "$output_log"
            echo "The current version contains changes compared to the previous version." >> "$output_log"
            echo "CHANGES_DETECTED"
            ;;
        *)
            echo "Result: Comparison encountered errors (exit code: $diff_result)" >> "$output_log"
            echo "There may have been issues during the comparison process." >> "$output_log"
            echo "COMPARISON_ERROR"
            ;;
    esac
    
    return 0
}

# Function to generate hash-based comparison
compare_by_hash() {
    local previous_dir="$1"
    local current_dir="$2"
    local output_log="$3"
    
    log "Performing hash-based comparison"
    
    echo "" >> "$output_log"
    echo "=== Hash-Based Comparison ===" >> "$output_log"
    
    local temp_prev_hashes temp_curr_hashes
    temp_prev_hashes=$(mktemp)
    temp_curr_hashes=$(mktemp)
    
    # Generate hash lists
    if [ -d "$previous_dir" ] && [ -n "$(ls -A "$previous_dir" 2>/dev/null)" ]; then
        find "$previous_dir" -type f -exec sha256sum {} \; 2>/dev/null | \
            sed "s|$previous_dir/||g" | sort > "$temp_prev_hashes" || {
            # Fallback to md5 if sha256sum not available
            find "$previous_dir" -type f -exec md5sum {} \; 2>/dev/null | \
                sed "s|$previous_dir/||g" | sort > "$temp_prev_hashes" || {
                echo "WARNING: Could not generate hashes for previous version" >> "$output_log"
                rm -f "$temp_prev_hashes" "$temp_curr_hashes"
                return 1
            }
        }
    else
        touch "$temp_prev_hashes"
    fi
    
    if [ -d "$current_dir" ] && [ -n "$(ls -A "$current_dir" 2>/dev/null)" ]; then
        find "$current_dir" -type f -exec sha256sum {} \; 2>/dev/null | \
            sed "s|$current_dir/||g" | sort > "$temp_curr_hashes" || {
            # Fallback to md5 if sha256sum not available
            find "$current_dir" -type f -exec md5sum {} \; 2>/dev/null | \
                sed "s|$current_dir/||g" | sort > "$temp_curr_hashes" || {
                echo "WARNING: Could not generate hashes for current version" >> "$output_log"
                rm -f "$temp_prev_hashes" "$temp_curr_hashes"
                return 1
            }
        }
    else
        touch "$temp_curr_hashes"
    fi
    
    # Compare hash files
    if diff -q "$temp_prev_hashes" "$temp_curr_hashes" >/dev/null 2>&1; then
        echo "Hash comparison result: Files are identical" >> "$output_log"
        local hash_result="IDENTICAL"
    else
        echo "Hash comparison result: Files have changed" >> "$output_log"
        echo "" >> "$output_log"
        echo "Changed files:" >> "$output_log"
        diff "$temp_prev_hashes" "$temp_curr_hashes" >> "$output_log" 2>&1 || true
        local hash_result="DIFFERENT"
    fi
    
    # Cleanup temporary files
    rm -f "$temp_prev_hashes" "$temp_curr_hashes"
    
    echo "$hash_result"
}

# Function to identify specific file changes
analyze_changes() {
    local previous_dir="$1"
    local current_dir="$2"
    local output_log="$3"
    
    log "Analyzing specific file changes"
    
    echo "" >> "$output_log"
    echo "=== Change Analysis ===" >> "$output_log"
    
    # Find new files
    if [ -d "$current_dir" ]; then
        local new_files
        new_files=$(mktemp)
        
        if [ -d "$previous_dir" ] && [ -n "$(ls -A "$previous_dir" 2>/dev/null)" ]; then
            # Compare file lists to find new files
            find "$current_dir" -type f | sed "s|$current_dir/||g" | sort > "$new_files.curr"
            find "$previous_dir" -type f | sed "s|$previous_dir/||g" | sort > "$new_files.prev"
            
            # Find files that are in current but not in previous
            comm -23 "$new_files.curr" "$new_files.prev" > "$new_files"
            
            if [ -s "$new_files" ]; then
                echo "New files added:" >> "$output_log"
                cat "$new_files" >> "$output_log"
            else
                echo "No new files added" >> "$output_log"
            fi
            
            # Find files that were removed
            comm -13 "$new_files.curr" "$new_files.prev" > "$new_files.removed"
            if [ -s "$new_files.removed" ]; then
                echo "" >> "$output_log"
                echo "Files removed:" >> "$output_log"
                cat "$new_files.removed" >> "$output_log"
            else
                echo "No files removed" >> "$output_log"
            fi
            
            rm -f "$new_files.curr" "$new_files.prev" "$new_files.removed"
        else
            # First run - all files are new
            find "$current_dir" -type f | sed "s|$current_dir/||g" | sort > "$new_files"
            echo "All files are new (first run):" >> "$output_log"
            cat "$new_files" >> "$output_log"
        fi
        
        rm -f "$new_files"
    fi
}

# Main comparison function
perform_comparison() {
    local previous_dir="$1"
    local current_dir="$2"
    local output_log="$3"
    
    log "Starting comprehensive version comparison"
    
    # Perform directory comparison
    local diff_result
    diff_result=$(compare_directories "$previous_dir" "$current_dir" "$output_log")
    
    # If we have both directories, do additional analysis
    if [ "$diff_result" = "CHANGES_DETECTED" ] || [ "$diff_result" = "NO_CHANGES" ]; then
        # Perform hash comparison for additional verification
        local hash_result
        hash_result=$(compare_by_hash "$previous_dir" "$current_dir" "$output_log" || echo "HASH_ERROR")
        
        # Analyze specific changes
        analyze_changes "$previous_dir" "$current_dir" "$output_log"
        
        # Final determination
        if [ "$diff_result" = "CHANGES_DETECTED" ] || [ "$hash_result" = "DIFFERENT" ]; then
            echo "CHANGES_DETECTED"
        else
            echo "NO_CHANGES"
        fi
    else
        echo "$diff_result"
    fi
}

# Main execution when script is run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -ne 3 ]; then
        echo "Usage: $0 <previous_dir> <current_dir> <output_log>"
        echo "Example: $0 /path/to/previous /path/to/current /path/to/comparison.log"
        exit 1
    fi
    
    PREVIOUS_DIR="$1"
    CURRENT_DIR="$2"
    OUTPUT_LOG="$3"
    
    # Ensure output directory exists
    mkdir -p "$(dirname "$OUTPUT_LOG")"
    
    # Perform the comparison
    result=$(perform_comparison "$PREVIOUS_DIR" "$CURRENT_DIR" "$OUTPUT_LOG")
    
    log "Comparison completed with result: $result"
    echo "$result"
    
    # Set exit code based on result
    case "$result" in
        "NO_CHANGES")
            exit 0
            ;;
        "CHANGES_DETECTED"|"FIRST_RUN")
            exit 1
            ;;
        *)
            exit 2
            ;;
    esac
fi