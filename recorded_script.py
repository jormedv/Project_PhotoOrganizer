import re
from playwright.sync_api import Playwright, sync_playwright, expect


def run(playwright: Playwright) -> None:
    browser = playwright.chromium.launch(channel="chrome", headless=False)
    context = browser.new_context()
    page.goto("https://photos.google.com/share/AF1QipPKstyDa-f6KnXLwuzukksNQjsBGhrBQFRLBqZdKqw2AoTJ773DqnOUf06QBT9m7A?obfsgid=106615097338837901788")
    page.get_by_role("button", name="More options").click()
    page.get_by_role("menuitem", name="Download all").click()
    with page.expect_download() as download_info:
        page.goto("https://photos.google.com/share/AF1QipPKstyDa-f6KnXLwuzukksNQjsBGhrBQFRLBqZdKqw2AoTJ773DqnOUf06QBT9m7A?obfsgid=106615097338837901788")
    download = download_info.value

    # ---------------------
    context.close()
    browser.close()


with sync_playwright() as playwright:
    run(playwright)
