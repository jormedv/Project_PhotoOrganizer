from playwright.sync_api import Playwright, sync_playwright

def run(playwright: Playwright) -> None:
    context = playwright.chromium.launch_persistent_context(
        user_data_dir="/home/jorgemedinavallejo/.config/google-chrome-playwright",
        channel="chrome",
        headless=False,
    )
    page = context.new_page()

    page.goto("https://photos.google.com/share/AF1QipPKstyDa-f6KnXLwuzukksNQjsBGhrBQFRLBqZdKqw2AoTJ773DqnOUf06QBT9m7A?obfsgid=106615097338837901788")
    
    # Wait for page to fully load
    page.wait_for_load_state("networkidle")

    # Trigger download and capture it
    with page.expect_download(timeout=60000) as download_info:
        page.get_by_role("button", name="More options").click()
        page.get_by_role("menuitem", name="Download all").click()
    
    download = download_info.value

    # Save to your Downloads folder
    save_path = f"/home/jorgemedinavallejo/Downloads/{download.suggested_filename}"
    download.save_as(save_path)
    print(f"Downloaded to: {save_path}")

    context.close()

with sync_playwright() as playwright:
    run(playwright)
