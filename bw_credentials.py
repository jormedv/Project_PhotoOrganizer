"""
bw_credentials.py
-----------------
Retrieve secrets from Bitwarden at runtime via Google Secret Manager.

Flow:
  1. Fetch the Bitwarden master password from Google Secret Manager (GSM).
  2. Unlock the local Bitwarden vault  →  session token (in-memory only).
  3. Fetch all vault items once and cache them for the process lifetime.

Authentication to GSM uses Application Default Credentials (ADC):
  Local:   gcloud auth application-default login
  GCP VM:  automatic via Workload Identity (no setup needed)

Configuration (env vars, or defaults below):
  GCP_PROJECT   Google Cloud project ID  (default: jmv-linux-gcloud)
  GSM_SECRET    Secret name in GSM       (default: JMV-BW)

Usage:
    from bw_credentials import get_credential

    password = get_credential("GOOGLE_PHOTOS_ALBUM_URL")
"""

import json
import os
import subprocess

from google.cloud import secretmanager

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

GCP_PROJECT = os.environ.get("GCP_PROJECT", "jmv-linux-gcloud")
GSM_SECRET  = os.environ.get("GSM_SECRET",  "JMV-BW")

# ---------------------------------------------------------------------------
# Internal state — cached for the lifetime of the process, never written to disk
# ---------------------------------------------------------------------------

_session:     str  | None = None
_vault_cache: dict | None = None   # all vault items indexed by exact name


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

def _fetch_master_password() -> str:
    """Fetch the Bitwarden master password from Google Secret Manager."""
    try:
        client   = secretmanager.SecretManagerServiceClient()
        name     = f"projects/{GCP_PROJECT}/secrets/{GSM_SECRET}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("utf-8").strip()
    except Exception as e:
        raise RuntimeError(
            f"Failed to fetch secret '{GSM_SECRET}' from GSM project '{GCP_PROJECT}':\n{e}\n\n"
            f"Local fix:  gcloud auth application-default login\n"
            f"GCP VM:     verify Workload Identity and IAM role "
            f"roles/secretmanager.secretAccessor"
        ) from e


def _unlock_bitwarden(password: str) -> str:
    """Unlock the Bitwarden vault and return a session token."""
    result = subprocess.run(
        ["bw", "unlock", "--raw", "--passwordenv", "BW_MASTER_PASSWORD"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        env={**os.environ, "BW_MASTER_PASSWORD": password},
    )
    session = result.stdout.strip()
    if not session:
        raise RuntimeError(
            f"bw unlock returned no session token (exit code {result.returncode}).\n"
            f"stdout: {result.stdout!r}\n"
            f"stderr: {result.stderr.strip()}\n"
            "Make sure you are logged in: run 'bw login' then 'bw sync'."
        )
    return session


def _load_vault_cache() -> None:
    """Fetch all vault items once and index them by exact name in memory."""
    global _vault_cache

    result = subprocess.run(
        ["bw", "list", "items"],
        capture_output=True,
        text=True,
        env={**os.environ, "BW_SESSION": _session},
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Failed to list Bitwarden items:\n{result.stderr.strip()}"
        )

    try:
        items = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise RuntimeError("Failed to parse Bitwarden vault response as JSON.")

    _vault_cache = {item["name"]: item for item in items}


def _get_session() -> str:
    """
    Return a valid Bitwarden session token.
    On first call: fetches password from GSM, unlocks vault, loads all items.
    On subsequent calls: returns cached session instantly.
    """
    global _session
    if _session:
        return _session

    password  = _fetch_master_password()
    _session  = _unlock_bitwarden(password)
    _load_vault_cache()
    return _session


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def get_credential(key: str, field: str = "password") -> str:
    """
    Fetch a single credential from Bitwarden by exact item name.

    Parameters
    ----------
    key : str
        The exact name of the item in Bitwarden (case-sensitive).
    field : str
        The field to retrieve: "password" (default) or "username".

    Raises
    ------
    KeyError      If the item or field does not exist in the vault.
    ValueError    If an unsupported field is requested.
    RuntimeError  If GSM or Bitwarden cannot be reached.
    """
    _get_session()

    item = _vault_cache.get(key)
    if not item:
        raise KeyError(
            f"Credential '{key}' not found in Bitwarden. "
            f"Make sure an item named exactly '{key}' exists in your vault."
        )

    if field == "password":
        value = item.get("login", {}).get("password", "")
    elif field == "username":
        value = item.get("login", {}).get("username", "")
    else:
        raise ValueError(
            f"Unknown field '{field}'. Supported fields: 'password', 'username'."
        )

    if not value:
        raise KeyError(
            f"Credential '{key}' exists in Bitwarden but field '{field}' is empty."
        )

    return value


def reset_session() -> None:
    """Clear the cached session and vault. Call if the session has expired."""
    global _session, _vault_cache
    _session     = None
    _vault_cache = None
