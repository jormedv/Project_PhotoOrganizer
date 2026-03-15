#!/bin/bash

################################################################################
# Script: upload_to_drive.sh
# Purpose: Upload a file to Google Drive using the Google Workspace CLI (gw).
# Author: Jorge
################################################################################

# --- Load the Project Config ---
. ./Project_PhotoOrganizer.conf
    
# --- Default Configuration ---
DEBUG_MODE=false
EXEC_ID=$(date '+%Y%m%d%H%M%S')
BASE_DIR="$BASE_DEV_FOLDER/photos"
LOG_DIR="$BASE_DIR/log_$EXEC_ID"
LOG_FILE="$LOG_DIR/upload_to_drive_$EXEC_ID.log"

# --- Utility Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] $1"
}

log_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [DEBUG] $1"
    fi
}

size_mb() {
    # stdin or argument: bytes -> MB with one decimal
    local bytes
    if [ -n "$1" ]; then
        bytes=$1
    else
        read -r bytes
    fi
    awk "BEGIN {printf \"%.1f\", $bytes / (1024*1024)}"
}

show_usage() {
    echo "================================================================"
    echo "  Google Drive Upload Script - By Jorge"
    echo "================================================================"
    echo "Usage: $0 [-d yes|no] -f <file|folder> [-p <parent_folder>]"
    echo ""
    echo "Options:"
    echo "  -d [yes|no]          : Enable/Disable debug mode. Default: no."
    echo "  -f <file|folder>     : File or folder to upload. (required)"
    echo "  -p <parent_folder>   : Name of the Drive folder (e.g. SHARED_WITH_JORGE).
                             For files, this is treated as a folder ID." 
    echo "  -h                   : Display this help message."
    echo ""
    echo "Requirements:"
    echo "  npm install -g @googleworkspace/cli"
    echo "  sudo npm install -g @googleworkspace/cli"
    echo "  rclone (for folder uploads)"
    echo "================================================================"
    exit 0
}

# --- Argument Parsing ---
PARENT_ID=""
FILE_TO_UPLOAD=""
while getopts "d:f:p:h" opt; do
    case "$opt" in
        d)
            if [ "$OPTARG" = "yes" ]; then
                DEBUG_MODE=true
            else
                DEBUG_MODE=false
            fi
            ;;
        f)
            FILE_TO_UPLOAD="$OPTARG"
            ;;
        p)
            PARENT_ID="$OPTARG"
            ;;
        h)
            show_usage
            ;;
        *)
            show_usage
            ;;
    esac
done

if [ -z "$FILE_TO_UPLOAD" ]; then
    echo "ERROR: Missing required -f <file|folder> argument."
    show_usage
fi

if [ ! -e "$FILE_TO_UPLOAD" ]; then
    echo "ERROR: Path not found: $FILE_TO_UPLOAD"
    exit 1
fi

# --- Global Logging ---
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Main Execution ---
log_info "Starting upload_to_drive workflow..."

if [ -d "$FILE_TO_UPLOAD" ]; then
    # Folder uploads use rclone (faster & preserves structure)
    if ! command -v rclone >/dev/null 2>&1; then
        log_info "ERROR: 'rclone' command not found. Please install and configure it."
        exit 1
    fi
else
    # File uploads use gws
    if ! command -v gws >/dev/null 2>&1; then
        log_info "ERROR: 'gws' command not found. Install it with: npm install -g @googleworkspace/cli"
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        log_info "ERROR: 'jq' command not found. Install it (e.g. sudo apt install jq)."
        exit 1
    fi

    if [ -z "$PARENT_ID" ]; then
        log_info "No parent folder ID provided; locating 'SHARED_WITH_JORGE' folder..."
        PARENT_ID=$(gws drive files list --params '{"q": "mimeType='\''application/vnd.google-apps.folder'\'' and name='\''SHARED_WITH_JORGE'\''", "fields": "files(id,name)"}' | jq -r '.files[0].id')
        log_info "Resolved parent folder ID: $PARENT_ID"

        if [ -z "$PARENT_ID" ] || [ "$PARENT_ID" = "null" ]; then
            log_info "ERROR: Could not resolve SHARED_WITH_JORGE folder ID."
            exit 1
        fi
    fi
fi

# Report how much will be uploaded
if [ -d "$FILE_TO_UPLOAD" ]; then
    file_count=$(find "$FILE_TO_UPLOAD" -type f 2>/dev/null | wc -l | xargs)
    total_bytes=$(find "$FILE_TO_UPLOAD" -type f -printf '%s\n' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
else
    file_count=1
    total_bytes=$(stat -c%s "$FILE_TO_UPLOAD" 2>/dev/null || echo 0)
fi

total_mb=$(size_mb "$total_bytes")
log_info "Uploading $file_count files (total size: ${total_mb}MB)"

if [ -d "$FILE_TO_UPLOAD" ]; then
    # Folder upload via rclone using the configured gdrive remote.
    REMOTE_PATH="${PARENT_ID:-SHARED_WITH_JORGE}"
    log_info "Uploading folder with rclone to gdrive:$REMOTE_PATH"
    if rclone copy --progress "$FILE_TO_UPLOAD" "gdrive:$REMOTE_PATH"; then
        log_info "Folder upload succeeded."
    else
        log_info "Folder upload failed."
        exit 1
    fi
else
    # File upload via gws
    GWS_COMMAND=(gws drive +upload "${FILE_TO_UPLOAD}")
    if [ -n "$PARENT_ID" ]; then
        GWS_COMMAND+=(--parent "$PARENT_ID")
    fi

    log_info "Running: ${GWS_COMMAND[*]}"
    if "${GWS_COMMAND[@]}"; then
        log_info "Upload succeeded."
    else
        log_info "Upload failed."
        exit 1
    fi
fi

log_info "Log: $LOG_FILE"
