#!/bin/bash

################################################################################
# Script: upload_to_drive.sh
# Purpose: Upload a file or folder to Google Drive using rclone.
# Author: Jorge
################################################################################

# --- Load the Project Config ---
set -a; . ./.env.photoorganizer; set +a

# --- Default Configuration ---
DEBUG_MODE=false
EXEC_ID=$(date '+%Y%m%d%H%M%S')
LOG_DIR="${LOG_DIR:-$HOME/log/Project_PhotoOrganizer}"
LOG_FILE="$LOG_DIR/upload_to_drive_$EXEC_ID.log"
REMOTE_FOLDER="SHARED_WITH_JORGE"

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
    awk "BEGIN {printf \"%.1f\", $1 / (1024*1024)}"
}

show_usage() {
    echo "================================================================"
    echo "  Google Drive Upload Script - By Jorge"
    echo "================================================================"
    echo "Usage: $0 [-d yes|no] -f <file|folder> [-p <drive_folder>] [-h]"
    echo ""
    echo "Options:"
    echo "  -d [yes|no]       : Enable/Disable debug mode. Default: no."
    echo "  -f <file|folder>  : File or folder to upload. (required)"
    echo "  -p <drive_folder> : Destination folder name on Drive."
    echo "                      Default: SHARED_WITH_JORGE"
    echo "  -h                : Display this help message."
    echo ""
    echo "Requirements:"
    echo "  rclone configured with a 'gdrive' remote (run: rclone config)"
    echo "================================================================"
    exit 0
}

# --- Argument Parsing ---
FILE_TO_UPLOAD=""
while getopts "d:f:p:h" opt; do
    case "$opt" in
        d) [ "$OPTARG" = "yes" ] && DEBUG_MODE=true || DEBUG_MODE=false ;;
        f) FILE_TO_UPLOAD="$OPTARG" ;;
        p) REMOTE_FOLDER="$OPTARG" ;;
        h) show_usage ;;
        *) show_usage ;;
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

if ! command -v rclone >/dev/null 2>&1; then
    echo "ERROR: 'rclone' not found. Install it and run: rclone config"
    exit 1
fi

# --- Global Logging ---
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Main Execution ---
if [ -d "$FILE_TO_UPLOAD" ]; then
    total_bytes=$(find "$FILE_TO_UPLOAD" -type f -printf '%s\n' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    file_count=$(find "$FILE_TO_UPLOAD" -type f 2>/dev/null | wc -l | xargs)
else
    total_bytes=$(stat -c%s "$FILE_TO_UPLOAD" 2>/dev/null || echo 0)
    file_count=1
fi

log_info "Uploading $file_count files ($(size_mb "$total_bytes")MB) → gdrive:$REMOTE_FOLDER"

if rclone copy --stats-one-line --stats 2s "$FILE_TO_UPLOAD" "gdrive:$REMOTE_FOLDER"; then
    log_info "Upload succeeded. Log: $LOG_FILE"
else
    log_info "Upload failed."
    exit 1
fi
