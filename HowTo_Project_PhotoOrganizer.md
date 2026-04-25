# HowTo: Project PhotoOrganizer

## 1. Project Description

**Purpose:** End-to-end pipeline that downloads a shared Google Photos album, organizes the photos and videos by date using EXIF metadata, and uploads the result to Google Drive.

**Problem it solves:** Shared Google Photos albums can be downloaded only as a flat zip of files. This pipeline converts that flat dump into a structured folder hierarchy organized by shoot date, with live-photo videos separated from regular videos and sparse dates consolidated into a single bucket.

**Key technologies:**
- Python 3 / Playwright — browser automation for Google Photos download
- Bash — orchestration, organizing, uploading
- ExifTool — EXIF metadata extraction (dates, ContentIdentifier)
- rclone — Google Drive upload
- Google Secret Manager (GSM) + Bitwarden — zero-secrets-on-disk credential chain

**Scope:**
- Downloads one shared Google Photos album URL per run
- Organizes HEIC/JPG photos, MP4 videos, and any other file types
- Does NOT sync incrementally — each run produces a fresh `organized_album.zip`
- Does NOT delete files from Google Photos or Drive

---

## 2. How the Project is Executed

### Main entry point

```bash
./download_and_organize.sh
```

This is the full-pipeline orchestrator. It sources `.env.photoorganizer`, then runs three stages in sequence: download → organize → upload.

### Execution modes and flags

```bash
# Full pipeline (download + organize + upload)
./download_and_organize.sh

# Skip download step (reuse existing ~/data/Project_PhotoOrganizer/album.zip)
./download_and_organize.sh -s

# Enable verbose/debug output
./download_and_organize.sh -d yes

# Pass flags to the organizer step (e.g. unzip-only)
./download_and_organize.sh -- -u

# Run individual components directly
source .venv/bin/activate
python3 download_album_all_1.py          # download only
./organize_album_1.sh                    # organize only
./upload_to_drive.sh -f <path>           # upload only
```

### What happens at each phase

1. **Download** (`download_album_all_1.py`)
   - Launches a non-headless Chrome browser using a persistent Playwright profile (already logged into Google).
   - Navigates to `GOOGLE_PHOTOS_ALBUM_URL`, waits for the SPA to settle, then clicks "More options → Download all".
   - Saves the resulting zip to `$DATA_DIR/album.zip`.

2. **Organize** (`organize_album_1.sh`)
   - Unzips `album.zip` into a timestamped temp directory.
   - Runs three passes: photos → MP4 videos → other files. Each file is placed into a `YYYYMMDD/` folder based on EXIF date (`DateTimeOriginal` → `CreateDate` → `FileModifyDate`).
   - Live-photo MP4s (matched via `ContentIdentifier` EXIF tag to their paired HEIC/JPG) are segregated into `mp4_live_videos/` at the root.
   - Date folders with fewer than 5 total files are consolidated into `individual/`.
   - Produces `$DATA_DIR/organized_album.zip`.

3. **Upload** (`upload_to_drive.sh`)
   - Uses `rclone copy` to upload `organized_album.zip` to the `gdrive:SHARED_WITH_JORGE` remote folder.

### Expected output and success indicators

- Organizer prints a summary line, e.g.:
  ```
  Result: 312 files — Photos: 240 | Videos: 52 | Unknown: 20 | Size: 1234.5MB  ✅
  ```
  A `✅` means the count of organized files matches the count of files that were in the input zips. A `❌` triggers a filename-level diff report in the log directory.
- Upload prints:
  ```
  Upload succeeded. Log: /home/jorge/logs/Project_PhotoOrganizer/upload_to_drive_<EXEC_ID>.log
  ```

---

## 3. Architecture Diagram

```
download_and_organize.sh  (orchestrator)
│
├─► download_album_all_1.py
│       Playwright (Chrome, non-headless)
│       → photos.google.com  [persistent auth profile]
│       → "More options → Download all"
│       → $DATA_DIR/album.zip
│
├─► organize_album_1.sh
│       unzip album.zip  →  tmp_<EXEC_ID>/
│       │
│       ├── Phase 1: Photos (HEIC/JPG)
│       │       exiftool → DateTimeOriginal / CreateDate / FileModifyDate
│       │       → OUT_DIR/YYYYMMDD/
│       │       (records ContentIdentifier for live-photo pairing)
│       │
│       ├── Phase 2: Videos (MP4)
│       │       exiftool → date folders  → OUT_DIR/YYYYMMDD/videos/
│       │       live-photo match (ContentIdentifier) → OUT_DIR/mp4_live_videos/
│       │
│       ├── Phase 3: Other files
│       │       → OUT_DIR/YYYYMMDD/unknown/
│       │
│       ├── Consolidate: small date folders (< 5 files)
│       │       → OUT_DIR/individual/
│       │
│       └── Zip output  →  $DATA_DIR/organized_album.zip
│
└─► upload_to_drive.sh
        rclone copy
        → gdrive:SHARED_WITH_JORGE/organized_album.zip

Credential chain (used by Python scripts):
    GSM (Google Secret Manager)
        ↓ gcloud ADC (local) or Workload Identity (GCP VM)
    Bitwarden master password  [in-memory]
        ↓ bw unlock
    BW session token  [in-memory]
        ↓ bw list items
    Vault cache  [in-memory, process lifetime]
        ↓ get_credential(key)
    Individual secrets
```

---

## 4. How the Project is Deployed

This project runs locally on WSL2. There is no build step and no containerisation. "Deployment" means ensuring dependencies are installed and the one-time auth steps are complete.

