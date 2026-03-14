#!/bin/bash

################################################################################
# Script: download_and_organize.sh
# Purpose: Run the download_album_all_1.py downloader and then invoke organize_album_1.sh
# Author: Jorge
################################################################################

# --- Default Configuration ---
DEBUG_MODE=false
EXEC_ID=$(date '+%Y%m%d%H%M%S')
BASE_DIR="/home/jorge/DATOS/Project_PhotoOrganizer"
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
    echo "Usage: $0 [-d yes|no] [-h] [--] [organize_album_1.sh args]"
    echo ""
    echo "Options:"
    echo "  -d [yes|no] : Enable/Disable debug mode. Default: no."
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
# Captures everything to screen and log file
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Main Execution ---
log_info "Starting download + organize workflow..."
cd "$BASE_DIR" || { echo "CRITICAL: Cannot access $BASE_DIR"; exit 1; }

log_info "Running downloader: download_album_all_1.py"
python3 download_album_all_1.py
if [ $? -ne 0 ]; then
    log_info "Download script failed. Aborting."
    exit 1
fi

log_info "Running organizer: organize_album_1.sh ${ORGANIZE_ARGS[*]}"
./organize_album_1.sh "${ORGANIZE_ARGS[@]}"
if [ $? -ne 0 ]; then
    log_info "Organizer script failed. Aborting."
    exit 1
fi

log_info "Workflow complete."
log_info "Log file: $LOG_FILE"
