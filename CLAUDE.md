# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

End-to-end photo management pipeline: downloads a shared Google Photos album via browser automation, organizes photos by date using EXIF metadata, and uploads the result to Google Drive.

## Setup

```bash
# Install system dependencies (exiftool, rclone, gws, jq, etc.)
bash requirements.apt.txt

# Install Python dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Install Playwright browser
playwright install chromium

# Configure environment
cp .env.photoorganizer.sample .env.photoorganizer
# edit .env.photoorganizer — fill in GOOGLE_PHOTOS_ALBUM_URL at minimum

# Authenticate to Google Cloud (for GSM → Bitwarden)
gcloud auth application-default login

# Smoke-test the GSM → Bitwarden chain
cp .env.test_gsm.sample .env.test_gsm
python test_gsm_and_bw.py

# One-time: log in to Google in the dedicated Playwright Chrome profile
google-chrome --user-data-dir=/home/jorge/.config/google-chrome-playwright
# (navigate to photos.google.com and log in, then close Chrome)
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
├── download_album_all_1.py → ~/data/Project_PhotoOrganizer/album.zip
├── organize_album_1.sh    → ~/data/Project_PhotoOrganizer/organized_album.zip
└── upload_to_drive.sh     → Google Drive (SHARED_WITH_JORGE folder)
```

### Configuration

All scripts source `.env.photoorganizer` at startup. Key variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `DATA_DIR` | `~/data/Project_PhotoOrganizer` | Photos, zips, temp dirs |
| `LOG_DIR` | `~/logs/Project_PhotoOrganizer` | Log files |
| `GOOGLE_PHOTOS_ALBUM_URL` | *(required)* | Shared album to download |
| `CHROME_USER_DATA_DIR` | `~/.config/google-chrome-playwright` | Playwright Chrome profile |
| `GCP_PROJECT` | `jmv-linux-gcloud` | GCP project for GSM |
| `GSM_SECRET` | `JMV-BW` | Secret name in GSM holding BW master password |

### Credential Flow

Secrets are never stored on disk. The chain at runtime:

```
Google Secret Manager (GSM)
    ↓  gcloud ADC (local) or Workload Identity (GCP VM)
Bitwarden master password  (in-memory)
    ↓  bw unlock
Session token  (in-memory)
    ↓  bw list items
Vault cache  (in-memory, indexed by name)
    ↓  get_credential(key)
Individual secrets
```

### Key Design Decisions

**organize_album_1.sh** runs three sequential passes over files:
1. Photos (HEIC/JPG) — extracts EXIF `DateTimeOriginal`/`CreateDate`, groups into `YYYYMMDD/` folders
2. Videos (MP4) — same date extraction; live-photo videos (matched via `ContentIdentifier` EXIF tag) are segregated into `mp4_live_videos/` at root level
3. Other files — organized by date or moved to `unknown_date/`

Date folders with fewer than 5 files are consolidated into an `individual/` bucket.

**download_album_all_1.py** uses Playwright (non-headless, persistent Chrome profile) to navigate Google Photos and click "Download All". The Chrome profile must be pre-authenticated with Google (one-time manual login).

**upload_to_drive.sh** uses `gws` (Google Workspace CLI) for single files and `rclone` for folder uploads.

### Logging

- Orchestrator logs: `$LOG_DIR/download_and_organize_<EXEC_ID>.log`
- Organizer logs: `$LOG_DIR/organize_<EXEC_ID>/organize_album_<EXEC_ID>.log`
- Upload logs: `$LOG_DIR/upload_to_drive_<EXEC_ID>.log`

Use `-d yes` for verbose/debug output.

## Environment

- Designed for WSL2 (Windows Subsystem for Linux)
- Git remote uses SSH: `git@github.com:jormedv/Project_PhotoOrganizer.git`

## Git Workflow

### Commit

Stage specific files (never `git add -A`), then commit with a descriptive message and co-author tag:

```bash
git add <file1> <file2> ...
git commit -m "$(cat <<'EOF'
Short summary line (imperative mood, under 70 chars)

- Bullet explaining what changed and why
- Another bullet if needed

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

### Push

Remote is SSH — no password prompt required:

```bash
git push
```

If the remote is ever set to HTTPS, switch it back:

```bash
git remote set-url origin git@github.com:jormedv/Project_PhotoOrganizer.git
```
