    #!/bin/bash

    ################################################################################
    # Script: organize_album_9.sh
    # Purpose: Unzip and/or Organize Google Photo archives.
    # Author: Jorge
    ################################################################################

  
    # --- Load the Project Config ---
    set -a; . ./.env.photoorganizer; set +a

    # --- Default Configuration ---
    DEBUG_MODE=false
    UNZIP_ONLY_MODE=false
    EXEC_ID=$(date '+%Y%m%d%H%M%S')
    DATA_DIR="${DATA_DIR:-$HOME/data/Project_PhotoOrganizer}"
    LOG_DIR="${LOG_DIR:-$HOME/logs/Project_PhotoOrganizer}/organize_$EXEC_ID"
    LOG_FILE="$LOG_DIR/organize_album_$EXEC_ID.log"
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
# Ensure log directory exists (so tee can write the log file)
mkdir -p "$LOG_DIR"
# Captures everything to screen and log file
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Logic Blocks ---

size_mb() {
    # Accept bytes, print MB with 1 decimal.
    awk "BEGIN {printf \"%.1f\", $1 / (1024*1024)}"
}

run_pre_process() {
    shopt -s nullglob
    LIST_OF_ZIPS=(*.zip)

    # Ignore our own output archive if it exists in the base directory.
    local filtered_zips=()
    for z in "${LIST_OF_ZIPS[@]}"; do
        if [ "$(basename "$z")" = "organized_album.zip" ]; then
            continue
        fi
        filtered_zips+=("$z")
    done
    LIST_OF_ZIPS=("${filtered_zips[@]}")

    if [ ${#LIST_OF_ZIPS[@]} -eq 0 ]; then
        log_info "No ZIP files found in $DATA_DIR. Exiting."
        exit 0
    fi

    local expected_total=0
    # Prepare expected file list (basename only) for post-run verification.
    EXPECTED_FILE_LIST="$LOG_DIR/expected_file_list.txt"
    : > "$EXPECTED_FILE_LIST"

    for item in "${LIST_OF_ZIPS[@]}"; do
        local zip_count
        zip_count=$(zipinfo -1 "$item" | grep -v "/$" | wc -l | xargs)
        expected_total=$((expected_total + zip_count))

        # Record expected basenames for later cross-check.
        zipinfo -1 "$item" | grep -v "/$" | xargs -n1 basename >> "$EXPECTED_FILE_LIST"

        local zip_size
        zip_size=$(stat -c%s "$item" 2>/dev/null || echo 0)
        local zip_mb
        zip_mb=$(size_mb "$zip_size")
        log_info "Input: $item — $zip_count files (${zip_mb}MB)"
    done

    # Store expected file count for later verification.
    EXPECTED_TOTAL_FILES=$expected_total
    
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
    log_info "Organizing..."

    for zip_file in "${LIST_OF_ZIPS[@]}"; do
        local folder_name="${zip_file%.*}"
        # Phase 1: Process photos (heic/jpg) first and record their ContentIdentifier by base filename.
        declare -A photo_cid_by_base=()
        while IFS= read -r -d '' photo_file; do

            # Determine base name (without extension)
            local base_name
            base_name="$(basename "$photo_file")"
            base_name="${base_name%.*}"

            # Extract ContentIdentifier (may be empty)
            local cid
            cid=$(exiftool -m -s3 -ContentIdentifier "$photo_file" 2>/dev/null | tr -d '\r\n')
            if [ -n "$cid" ]; then
                photo_cid_by_base["$base_name"]="$cid"
            fi

            # Move the photo into its date folder
            local final_date
            final_date=$(exiftool -m -s3 -d "%Y%m%d" -DateTimeOriginal "$photo_file")
            if [ -z "$final_date" ]; then
                final_date=$(exiftool -m -s3 -d "%Y%m%d" -CreateDate "$photo_file")
            fi
            if [ -z "$final_date" ]; then
                final_date=$(exiftool -m -s3 -d "%Y%m%d" -FileModifyDate "$photo_file")
            fi
            if [[ "$final_date" == "0000:00:00 00:00:00" ]] || [[ "$final_date" == "00000000" ]]; then
                final_date="unknown_date"
            fi
            if [ -z "$final_date" ]; then
                final_date="unknown_date"
            fi

            local final_dest="$OUT_DIR/$final_date"
            mkdir -p "$final_dest"
            log_debug "Moving $(basename "$photo_file") to ${final_dest#$OUT_DIR/}"
            mv "$photo_file" "$final_dest/"
        done < <(find "$TMP_DIR/$folder_name" -type f \( -iname '*.heic' -o -iname '*.HEIC' -o -iname '*.jpg' -o -iname '*.JPG' -o -iname '*.jpeg' -o -iname '*.JPEG' \) -print0)

        # Phase 2: Process mp4 files and detect live-photo videos by base filename + content identifier.
        while IFS= read -r -d '' mp4_file; do
            local final_date
            final_date=$(exiftool -m -s3 -d "%Y%m%d" -DateTimeOriginal "$mp4_file")
            if [ -z "$final_date" ]; then
                final_date=$(exiftool -m -s3 -d "%Y%m%d" -CreateDate "$mp4_file")
            fi
            if [ -z "$final_date" ]; then
                final_date=$(exiftool -m -s3 -d "%Y%m%d" -FileModifyDate "$mp4_file")
            fi
            if [[ "$final_date" == "0000:00:00 00:00:00" ]] || [[ "$final_date" == "00000000" ]]; then
                final_date="unknown_date"
            fi
            if [ -z "$final_date" ]; then
                final_date="unknown_date"
            fi

            local base_name
            base_name="$(basename "$mp4_file")"
            base_name="${base_name%.*}"

            local sub_folder="videos"
            if [ -n "${photo_cid_by_base[$base_name]}" ]; then
                local mp4_cid
                mp4_cid=$(exiftool -m -s3 -ContentIdentifier "$mp4_file" 2>/dev/null | tr -d '\r\n')
                log_debug "mp4=$mp4_file ContentIdentifier='$mp4_cid' against photo base '$base_name'"
                if [ -n "$mp4_cid" ] && [ "$mp4_cid" = "${photo_cid_by_base[$base_name]}" ]; then
                    sub_folder="mp4_live_videos"
                fi
            fi

            local final_dest
            if [ "$sub_folder" = "mp4_live_videos" ]; then
                final_dest="$OUT_DIR/$sub_folder"
            else
                final_dest="$OUT_DIR/$final_date/$sub_folder"
            fi
            mkdir -p "$final_dest"
            log_debug "Moving $(basename "$mp4_file") to ${final_dest#$OUT_DIR/}"
            mv "$mp4_file" "$final_dest/"
        done < <(find "$TMP_DIR/$folder_name" -type f -iname '*.mp4' -print0)

        # Phase 3: Process remaining files (unknowns)
        while IFS= read -r -d '' other_file; do
            # Skip already-handled types
            local final_date
            final_date=$(exiftool -m -s3 -d "%Y%m%d" -DateTimeOriginal "$other_file")
            if [ -z "$final_date" ]; then
                final_date=$(exiftool -m -s3 -d "%Y%m%d" -CreateDate "$other_file")
            fi
            if [ -z "$final_date" ]; then
                final_date=$(exiftool -m -s3 -d "%Y%m%d" -FileModifyDate "$other_file")
            fi
            if [[ "$final_date" == "0000:00:00 00:00:00" ]] || [[ "$final_date" == "00000000" ]]; then
                final_date="unknown_date"
            fi
            if [ -z "$final_date" ]; then
                final_date="unknown_date"
            fi

            local final_dest="$OUT_DIR/$final_date/unknown"
            mkdir -p "$final_dest"
            log_debug "Moving $(basename "$other_file") to ${final_dest#$OUT_DIR/}"
            mv "$other_file" "$final_dest/"
        done < <(find "$TMP_DIR/$folder_name" -type f ! -iname '*.heic' ! -iname '*.HEIC' ! -iname '*.jpg' ! -iname '*.JPG' ! -iname '*.jpeg' ! -iname '*.JPEG' ! -iname '*.mp4' -print0)
    done
}

run_consolidate_small_date_folders() {
    # Move small date folders into an "individual" bucket to avoid many sparse date folders.
    local threshold=5
    local individual_dir="$OUT_DIR/individual"
    local individual_videos="$individual_dir/videos"
    local individual_unknown="$individual_dir/unknown"

    for d_folder in $(ls "$OUT_DIR" | sort); do
        # Skip special folders
        if [ "$d_folder" = "mp4_live_videos" ] || [ "$d_folder" = "individual" ]; then
            continue
        fi

        local date_dir="$OUT_DIR/$d_folder"
        if [ ! -d "$date_dir" ]; then
            continue
        fi

        # Count all files under the date folder (photos + videos + unknown)
        local total_count
        total_count=$(find "$date_dir" -type f 2>/dev/null | wc -l | xargs)

        if [ "$total_count" -lt "$threshold" ]; then
            log_debug "Consolidating small date folder '$d_folder' (total files=$total_count) into individual/"

            mkdir -p "$individual_dir" "$individual_videos" "$individual_unknown"

            # Move photos (anywhere under the date folder)
            find "$date_dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.heic' -o -iname '*.png' -o -iname '*.tiff' -o -iname '*.bmp' \) -exec mv -t "$individual_dir" -- {} +

            # Move videos (anywhere under the date folder)
            find "$date_dir" -type f \( -iname '*.mov' -o -iname '*.mp4' -o -iname '*.avi' -o -iname '*.m4v' -o -iname '*.mkv' -o -iname '*.3gp' \) -exec mv -t "$individual_videos" -- {} +

            # Move unknowns (any remaining files)
            find "$date_dir" -type f -exec mv -t "$individual_unknown" -- {} +

            # Cleanup
            find "$date_dir" -depth -type d -empty -delete
            rmdir --ignore-fail-on-non-empty "$date_dir" 2>/dev/null || true
        fi
    done
}

run_cleanup() {
    find "$OUT_DIR" -depth -type d -empty -delete
    [ -d "$OUT_DIR/mp4_live_videos" ] && rm -rf "$OUT_DIR/mp4_live_videos"
}
run_zip_output() {
    local zip_path="$DATA_DIR/organized_album.zip"

    [ -f "$zip_path" ] && rm -f "$zip_path"
    (cd "$OUT_DIR" && zip -rq "$zip_path" .)

    if [ -f "$zip_path" ]; then
        local zip_mb
        zip_mb=$(size_mb "$(stat -c%s "$zip_path" 2>/dev/null || echo 0)")
        log_info "Output: $zip_path (${zip_mb}MB)"
    else
        log_info "ERROR: Failed to create $zip_path"
    fi
}
run_post_summary() {
    local grand_photos=0
    local grand_videos=0
    local grand_unknown=0
    local grand_size=0

    # Tally mp4 live videos (top-level special folder)
    if [ -d "$OUT_DIR/mp4_live_videos" ]; then
        local live_c live_bytes
        live_c=$(find "$OUT_DIR/mp4_live_videos" -type f 2>/dev/null | wc -l | xargs)
        live_bytes=$(find "$OUT_DIR/mp4_live_videos" -type f -printf '%s\n' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
        grand_videos=$((grand_videos + live_c))
        grand_size=$((grand_size + live_bytes))
    fi

    # Tally all remaining folders (individual + per-date)
    for d_folder in $(ls "$OUT_DIR" | sort); do
        [ "$d_folder" = "mp4_live_videos" ] && continue
        [ ! -d "$OUT_DIR/$d_folder" ] && continue

        local p_c v_c u_c folder_bytes
        p_c=$(find "$OUT_DIR/$d_folder" -maxdepth 1 -type f 2>/dev/null | wc -l | xargs)
        v_c=$(find "$OUT_DIR/$d_folder/videos" -type f 2>/dev/null | wc -l | xargs)
        u_c=$(find "$OUT_DIR/$d_folder/unknown" -type f 2>/dev/null | wc -l | xargs)
        folder_bytes=$(find "$OUT_DIR/$d_folder" -type f -printf '%s\n' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')

        grand_photos=$((grand_photos + p_c))
        grand_videos=$((grand_videos + v_c))
        grand_unknown=$((grand_unknown + u_c))
        grand_size=$((grand_size + folder_bytes))
    done

    local grand_total=$((grand_photos + grand_videos + grand_unknown))
    local grand_mb
    grand_mb=$(size_mb "$grand_size")

    if [ -n "${EXPECTED_TOTAL_FILES:-}" ] && [ "$grand_total" -eq "${EXPECTED_TOTAL_FILES}" ]; then
        log_info "Result: $grand_total files — Photos: $grand_photos | Videos: $grand_videos | Unknown: $grand_unknown | Size: ${grand_mb}MB  ✅"
    else
        local diff=$((grand_total - ${EXPECTED_TOTAL_FILES:-0}))
        log_info "Result: $grand_total files — Photos: $grand_photos | Videos: $grand_videos | Unknown: $grand_unknown | Size: ${grand_mb}MB  ❌ expected ${EXPECTED_TOTAL_FILES:-?} (diff: $diff)"

        # Filename-level cross-check to surface missing/extra files
        if [ -f "$EXPECTED_FILE_LIST" ]; then
            local actual_file_list="$LOG_DIR/actual_file_list.txt"
            : > "$actual_file_list"
            find "$OUT_DIR" -type f -printf '%f\n' >> "$actual_file_list"

            local expected_counts="$LOG_DIR/expected_counts.txt"
            local actual_counts="$LOG_DIR/actual_counts.txt"
            local missing_list="$LOG_DIR/missing_files.txt"
            local extra_list="$LOG_DIR/extra_files.txt"

            awk '{cnt[$0]++} END {for (f in cnt) print f, cnt[f]}' "$EXPECTED_FILE_LIST" | sort > "$expected_counts"
            awk '{cnt[$0]++} END {for (f in cnt) print f, cnt[f]}' "$actual_file_list"   | sort > "$actual_counts"
            : > "$missing_list"; : > "$extra_list"

            python3 - "$expected_counts" "$actual_counts" "$missing_list" "$extra_list" <<'PY'
import sys
from pathlib import Path

exp = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.strip():
        name, count = line.rsplit(None, 1)
        exp[name] = exp.get(name, 0) + int(count)

act = {}
for line in Path(sys.argv[2]).read_text().splitlines():
    if line.strip():
        name, count = line.rsplit(None, 1)
        act[name] = act.get(name, 0) + int(count)

with Path(sys.argv[3]).open('w') as mf, Path(sys.argv[4]).open('w') as ef:
    for name in sorted(set(exp) | set(act)):
        de, da = exp.get(name, 0), act.get(name, 0)
        if de > da: mf.write(f"{name}\n")
        elif da > de: ef.write(f"{name}\n")
PY

            local missing_count
            missing_count=$(wc -l < "$missing_list" | xargs)
            [ "$missing_count" -gt 0 ] && \
                log_info "  Missing ($missing_count):" && head -n 10 "$missing_list" | sed 's/^/    - /'

            local extra_count
            extra_count=$(wc -l < "$extra_list" | xargs)
            [ "$extra_count" -gt 0 ] && \
                log_info "  Extra ($extra_count):" && head -n 10 "$extra_list" | sed 's/^/    - /'
        fi
    fi
}

# --- Main Execution ---

cd "$DATA_DIR" || { echo "CRITICAL: Cannot access $DATA_DIR"; exit 1; }

run_pre_process
run_unzip

if [ "$UNZIP_ONLY_MODE" = false ]; then
    run_organization
    run_consolidate_small_date_folders
    run_post_summary
    run_cleanup
    run_zip_output
else
    log_info "Unzip mode complete. Organization skipped per -u flag."
fi

log_info "Done. Log: $LOG_FILE"
# End of script
