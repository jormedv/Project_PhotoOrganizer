"""
test_gsm_and_bw.py
------------------
Smoke-test for the GSM → Bitwarden unlock chain.

Steps:
  1. Load config from .env.test_gsm
  2. Fetch the Bitwarden master password from Google Secret Manager
  3. Unlock the Bitwarden vault
  4. List vault items — print count and first 5 names as proof

Usage:
    cp .env.test_gsm.sample .env.test_gsm   # fill in your values
    python test_gsm_and_bw.py

Authentication (ADC):
  Local:   gcloud auth application-default login
  GCP VM:  automatic via Workload Identity
"""

import json
import os
import subprocess
import sys
from pathlib import Path

from google.cloud import secretmanager

# ---------------------------------------------------------------------------
# Load config from .env.test_gsm
# ---------------------------------------------------------------------------

ENV_FILE = Path(__file__).parent / ".env.test_gsm"

if not ENV_FILE.exists():
    print(f"ERROR: {ENV_FILE} not found.")
    print(f"       Copy .env.test_gsm.sample to .env.test_gsm and fill in your values.")
    sys.exit(1)

with open(ENV_FILE) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip())

GCP_PROJECT = os.environ.get("GCP_PROJECT", "")
GSM_SECRET  = os.environ.get("GSM_SECRET", "")

if not GCP_PROJECT or not GSM_SECRET:
    print("ERROR: GCP_PROJECT and GSM_SECRET must be set in .env.test_gsm")
    sys.exit(1)


def log(msg: str) -> None:
    print(f"[TEST] {msg}", flush=True)


# ---------------------------------------------------------------------------
# Step 1 — Fetch BW master password from GSM
# ---------------------------------------------------------------------------

log(f"Fetching secret '{GSM_SECRET}' from project '{GCP_PROJECT}'...")

try:
    client   = secretmanager.SecretManagerServiceClient()
    name     = f"projects/{GCP_PROJECT}/secrets/{GSM_SECRET}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    bw_master_password = response.payload.data.decode("utf-8").strip()
    log("GSM fetch OK.")
except Exception as e:
    print(f"\nERROR: could not fetch secret from GSM:\n  {e}")
    print()
    print("Checklist:")
    print("  1. Authenticated?  →  gcloud auth application-default login")
    print("  2. Correct project? →", GCP_PROJECT)
    print("  3. Secret exists?  →  gcloud secrets list --project", GCP_PROJECT)
    print("  4. IAM role granted?  roles/secretmanager.secretAccessor")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Step 2 — Unlock Bitwarden vault
# ---------------------------------------------------------------------------

log("Unlocking Bitwarden vault...")

result = subprocess.run(
    ["bw", "unlock", "--raw", "--passwordenv", "BW_MASTER_PASSWORD"],
    capture_output=True,
    text=True,
    encoding="utf-8",
    env={**os.environ, "BW_MASTER_PASSWORD": bw_master_password},
)

session = result.stdout.strip()

if not session:
    print(f"\nERROR: bw unlock returned no session token.")
    print(f"  exit code : {result.returncode}")
    print(f"  stderr    : {result.stderr.strip()}")
    print()
    print("Checklist:")
    print("  1. Logged in?  →  bw login")
    print("  2. Vault synced?  →  bw sync")
    sys.exit(1)

log("Bitwarden vault unlocked OK.")

# ---------------------------------------------------------------------------
# Step 3 — List vault items as proof
# ---------------------------------------------------------------------------

log("Fetching vault items...")

result = subprocess.run(
    ["bw", "list", "items"],
    capture_output=True,
    text=True,
    env={**os.environ, "BW_SESSION": session},
)

if result.returncode != 0:
    print(f"ERROR: bw list items failed:\n{result.stderr.strip()}")
    sys.exit(1)

try:
    items = json.loads(result.stdout)
except json.JSONDecodeError:
    print("ERROR: could not parse bw list items output as JSON.")
    sys.exit(1)

log(f"Vault contains {len(items)} items.")
log("First 5 item names:")
for item in items[:5]:
    print(f"    - {item.get('name', '(no name)')}")

print()
log("All checks passed. GSM → Bitwarden chain is working.")
