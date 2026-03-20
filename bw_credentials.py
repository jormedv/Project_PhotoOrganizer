"""
bw_credentials.py
-----------------
Retrieve secrets from Bitwarden at runtime.
No secrets are stored in environment variables or on disk.

Usage:
    from bw_credentials import get_credential, load_env

    # fetch one secret by name
    api_key = get_credential("OPENAI_API_KEY")

    # fetch all secrets declared in a .env manifest
    creds = load_env(".env")
    db_pass = creds["DB_PASSWORD"]
"""

import subprocess
import os
import sys
import json

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

GPG_FILE     = os.path.expanduser("~/DEV/.secrets/master.gpg")
SECRETS_REPO = os.path.expanduser("~/DEV/.secrets")

# ---------------------------------------------------------------------------
# Internal state — cached for the lifetime of the process, never written to disk
# ---------------------------------------------------------------------------

_session: str | None = None
_vault_cache: dict | None = None  # all vault items indexed by exact name


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

def _sync_secrets_repo() -> None:
    """Pull latest from GitHub (uses SSH key — no prompt)."""
    result = subprocess.run(
        ["git", "-C", SECRETS_REPO, "pull"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Failed to sync secrets repo:\n{result.stderr.strip()}"
        )


def _decrypt_master_password() -> str:
    """Decrypt master.gpg with GPG private key — no passphrase prompt."""
    result = subprocess.run(
        ["gpg", "--decrypt", "--quiet", GPG_FILE],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"GPG decryption failed:\n{result.stderr.strip()}"
        )
    password = result.stdout.strip()
    if not password:
        raise RuntimeError(
            f"GPG decrypted successfully but output was empty. "
            f"Check that {GPG_FILE} was encrypted with the correct content."
        )
    return password


def _unlock_bitwarden(password: str) -> str:
    """Unlock the Bitwarden vault and return a session token."""
    result = subprocess.run(
        ["bw", "unlock", "--raw", password],
        capture_output=True,
        text=True,
    )
    session = result.stdout.strip()
    if not session:
        raise RuntimeError(
            "bw unlock returned no session token. "
            "Make sure you are logged in: run 'bw login' once manually."
        )
    return session


def _load_vault_cache() -> None:
    """
    Fetch all vault items once and index them by exact name in memory.
    This means only one bw CLI call regardless of how many credentials you fetch.
    """
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

    # index by exact item name for O(1) lookup
    _vault_cache = {item["name"]: item for item in items}


def _get_session() -> str:
    """
    Return a valid Bitwarden session token.
    On first call: syncs repo, decrypts password, unlocks vault, loads all items.
    On subsequent calls: returns cached session instantly.
    """
    global _session
    if _session:
        return _session

    _sync_secrets_repo()
    password = _decrypt_master_password()
    _session = _unlock_bitwarden(password)
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
        e.g. "OPENAI_API_KEY"
    field : str
        The field to retrieve: "password" (default) or "username"

    Returns
    -------
    str
        The value of the requested field.

    Raises
    ------
    KeyError
        If no item with that exact name exists, or the field is empty.
    ValueError
        If an unsupported field is requested.
    RuntimeError
        If Bitwarden cannot be unlocked or vault cannot be loaded.
    """
    _get_session()  # ensures _vault_cache is populated

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


def load_env(dotenv_path: str = ".env") -> dict:
    """
    Read key names from a .env manifest file and fetch each from Bitwarden.

    The .env file should contain key names only (values are ignored):
        DB_PASSWORD
        API_KEY=anything_here_is_ignored
        # lines starting with # are comments

    Parameters
    ----------
    dotenv_path : str
        Path to the .env file. Defaults to ".env" in the current directory.

    Returns
    -------
    dict
        Mapping of key name -> secret value.
        Keys not found in Bitwarden are excluded; a warning is printed.

    Raises
    ------
    FileNotFoundError
        If the .env file does not exist.
    RuntimeError
        If Bitwarden cannot be unlocked.
    """
    if not os.path.exists(dotenv_path):
        raise FileNotFoundError(
            f".env file not found at '{dotenv_path}'"
        )

    credentials: dict = {}
    missing: list = []

    with open(dotenv_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # support both "KEY" and "KEY=placeholder" formats
            key = line.split("=")[0].strip()
            if not key:
                continue
            try:
                credentials[key] = get_credential(key)
            except KeyError:
                missing.append(key)

    if missing:
        for key in missing:
            print(
                f"[bw_credentials] WARNING: '{key}' not found in Bitwarden",
                file=sys.stderr
            )

    return credentials


def reset_session() -> None:
    """
    Clear the cached session token and vault cache.
    Call this if the session has expired and you need to re-authenticate.
    """
    global _session, _vault_cache
    _session = None
    _vault_cache = None