```bash
# Install system-level tools (exiftool, rclone, bw CLI, etc.)
bash requirements.apt.txt

# Install Python dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Install Playwright's Chromium browser
playwright install chromium

# Authenticate gcloud for Application Default Credentials (ADC)
gcloud auth application-default login

# One-time: log into Google inside the dedicated Playwright Chrome profile
google-chrome --user-data-dir=/home/jorge/.config/google-chrome-playwright
# Navigate to photos.google.com, complete login, then close Chrome.

# Configure rclone with a Google Drive remote named "gdrive"
rclone config
# Follow the interactive prompts; name the remote "gdrive".
```

Changes that require only config edits (no reinstall):
- Changing the album URL → edit `GOOGLE_PHOTOS_ALBUM_URL` in `.env.photoorganizer`
- Changing the Drive destination folder → edit `REMOTE_FOLDER` in `upload_to_drive.sh` or pass `-p <folder>` at runtime

---

## 5. Prerequisites

### Required tools

| Tool | Purpose |
|------|---------|
| `python3` + `pip` | Run the downloader and credential library |
| `playwright` (Python) | Browser automation |
| `google-chrome` | Playwright persistent context |
| `exiftool` | EXIF metadata extraction |
| `rclone` | Google Drive upload |
| `bw` (Bitwarden CLI) | Vault access |
| `gcloud` CLI | ADC + GSM access |
| `unzip`, `zip` | Archive handling |

### Credentials and secrets

- **Google Photos album URL** — stored in `.env.photoorganizer` as `GOOGLE_PHOTOS_ALBUM_URL`
- **Google account session** — stored in the Chrome persistent profile at `CHROME_USER_DATA_DIR` (set up once via manual login)
- **Bitwarden master password** — stored in Google Secret Manager under secret `JMV-BW` in project `jmv-linux-gcloud`; never written to disk
- **rclone Google Drive token** — stored by rclone in its own config (set up via `rclone config`)

### Environment file

```bash
cp .env.photoorganizer.sample .env.photoorganizer
```

Variables to fill in:

| Variable | Required | Notes |
|----------|----------|-------|
| `GOOGLE_PHOTOS_ALBUM_URL` | yes | Full URL of the shared album |
| `DATA_DIR` | no | Default: `~/data/Project_PhotoOrganizer` |
| `LOG_DIR` | no | Default: `~/logs/Project_PhotoOrganizer` |
| `CHROME_USER_DATA_DIR` | no | Default: `~/.config/google-chrome-playwright` |
| `GCP_PROJECT` | no | Default: `jmv-linux-gcloud` |
| `GSM_SECRET` | no | Default: `JMV-BW` |

### Smoke-test the GSM → Bitwarden chain

```bash
cp .env.test_gsm.sample .env.test_gsm
python test_gsm_and_bw.py
```

---

## 6. Detailed Functionality

### 6.1 Downloader — `download_album_all_1.py`

Uses Playwright's `launch_persistent_context` with `channel="chrome"` and `headless=False` so it reuses the pre-authenticated Chrome profile. After navigating to the album URL and waiting for the SPA to settle (`networkidle` + 3 s buffer), it clicks the "More options" button and then "Download all" menu item, then waits for the browser-triggered download and saves it as `$DATA_DIR/album.zip`.

**Non-obvious behaviour:** The 3-second extra wait after `networkidle` is required because Google Photos renders album controls asynchronously after the network goes idle. Without it, the "More options" button may not yet be in the DOM.

### 6.2 Organizer — `organize_album_1.sh`

Runs in `$DATA_DIR`. Processes each `*.zip` in that directory (excluding `organized_album.zip`).

**Phase 1 — Photos (HEIC/JPG/JPEG):**
Reads `DateTimeOriginal`, falls back to `CreateDate`, then `FileModifyDate`. Files with date `00000000` or no date go to `unknown_date/`. While processing, records each photo's `ContentIdentifier` EXIF tag keyed by base filename (no extension), for use in Phase 2.

**Phase 2 — Videos (MP4):**
Same date extraction. Additionally checks whether the MP4's base filename matches a photo from Phase 1 *and* its `ContentIdentifier` matches that photo's. If both match, the video is a Live Photo companion and goes to `$OUT_DIR/mp4_live_videos/` (flat, at root). All other MP4s go to `$OUT_DIR/YYYYMMDD/videos/`.

**Phase 3 — Other files:**
All remaining files (not HEIC/JPG/MP4) go to `$OUT_DIR/YYYYMMDD/unknown/`.

**Small-folder consolidation:**
After all three phases, date folders with fewer than 5 files total are merged into `individual/` (photos → `individual/`, videos → `individual/videos/`, others → `individual/unknown/`). This prevents dozens of one-photo date folders.

**Post-summary verification:**
Compares the total file count in `$OUT_DIR` against the total entry count from all input zips (computed during pre-processing). On mismatch, a Python inline script diffs the expected vs actual filename lists and reports missing/extra files to `$LOG_DIR/missing_files.txt` and `extra_files.txt`.

**Output:** `$DATA_DIR/organized_album.zip` — a zip of the entire `$OUT_DIR` tree.

### 6.3 Uploader — `upload_to_drive.sh`

Wraps `rclone copy` with logging. Accepts `-f <path>` (file or folder) and optional `-p <remote_folder>` (default: `SHARED_WITH_JORGE`). Logs file count and size before upload, then reports success or failure.

### 6.4 Credential library — `bw_credentials.py`

Provides a single public function `get_credential(key, field="password")`.

On first call it:
1. Fetches the Bitwarden master password from Google Secret Manager using `google-cloud-secret-manager` and ADC.
2. Runs `bw unlock --raw --passwordenv BW_MASTER_PASSWORD` to obtain a session token.
3. Runs `bw list items` and caches all vault items in a dict keyed by exact item name.

Subsequent calls return from the in-memory cache instantly. Nothing is written to disk. Call `reset_session()` if the session expires mid-run.
