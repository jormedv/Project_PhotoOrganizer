#!/bin/bash

################################################################################
# Script: organize_album_9.sh
# Purpose: Unzip and/or Organize Google Photo archives.
# Author: Jorge
################################################################################

# --- Default Configuration ---
DEBUG_MODE=false
UNZIP_ONLY_MODE=false
EXEC_ID=$(date '+%Y%m%d%H%M%S')
BASE_DIR="/home/jorge/DATOS/photos"
LOG_FILE="organize_album_$EXEC_ID.log"
TMP_DIR="tmp_$EXEC_ID"
OUT_DIR="organize_album_$EXEC_ID"

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
    echo "  Google Photos Organizer Script v2.1 - By Jorge"
    echo "================================================================"
    echo "Usage: $0 [-d yes|no] [-u] [-h]"
    echo ""
    echo "Options:"
    echo "  -d [yes|no] : Enable/Disable debug mode. Default: no."
    echo "  -u          : Unzip only mode. Skips organization. Default: off."
    echo "  -h          : Display this help message."
    echo "================================================================"
    exit 0
}

# --- Argument Parsing ---
while getopts "d:uh" opt; do
    case "$opt" in
        d)  if [ "$OPTARG" = "yes" ]; then DEBUG_MODE=true; else DEBUG_MODE=false; fi ;;
        u)  UNZIP_ONLY_MODE=true ;;
        h)  show_usage ;;
        *)  show_usage ;;
    esac
done

# --- Global Logging ---
# Captures everything to screen and log file
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Logic Blocks ---

run_pre_process() {
    shopt -s nullglob
    LIST_OF_ZIPS=(*.zip)

    if [ ${#LIST_OF_ZIPS[@]} -eq 0 ]; then
        log_info "No ZIP files found in $BASE_DIR. Exiting."
        exit 0
    fi

    log_info "--- Pre-processing Summary ---"
    log_info "Mode: $( [ "$UNZIP_ONLY_MODE" = true ] && echo "UNZIP ONLY" || echo "FULL" )"
    log_info "Debug: $( [ "$DEBUG_MODE" = true ] && echo "YES" || echo "NO" )"
    log_info "Zips found: ${#LIST_OF_ZIPS[@]}"
    
    for item in "${LIST_OF_ZIPS[@]}"; do
        local zip_count
        zip_count=$(zipinfo -1 "$item" | grep -v "/$" | wc -l | xargs)
        log_info "  - $item ($zip_count files)"
    done
    log_info "------------------------------"
    
    mkdir -p "$TMP_DIR"
    mkdir -p "$OUT_DIR"
}

run_unzip() {
    for zip_file in "${LIST_OF_ZIPS[@]}"; do
        local folder_name="${zip_file%.*}"
        log_info "Extracting $zip_file..."
        mkdir -p "$TMP_DIR/$folder_name"
        unzip -oq "$zip_file" -d "$TMP_DIR/$folder_name"
    done
}

run_organization() {
    log_info "Sorting files into $OUT_DIR..."
    for zip_file in "${LIST_OF_ZIPS[@]}"; do
        local folder_name="${zip_file%.*}"
        find "$TMP_DIR/$folder_name" -type f | while read -r target_file; do
            
            # Skip noise files
            if [[ "$target_file" == *.json ]] || [[ "$target_file" == *".DS_Store"* ]]; then
                continue
            fi

            # Date Detection
            local final_date=""
            final_date=$(exiftool -m -s3 -d "%Y%m%d" -DateTimeOriginal "$target_file")
            if [ -z "$final_date" ]; then
                final_date=$(exiftool -m -s3 -d "%Y%m%d" -CreateDate "$target_file")
            fi
            if [ -z "$final_date" ]; then
                final_date=$(exiftool -m -s3 -d "%Y%m%d" -FileModifyDate "$target_file")
            fi
            if [ -z "$final_date" ]; then 
                final_date="unknown_date"
            fi

            # Sorting Logic
            local ext="${target_file##*.}"
            local low_ext
            low_ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

            local sub_folder="unknown"
            case "$low_ext" in
                heic|jpg|jpeg|png|tiff|bmp) sub_folder="photos" ;;
                mov|mp4|avi|m4v|mkv|3gp)    sub_folder="videos" ;;
                *)                          sub_folder="unknown" ;;
            esac

            local final_dest="$OUT_DIR/$final_date/$sub_folder"
            mkdir -p "$final_dest"
            
            log_debug "Moving $(basename "$target_file") to $final_date/$sub_folder"
            mv "$target_file" "$final_dest/"
        done
    done
}

run_cleanup() {
    log_info "Cleaning up empty directories..."
    find "$OUT_DIR" -depth -type d -empty -delete
}

run_post_summary() {
    log_info ""
    log_info "--- Final Organization Summary ---"
    local grand_total=0
    
    for d_folder in $(ls "$OUT_DIR" | sort); do
        if [ -d "$OUT_DIR/$d_folder" ]; then
            local p_c=$(find "$OUT_DIR/$d_folder/photos" -type f 2>/dev/null | wc -l | xargs)
            local v_c=$(find "$OUT_DIR/$d_folder/videos" -type f 2>/dev/null | wc -l | xargs)
            local u_c=$(find "$OUT_DIR/$d_folder/unknown" -type f 2>/dev/null | wc -l | xargs)
            local s_t=$((p_c + v_c + u_c))
            
            log_info "  [$d_folder] Total: $s_t (Photos: $p_c, Videos: $v_c, Unknown: $u_c)"
            grand_total=$((grand_total + s_t))
        fi
    done
    log_info "------------------------------"
    log_info "GRAND TOTAL: $grand_total files organized."
}

# --- Main Execution ---

log_info "Initiating Photo Manager..."
cd "$BASE_DIR" || { echo "CRITICAL: Cannot access $BASE_DIR"; exit 1; }

run_pre_process
run_unzip

if [ "$UNZIP_ONLY_MODE" = false ]; then
    run_organization
    run_cleanup
    run_post_summary
else
    log_info "Unzip mode complete. Organization skipped per -u flag."
fi

log_info "Process Finished."
log_info "Log: $LOG_FILE"
log_info "Tmp: $BASE_DIR/tmp_$EXEC_ID"
log_info "Output: $BASE_DIR/organize_album_$EXEC_ID"
# End of script
