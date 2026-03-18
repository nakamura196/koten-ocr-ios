#!/usr/bin/env python3
"""
Upload marketing screenshots to App Store Connect.
Replaces existing screenshots with new marketing images.

Usage:
    python3 scripts/upload_screenshots.py --dir screenshots/marketing
    python3 scripts/upload_screenshots.py --dir screenshots/marketing --dry-run
"""

import argparse
import base64
import hashlib
import json
import os
import time
import urllib.request

import jwt

# Load credentials
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)

# Read .env
env_path = os.path.join(PROJECT_DIR, ".env")
env_vars = {}
if os.path.exists(env_path):
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env_vars[k.strip()] = v.strip()

KEY_ID = env_vars.get("APP_STORE_API_KEY", os.environ.get("ASC_KEY_ID", ""))
ISSUER_ID = env_vars.get("APP_STORE_API_ISSUER", os.environ.get("ASC_ISSUER_ID", ""))
KEY_PATH = os.path.expanduser(f"~/.private_keys/AuthKey_{KEY_ID}.p8")
BUNDLE_ID = "com.nakamura196.kotenocr"


def generate_token():
    with open(KEY_PATH, "r") as f:
        private_key = f.read()
    now = int(time.time())
    payload = {
        "iss": ISSUER_ID, "iat": now, "exp": now + 1200,
        "aud": "appstoreconnect-v1"
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID})


def api_request(method, path, data=None):
    token = generate_token()
    url = f"https://api.appstoreconnect.apple.com/v1/{path}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method, headers={
        "Authorization": f"Bearer {token}", "Content-Type": "application/json"
    })
    try:
        resp = urllib.request.urlopen(req)
        if resp.status == 204:
            return None
        return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"Error {e.code}: {e.read().decode()}")
        raise


def get_app_and_version():
    """Get app ID and latest editable version. Create new version if needed."""
    result = api_request("GET", f"apps?filter[bundleId]={BUNDLE_ID}")
    app_id = result["data"][0]["id"]

    result = api_request("GET", f"apps/{app_id}/appStoreVersions")

    # Prefer PREPARE_FOR_SUBMISSION (editable)
    for v in result["data"]:
        state = v["attributes"]["appStoreState"]
        if state == "PREPARE_FOR_SUBMISSION":
            return app_id, v["id"], v["attributes"]["versionString"], state

    # Find current READY_FOR_SALE version to determine next version
    current_version = None
    for v in result["data"]:
        state = v["attributes"]["appStoreState"]
        if state == "READY_FOR_SALE":
            current_version = v["attributes"]["versionString"]
            break

    if current_version is None:
        current_version = result["data"][0]["attributes"]["versionString"]

    # Create new version (increment patch)
    parts = current_version.split(".")
    parts[-1] = str(int(parts[-1]) + 1)
    new_version = ".".join(parts)

    print(f"Creating new version {new_version} (current: {current_version})...")
    new_ver = api_request("POST", "appStoreVersions", {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "versionString": new_version,
                "platform": "IOS"
            },
            "relationships": {
                "app": {
                    "data": {"type": "apps", "id": app_id}
                }
            }
        }
    })
    version_id = new_ver["data"]["id"]
    state = new_ver["data"]["attributes"]["appStoreState"]
    print(f"Created version {new_version} ({state})")
    return app_id, version_id, new_version, state


def get_localizations(version_id):
    """Get localization IDs."""
    result = api_request("GET",
        f"appStoreVersions/{version_id}/appStoreVersionLocalizations")
    return {loc["attributes"]["locale"]: loc["id"] for loc in result["data"]}


def delete_existing_screenshots(loc_id, display_type):
    """Delete all existing screenshots in a screenshot set."""
    result = api_request("GET",
        f"appStoreVersionLocalizations/{loc_id}/appScreenshotSets"
        f"?include=appScreenshots")

    for ss_set in result["data"]:
        if ss_set["attributes"]["screenshotDisplayType"] != display_type:
            continue

        related_ids = [r["id"] for r in
                       ss_set["relationships"]["appScreenshots"]["data"]]
        for sc in result.get("included", []):
            if sc["id"] in related_ids:
                print(f"  Deleting: {sc['attributes'].get('fileName', sc['id'])}")
                api_request("DELETE", f"appScreenshots/{sc['id']}")

        return ss_set["id"]

    return None


def create_screenshot_set(loc_id, display_type):
    """Create screenshot set if it doesn't exist."""
    result = api_request("GET",
        f"appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    for ss_set in result["data"]:
        if ss_set["attributes"]["screenshotDisplayType"] == display_type:
            return ss_set["id"]

    result = api_request("POST", "appScreenshotSets", {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                }
            }
        }
    })
    return result["data"]["id"]


