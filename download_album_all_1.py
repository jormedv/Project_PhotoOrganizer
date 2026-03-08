import os
import re
from playwright.sync_api import sync_playwright

ALBUM_ID = "AF1QipPKstyDa-f6KnXLwuzukksNQjsBGhrBQFRLBqZdKqw2AoTJ773DqnOUf06QBT9m7A"
ALBUM_URL = f"https://photos.google.com/share/{ALBUM_ID}?obfsgid=106615097338837901788&email=jorge.medina.vallejo.ai@gmail.com&key=NWRpT3luZ0IxRlRpWDMwYzdmSXlUWE40eU9OX0lB"
DOWNLOAD_DIR = "photos"
os.makedirs(DOWNLOAD_DIR, exist_ok=True)

with sync_playwright() as p:
    browser = p.chromium.launch_persistent_context(
        user_data_dir="/home/jorge/.config/chrome-playwright",
        headless=False,
        channel="chrome",
        args=[
            "--disable-blink-features=AutomationControlled",
            "--no-sandbox",
            "--disable-dev-shm-usage",
        ],
        ignore_default_args=["--enable-automation"],
    )

    page = browser.new_page()
    page.add_init_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")

    page.goto(ALBUM_URL)
    page.wait_for_load_state("networkidle")
    input("Album loaded? Press ENTER to attempt Download All...")

    # Try various selectors Google Photos uses for the Download All button
    # It may be a direct button or inside a 3-dot menu
    download_all_clicked = False

    # Strategy 1: direct "Download all" button visible on the page
    for selector in [
        "button[aria-label='Download all']",
        "button[aria-label='Download All']",
        "[data-tooltip='Download all']",
        "span:has-text('Download all')",
        "div[aria-label='Download all']",
    ]:
        try:
            btn = page.locator(selector).first
            if btn.is_visible(timeout=2000):
                print(f"Found Download All via: {selector}")
                with page.expect_download(timeout=300000) as download_info:
                    btn.click()
                download_all_clicked = True
                download = download_info.value
                zip_path = os.path.join(os.path.abspath(DOWNLOAD_DIR), "album.zip")
                print("Downloading zip... this may take a while")
                download.save_as(zip_path)
                size_mb = os.path.getsize(zip_path) / (1024 * 1024)
                print(f"✓ Downloaded: {zip_path} ({size_mb:.1f} MB)")
                break
        except Exception:
            continue

    # Strategy 2: open the 3-dot / more options menu on the album page first
    if not download_all_clicked:
        print("Direct button not found, trying via More Options menu...")
        for menu_selector in [
            "button[aria-label='More options']",
            "button[aria-label='Open menu']",
            "[data-tooltip='More options']",
            "button[aria-label='Menu']",
        ]:
            try:
                menu_btn = page.locator(menu_selector).first
                if menu_btn.is_visible(timeout=2000):
                    print(f"Clicking menu: {menu_selector}")
                    menu_btn.click()
                    page.wait_for_timeout(1000)

                    # Now look for Download all in the opened dropdown
                    for dl_selector in [
                        "li[aria-label='Download all']",
                        "span:has-text('Download all')",
                        "div[role='menuitem']:has-text('Download all')",
                        "[aria-label='Download all']",
                    ]:
                        try:
                            dl_btn = page.locator(dl_selector).first
                            if dl_btn.is_visible(timeout=2000):
                                print(f"Found Download All in menu via: {dl_selector}")
                                with page.expect_download(timeout=300000) as download_info:
                                    dl_btn.click()
                                download_all_clicked = True
                                download = download_info.value
                                zip_path = os.path.join(os.path.abspath(DOWNLOAD_DIR), "album.zip")
                                print("Downloading zip... this may take a while")
                                download.save_as(zip_path)
                                size_mb = os.path.getsize(zip_path) / (1024 * 1024)
                                print(f"✓ Downloaded: {zip_path} ({size_mb:.1f} MB)")
                                break
                        except Exception:
                            continue

                    if download_all_clicked:
                        break
                    else:
                        page.keyboard.press("Escape")
            except Exception:
                continue

    if not download_all_clicked:
        print("\n✗ Could not find Download All button automatically.")
        print("Please open the browser, click 'Download all' manually,")
        print("and the script will capture the download.")

        # Last resort: just wait and capture any download that happens
        try:
            with page.expect_download(timeout=300000) as download_info:
                input("Click 'Download all' in the browser, then press ENTER here...")
            download = download_info.value
            zip_path = os.path.join(os.path.abspath(DOWNLOAD_DIR), "album.zip")
            print("Saving download...")
            download.save_as(zip_path)
            size_mb = os.path.getsize(zip_path) / (1024 * 1024)
            print(f"✓ Downloaded: {zip_path} ({size_mb:.1f} MB)")
        except Exception as e:
            print(f"✗ Failed: {e}")

    browser.close()
