# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

End-to-end photo management pipeline: downloads a shared Google Photos album via browser automation, organizes photos by date using EXIF metadata, and uploads the result to Google Drive.

## Setup

```bash
# Install system dependencies (exiftool, rclone, gws, etc.)
bash requirements.apt.txt

# Install Python dependencies
source .venv/bin/activate
pip install -r requirements.txt

# Install Playwright browser
playwright install chromium
```

## Running the Pipeline

```bash
# Full pipeline (download → organize → upload)
./download_and_organize.sh

# Skip download (reuse existing album.zip)
./download_and_organize.sh -s

# Debug mode (verbose output)
./download_and_organize.sh -d yes

# Run individual components
python download_album_all_1.py
./organize_album_1.sh
./upload_to_drive.sh -f <path> -p <parent_folder_id>
```

## Architecture

### Pipeline Flow

```
download_and_organize.sh (orchestrator)
├── download_album_all_1.py → /DEV/photos/album.zip
├── organize_album_1.sh    → /DEV/photos/organized_album.zip
└── upload_to_drive.sh     → Google Drive (SHARED_WITH_JORGE folder)
```

### Configuration

`Project_PhotoOrganizer.conf` is sourced by all shell scripts and sets `BASE_DEV_FOLDER` (default: `/home/jorgemedinavallejo/DEV`). Paths for photos, logs, and code are derived from this variable.

### Key Design Decisions

**organize_album_1.sh** runs three sequential passes over files:
1. Photos (HEIC/JPG) — extracts EXIF `DateTimeOriginal`/`CreateDate`, groups into `YYYYMMDD/` folders
2. Videos (MP4) — same date extraction; live-photo videos (matched via `ContentIdentifier` EXIF tag) are segregated into `mp4_live_videos/` at root level
3. Other files — organized by date or moved to `unknown_date/`

Date folders with fewer than 5 files are consolidated into an `individual/` bucket.

**download_album_all_1.py** uses Playwright (non-headless, existing Chrome profile at `~/.config/chrome-playwright`) to navigate Google Photos and click "Download All". It disables webdriver detection and has fallback selector strategies.

**upload_to_drive.sh** uses `gws` (Google Workspace CLI) for single files and `rclone` for folder uploads.

### Logging

All scripts write timestamped logs to `$BASE_DEV_FOLDER/photos/logs/`. Use `-d yes` for verbose/debug output.

## Environment

- Designed for WSL2 (Windows Subsystem for Linux)
- Chrome user data dir hardcoded to `~/.config/chrome-playwright`
- Download destination hardcoded to `~/DEV/photos` in the Python script