def upload_screenshot(screenshot_set_id, filepath, filename):
    """Upload a screenshot (reserve → upload binary → commit)."""
    with open(filepath, "rb") as f:
        file_data = f.read()
    filesize = len(file_data)
    checksum = base64.b64encode(hashlib.md5(file_data).digest()).decode()

    # Step 1: Reserve
    result = api_request("POST", "appScreenshots", {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileName": filename, "fileSize": filesize},
            "relationships": {
                "appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": screenshot_set_id}
                }
            }
        }
    })
    screenshot_id = result["data"]["id"]
    upload_ops = result["data"]["attributes"]["uploadOperations"]
    print(f"    Reserved: {screenshot_id}")

    # Step 2: Upload binary
    for op in upload_ops:
        chunk = file_data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req)
    print(f"    Uploaded: {len(upload_ops)} chunk(s)")

    # Step 3: Commit
    result = api_request("PATCH", f"appScreenshots/{screenshot_id}", {
        "data": {
            "type": "appScreenshots",
            "id": screenshot_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": checksum}
        }
    })
    state = result["data"]["attributes"]["assetDeliveryState"]["state"]
    print(f"    Committed: {state}")
    return screenshot_id


def get_lang_dir(base_dir, locale):
    """Map App Store Connect locale to screenshot subdirectory."""
    # e.g. "ja" -> "ja", "en-US" -> "en"
    lang = locale.split("-")[0]
    lang_dir = os.path.join(base_dir, lang)
    if os.path.isdir(lang_dir):
        return lang_dir
    # Fallback: if no subdirectory structure, use base dir directly
    if any(f.endswith(".png") for f in os.listdir(base_dir) if os.path.isfile(os.path.join(base_dir, f))):
        return base_dir
    return None


def main():
    parser = argparse.ArgumentParser(description="Upload screenshots to App Store Connect")
    parser.add_argument("--dir", required=True, help="Directory with marketing screenshots (with ja/en subdirs)")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done without uploading")
    args = parser.parse_args()

    # Get app info
    app_id, version_id, version, state = get_app_and_version()
    print(f"App: {app_id}, Version: {version} ({state})")

    locs = get_localizations(version_id)
    print(f"Localizations: {list(locs.keys())}")

    if args.dry_run:
        print("\n--- DRY RUN ---")
        for locale, loc_id in locs.items():
            lang_dir = get_lang_dir(args.dir, locale)
            if lang_dir is None:
                print(f"\n{locale}: No screenshots directory found, skipping")
                continue
            iphone_files = sorted([f for f in os.listdir(lang_dir) if "iphone" in f and f.endswith(".png")])
            ipad_files = sorted([f for f in os.listdir(lang_dir) if "ipad" in f and f.endswith(".png")])
            print(f"\n{locale} (from {lang_dir}):")
            print(f"  Would delete existing iPhone screenshots and upload {len(iphone_files)} new ones")
            print(f"  Would delete existing iPad screenshots and upload {len(ipad_files)} new ones")
        print("\nRun without --dry-run to actually upload.")
        return

    # Upload for each locale
    for locale, loc_id in locs.items():
        lang_dir = get_lang_dir(args.dir, locale)
        if lang_dir is None:
            print(f"\n=== {locale}: No screenshots directory found, skipping ===")
            continue

        iphone_files = sorted([f for f in os.listdir(lang_dir) if "iphone" in f and f.endswith(".png")])
        ipad_files = sorted([f for f in os.listdir(lang_dir) if "ipad" in f and f.endswith(".png")])

        print(f"\n=== {locale} (from {lang_dir}) ===")
        print(f"Found {len(iphone_files)} iPhone + {len(ipad_files)} iPad screenshots")

        # iPhone screenshots
        if iphone_files:
            print(f"\n  iPhone (APP_IPHONE_67):")
            ss_set_id = delete_existing_screenshots(loc_id, "APP_IPHONE_67")
            if ss_set_id is None:
                ss_set_id = create_screenshot_set(loc_id, "APP_IPHONE_67")

            for f in iphone_files:
                filepath = os.path.join(lang_dir, f)
                print(f"  Uploading {f}...")
                upload_screenshot(ss_set_id, filepath, f)

        # iPad screenshots
        if ipad_files:
            print(f"\n  iPad (APP_IPAD_PRO_3GEN_129):")
            ss_set_id = delete_existing_screenshots(loc_id, "APP_IPAD_PRO_3GEN_129")
            if ss_set_id is None:
                ss_set_id = create_screenshot_set(loc_id, "APP_IPAD_PRO_3GEN_129")

            for f in ipad_files:
                filepath = os.path.join(lang_dir, f)
                print(f"  Uploading {f}...")
                upload_screenshot(ss_set_id, filepath, f)

    print("\n=== Upload complete ===")


if __name__ == "__main__":
    main()
