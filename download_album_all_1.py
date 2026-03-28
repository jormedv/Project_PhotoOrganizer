import os
from pathlib import Path
from playwright.sync_api import Playwright, sync_playwright

ALBUM_URL        = os.environ["GOOGLE_PHOTOS_ALBUM_URL"]
DOWNLOAD_DIR     = os.environ.get("DOWNLOAD_DIR", str(Path.home() / "data/Project_PhotoOrganizer"))
CHROME_USER_DATA = os.environ.get("CHROME_USER_DATA_DIR", str(Path.home() / ".config/google-chrome-playwright"))

os.makedirs(DOWNLOAD_DIR, exist_ok=True)

def run(playwright: Playwright) -> None:
    context = playwright.chromium.launch_persistent_context(
        user_data_dir=CHROME_USER_DATA,
        channel="chrome",
        headless=False,
    )
    page = context.new_page()

    page.goto(ALBUM_URL)
    page.wait_for_load_state("networkidle", timeout=90000)
    page.wait_for_timeout(3000)  # let the SPA finish rendering after networkidle

    with page.expect_download(timeout=90000) as download_info:
        page.get_by_role("button", name="More options").click(timeout=60000)
        page.get_by_role("menuitem", name="Download all").click(timeout=30000)

    download = download_info.value
    save_path = os.path.join(DOWNLOAD_DIR, "album.zip")
    download.save_as(save_path)
    print(f"Downloaded to: {save_path}")

    context.close()

with sync_playwright() as playwright:
    run(playwright)
