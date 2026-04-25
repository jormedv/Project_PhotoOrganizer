#!/bin/bash

################################################################################
# Script: download_and_organize.sh
# Purpose: Run the download_album_all_1.py downloader and then invoke organize_album_1.sh
# Author: Jorge
################################################################################

  # --- Load the Project Config ---
  set -a; . ./.env.photoorganizer; set +a
    

# --- Default Configuration ---
DEBUG_MODE=false
SKIP_DOWNLOAD=false
EXEC_ID=$(date '+%Y%m%d%H%M%S')
DATA_DIR="${DATA_DIR:-$HOME/data/Project_PhotoOrganizer}"
LOG_DIR="${LOG_DIR:-$HOME/logs/Project_PhotoOrganizer}"
CODE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="download_and_organize_$EXEC_ID.log"

# --- Utility Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] $1"
}

log_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [DEBUG] $1"
    fi
}

show_usage() {
    echo "================================================================"
    echo "  Download + Organize Photos Script - By Jorge"
    echo "================================================================"
    echo "Usage: $0 [-d yes|no] [-s] [-h] [--] [organize_album_1.sh args]"
    echo ""
    echo "Options:"
    echo "  -d [yes|no] : Enable/Disable debug mode. Default: no."
    echo "  -s          : Skip download step and only run organizer."
    echo "  -h          : Display this help message."
    echo ""
    echo "Any additional arguments after '--' (or any unrecognized args)"
    echo "are forwarded to organize_album_1.sh (e.g. -u)."
    echo "================================================================"
    exit 0
}

# --- Argument Parsing ---
ORGANIZE_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d)
            if [ "$2" = "yes" ]; then
                DEBUG_MODE=true
            else
                DEBUG_MODE=false
            fi
            shift 2
            ;;
        -s|--skip-download)
            SKIP_DOWNLOAD=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        --)
            shift
            ORGANIZE_ARGS+=("$@")
            break
            ;;
        *)
            ORGANIZE_ARGS+=("$1")
            shift
            ;;
    esac
done

# --- Global Logging ---
mkdir -p "$DATA_DIR" "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/$LOG_FILE") 2>&1

# --- Main Execution ---
log_info "Starting download + organize workflow..."
cd "$CODE_DIR" || { echo "CRITICAL: Cannot access $CODE_DIR"; exit 1; }

if [ "$SKIP_DOWNLOAD" = true ]; then
    log_info "Skipping download step (per -s/--skip-download)."
else
    log_info "Running downloader: download_album_all_1.py"

    if [ -f "$DATA_DIR/album.zip" ]; then
        echo "$DATA_DIR/album.zip exists. Deleting now..."
        rm -f "$DATA_DIR/album.zip"
    fi

    source .venv/bin/activate
    python3 download_album_all_1.py 
    if [ $? -ne 0 ]; then
        log_info "Download script failed. Aborting."
        exit 1
    fi
fi

log_info "Running organizer: organize_album_1.sh ${ORGANIZE_ARGS[*]}"
if [ ! -x "./organize_album_1.sh" ]; then
    log_info "Organizer script not found or not executable: ./organize_album_1.sh"
    exit 1
fi
./organize_album_1.sh "${ORGANIZE_ARGS[@]}"
if [ $? -ne 0 ]; then
    log_info "Organizer script failed. Aborting."
    exit 1
fi

# Verify the expected output archive exists before attempting upload.
ZIP_PATH="$DATA_DIR/organized_album.zip"
if [ ! -f "$ZIP_PATH" ]; then
    log_info "Expected output archive not found: $ZIP_PATH"
    log_info "Aborting upload step."
    exit 1
fi

log_info "Running upload_to_drive: upload_to_drive_1.sh -d yes -f $ZIP_PATH"
if [ ! -x "./upload_to_drive.sh" ]; then
    log_info "Upload script not found or not executable: ./upload_to_drive.sh"
    exit 1
fi
./upload_to_drive.sh -d yes -f "$ZIP_PATH"
if [ $? -ne 0 ]; then
    log_info "Upload script failed. Aborting."
    exit 1
fi

log_info "Workflow complete."
log_info "Log file: $LOG_FILE"
