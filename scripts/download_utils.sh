#!/bin/bash

# Notepad++ Download Utility Script
# This script provides robust download and extraction functions
# for the Jenkins pipeline monitoring system

set -euo pipefail

# Configuration
DOWNLOAD_TIMEOUT=900
CONNECT_TIMEOUT=60
RETRY_ATTEMPTS=3
RETRY_DELAY=10
MIN_FILE_SIZE=1048576  # 1MB minimum expected size

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Function to download file with robust error handling
download_notepad() {
    local url="$1"
    local output_file="$2"
    local attempt=0
    
    log "Starting download from: $url"
    log "Output file: $output_file"
    
    while [ $attempt -lt $RETRY_ATTEMPTS ]; do
        attempt=$((attempt + 1))
        log "Download attempt $attempt of $RETRY_ATTEMPTS"
        
        # Remove partial download if it exists
        [ -f "$output_file" ] && rm -f "$output_file"
        
        if curl -L \
            --max-time "$DOWNLOAD_TIMEOUT" \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --retry 2 \
            --retry-delay "$RETRY_DELAY" \
            --retry-max-time 600 \
            --fail \
            --silent \
            --show-error \
            --location \
            --user-agent "Jenkins-Pipeline-Monitor/1.0" \
            -o "$output_file" \
            "$url"; then
            
            log "Download completed successfully on attempt $attempt"
            return 0
        else
            log "Download attempt $attempt failed"
            [ -f "$output_file" ] && rm -f "$output_file"
            
            if [ $attempt -lt $RETRY_ATTEMPTS ]; then
                log "Waiting $RETRY_DELAY seconds before retry..."
                sleep "$RETRY_DELAY"
            fi
        fi
    done
    
    log "ERROR: All download attempts failed"
    return 1
}

# Function to validate downloaded file
validate_download() {
    local file_path="$1"
    
    log "Validating downloaded file: $file_path"
    
    if [ ! -f "$file_path" ]; then
        log "ERROR: Downloaded file does not exist"
        return 1
    fi
    
    local file_size
    file_size=$(wc -c < "$file_path")
    
    if [ "$file_size" -lt $MIN_FILE_SIZE ]; then
        log "ERROR: Downloaded file too small ($file_size bytes, expected at least $MIN_FILE_SIZE bytes)"
        return 1
    fi
    
    # Check if it's a valid ZIP file
    if ! file "$file_path" | grep -q "Zip archive data"; then
        log "ERROR: Downloaded file is not a valid ZIP archive"
        return 1
    fi
    
    log "File validation passed - size: $file_size bytes"
    return 0
}

# Function to extract ZIP file safely
extract_archive() {
    local zip_file="$1"
    local extract_dir="$2"
    
    log "Extracting archive: $zip_file"
    log "Destination: $extract_dir"
    
    # Create extraction directory if it doesn't exist
    mkdir -p "$extract_dir"
    
    # Change to extraction directory
    cd "$extract_dir"
    
    # Extract with error handling
    if unzip -q "$zip_file"; then
        log "Archive extracted successfully"
        
        # List extracted contents for verification
        local file_count
        file_count=$(find "$extract_dir" -type f | wc -l)
        log "Extracted $file_count files"
        
        return 0
    else
        log "ERROR: Failed to extract archive"
        return 1
    fi
}

# Function to perform complete download and extraction
download_and_extract() {
    local url="$1"
    local temp_file="$2"
    local extract_dir="$3"
    
    log "Starting complete download and extraction process"
    
    # Download the file
    if ! download_notepad "$url" "$temp_file"; then
        log "Download phase failed"
        return 1
    fi
    
    # Validate the download
    if ! validate_download "$temp_file"; then
        log "Validation phase failed"
        return 1
    fi
    
    # Extract the archive
    if ! extract_archive "$temp_file" "$extract_dir"; then
        log "Extraction phase failed"
        return 1
    fi
    
    log "Download and extraction completed successfully"
    return 0
}

# Function to get file hash for comparison
get_file_hash() {
    local file_path="$1"
    
    if [ -f "$file_path" ]; then
        # Use SHA256 if available, fallback to MD5
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$file_path" | cut -d' ' -f1
        elif command -v shasum >/dev/null 2>&1; then
            shasum -a 256 "$file_path" | cut -d' ' -f1
        elif command -v md5sum >/dev/null 2>&1; then
            md5sum "$file_path" | cut -d' ' -f1
        elif command -v md5 >/dev/null 2>&1; then
            md5 -q "$file_path"
        else
            log "WARNING: No hash utility available"
            echo "NO_HASH_AVAILABLE"
        fi
    else
        echo "FILE_NOT_FOUND"
    fi
}

# Function to cleanup temporary files
cleanup_temp_files() {
    local temp_dir="$1"
    
    if [ -d "$temp_dir" ]; then
        log "Cleaning up temporary directory: $temp_dir"
        rm -rf "$temp_dir"
        log "Cleanup completed"
    fi
}

# Main execution if script is run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -lt 3 ]; then
        echo "Usage: $0 <url> <temp_file> <extract_dir> [cleanup_dir]"
        echo "Example: $0 'https://example.com/file.zip' '/tmp/download.zip' '/tmp/extract'"
        exit 1
    fi
    
    URL="$1"
    TEMP_FILE="$2"
    EXTRACT_DIR="$3"
    CLEANUP_DIR="${4:-}"
    
    # Perform download and extraction
    if download_and_extract "$URL" "$TEMP_FILE" "$EXTRACT_DIR"; then
        log "Process completed successfully"
        
        # Optional cleanup
        if [ -n "$CLEANUP_DIR" ]; then
            cleanup_temp_files "$CLEANUP_DIR"
        fi
        
        exit 0
    else
        log "Process failed"
        exit 1
    fi
fi