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
    LOG_DIR="${LOG_DIR:-$HOME/log/Project_PhotoOrganizer}/organize_$EXEC_ID"
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

    log_info "--- Pre-processing Summary ---"
    log_info "Mode: $( [ "$UNZIP_ONLY_MODE" = true ] && echo "UNZIP ONLY" || echo "FULL" )"
    log_info "Debug: $( [ "$DEBUG_MODE" = true ] && echo "YES" || echo "NO" )"
    log_info "Zips found: ${#LIST_OF_ZIPS[@]}"
    
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
        log_info "  - $item ($zip_count files, ${zip_mb}MB)"
    done

    # Store expected file count for later verification.
    EXPECTED_TOTAL_FILES=$expected_total

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
            log_info "Consolidating small date folder '$d_folder' (total files=$total_count) into individual/"

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
    log_info "Cleaning up empty directories..."
    find "$OUT_DIR" -depth -type d -empty -delete

    # Remove the live-photo mp4 folder once done (it is a temporary staging area).
    if [ -d "$OUT_DIR/mp4_live_videos" ]; then
        log_info "Removing mp4_live_videos folder: $OUT_DIR/mp4_live_videos"
        rm -rf "$OUT_DIR/mp4_live_videos"
    fi
}
run_zip_output() {
    local zip_path="$DATA_DIR/organized_album.zip"

    # Count the total number of files we are about to archive.
    local file_count
    file_count=$(find "$OUT_DIR" -type f 2>/dev/null | wc -l | xargs)
    log_info "  [Zip] Will archive $file_count files from $OUT_DIR"

    if [ -f "$zip_path" ]; then
        log_info "Removing existing archive: $zip_path"
        rm -f "$zip_path"
    fi

    log_info "Creating zip archive: $zip_path"
    (cd "$OUT_DIR" && zip -rq "$zip_path" .)

    if [ -f "$zip_path" ]; then
        local zip_bytes
        zip_bytes=$(stat -c%s "$zip_path" 2>/dev/null || echo 0)
        local zip_mb
        zip_mb=$(size_mb "$zip_bytes")
        log_info "  [Zip] Created $zip_path (Size: ${zip_mb}MB)"
    else
        log_info "  [Zip] Failed to create $zip_path"
    fi
}
run_post_summary() {
    log_info ""
    log_info "--- Final Organization Summary ---"

    local grand_photos=0
    local grand_videos=0
    local grand_unknown=0
    local grand_size=0

    # Report mp4 live videos (stored at top level)
    if [ -d "$OUT_DIR/mp4_live_videos" ]; then
        local live_c
        local live_bytes
        live_c=$(find "$OUT_DIR/mp4_live_videos" -type f 2>/dev/null | wc -l | xargs)
        live_bytes=$(find "$OUT_DIR/mp4_live_videos" -type f -printf '%s\n' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
        local live_mb
        live_mb=$(size_mb "$live_bytes")
        log_info "  [mp4_live_videos] Total: $live_c (Size: ${live_mb}MB)"

        grand_videos=$((grand_videos + live_c))
        grand_size=$((grand_size + live_bytes))
    fi

    # Report consolidated "individual" bucket (small date folders)
    if [ -d "$OUT_DIR/individual" ]; then
        local ind_p
        local ind_v
        local ind_u
        local ind_bytes

        ind_v=$(find "$OUT_DIR/individual/videos" -type f 2>/dev/null | wc -l | xargs)
        ind_u=$(find "$OUT_DIR/individual/unknown" -type f 2>/dev/null | wc -l | xargs)
        local ind_total_root
        ind_total_root=$(find "$OUT_DIR/individual" -maxdepth 1 -type f 2>/dev/null | wc -l | xargs)
        # Files in the root of individual/ are treated as photos.
        ind_p=$ind_total_root

        ind_bytes=$(find "$OUT_DIR/individual" -type f -printf '%s\n' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
        local ind_mb
        ind_mb=$(size_mb "$ind_bytes")

        local ind_total=$((ind_p + ind_v + ind_u))
        log_info "  [individual] Total: $ind_total (Photos: $ind_p, Videos: $ind_v, Unknown: $ind_u) (Size: ${ind_mb}MB)"

        grand_photos=$((grand_photos + ind_p))
        grand_videos=$((grand_videos + ind_v))
        grand_unknown=$((grand_unknown + ind_u))
        grand_size=$((grand_size + ind_bytes))
    fi

    # Report per-date folders (skip special folders)
    for d_folder in $(ls "$OUT_DIR" | sort); do
        if [ "$d_folder" = "mp4_live_videos" ] || [ "$d_folder" = "individual" ]; then
            continue
        fi

        if [ -d "$OUT_DIR/$d_folder" ]; then
            # Photos are stored directly in the date folder (not in a "photos" subfolder).
            local v_c
            local u_c
            local total_c
            local p_c

            v_c=$(find "$OUT_DIR/$d_folder/videos" -type f 2>/dev/null | wc -l | xargs)
            u_c=$(find "$OUT_DIR/$d_folder/unknown" -type f 2>/dev/null | wc -l | xargs)
            # Photos for a date folder are stored at the top level within that folder.
            p_c=$(find "$OUT_DIR/$d_folder" -maxdepth 1 -type f 2>/dev/null | wc -l | xargs)

            local folder_bytes
            folder_bytes=$(find "$OUT_DIR/$d_folder" -type f -printf '%s\n' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
            local folder_mb
            folder_mb=$(size_mb "$folder_bytes")

            local s_t=$((p_c + v_c + u_c))
            log_info "  [$d_folder] Total: $s_t (Photos: $p_c, Videos: $v_c, Unknown: $u_c) (Size: ${folder_mb}MB)"

            grand_photos=$((grand_photos + p_c))
            grand_videos=$((grand_videos + v_c))
            grand_unknown=$((grand_unknown + u_c))
            grand_size=$((grand_size + folder_bytes))
        fi
    done

    local grand_total=$((grand_photos + grand_videos + grand_unknown))
    local grand_mb
    grand_mb=$(size_mb "$grand_size")

    log_info "  [Totals] Photos: $grand_photos, Videos: $grand_videos, Unknown: $grand_unknown"
    log_info "  [Verification] Expected from ZIP: ${EXPECTED_TOTAL_FILES:-unknown} files"

    if [ -n "${EXPECTED_TOTAL_FILES:-}" ]; then
        if [ "$grand_total" -eq "${EXPECTED_TOTAL_FILES}" ]; then
            log_info "  [Verification] Match ✅"
        else
            local diff
            diff=$((grand_total - EXPECTED_TOTAL_FILES))
            log_info "  [Verification] Mismatch (difference: $diff files)"

            # Perform a filename-based cross-check to help locate missing files.
            if [ -f "$EXPECTED_FILE_LIST" ]; then
                local actual_file_list="$LOG_DIR/actual_file_list.txt"
                : > "$actual_file_list"

                # List all organized files (including mp4_live_videos if present)
                find "$OUT_DIR" -type f -printf '%f\n' >> "$actual_file_list"
                if [ -d "$OUT_DIR/mp4_live_videos" ]; then
                    find "$OUT_DIR/mp4_live_videos" -type f -printf '%f\n' >> "$actual_file_list"
                fi

                # Build count tables (basename -> count) for expected vs actual.
                local expected_counts="$LOG_DIR/expected_counts.txt"
                awk '{cnt[$0]++} END {for (f in cnt) print f, cnt[f]}' "$EXPECTED_FILE_LIST" | sort > "$expected_counts"

                local actual_counts="$LOG_DIR/actual_counts.txt"
                awk '{cnt[$0]++} END {for (f in cnt) print f, cnt[f]}' "$actual_file_list" | sort > "$actual_counts"

                local missing_list="$LOG_DIR/missing_files.txt"
                local extra_list="$LOG_DIR/extra_files.txt"

                # Ensure the output files exist before writing to them.
                : > "$missing_list"
                : > "$extra_list"

                python3 - "$expected_counts" "$actual_counts" "$missing_list" "$extra_list" <<'PY'
import sys
from pathlib import Path

expected_counts = Path(sys.argv[1])
actual_counts = Path(sys.argv[2])
missing = Path(sys.argv[3])
extra = Path(sys.argv[4])

exp = {}
for line in expected_counts.read_text().splitlines():
    if not line.strip():
        continue
    name, count = line.rsplit(None, 1)
    exp[name] = exp.get(name, 0) + int(count)

act = {}
for line in actual_counts.read_text().splitlines():
    if not line.strip():
        continue
    name, count = line.rsplit(None, 1)
    act[name] = act.get(name, 0) + int(count)

with missing.open('w') as mf, extra.open('w') as ef:
    all_names = sorted(set(exp) | set(act))
    for name in all_names:
        de = exp.get(name, 0)
        da = act.get(name, 0)
        if de > da:
            mf.write(f"{name} {de-da}\n")
        elif da > de:
            ef.write(f"{name} {da-de}\n")
PY

                local missing_count
                missing_count=$(wc -l < "$missing_list" | xargs)
                if [ "$missing_count" -gt 0 ]; then
                    log_info "  [Verification] Missing files (basename + missing count): $missing_count (showing up to 10):"
                    head -n 10 "$missing_list" | sed 's/^/    - /'
                fi

                local extra_count
                extra_count=$(wc -l < "$extra_list" | xargs)
                if [ "$extra_count" -gt 0 ]; then
                    log_info "  [Verification] Extra files organized (basename + extra count): $extra_count (showing up to 10):"
                    head -n 10 "$extra_list" | sed 's/^/    - /'
                fi
            fi
        fi
    fi

    log_info "------------------------------"
    log_info "GRAND TOTAL: $grand_total files organized (Size: ${grand_mb}MB)."
}

# --- Main Execution ---

log_info "Initiating Photo Manager..."
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

log_info "Process Finished."
log_info "Log: $LOG_FILE"
log_info "Tmp: $DATA_DIR/tmp_$EXEC_ID"
log_info "Output Folder: $DATA_DIR/organize_album_$EXEC_ID"
log_info "Output Zip: $DATA_DIR/organized_album.zip"
# End of script
