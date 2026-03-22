#!/usr/bin/env python3
"""
Upload App Store preview video to App Store Connect.

Usage:
    python3 scripts/upload_preview.py --video /tmp/kotenocr_videos/demo_ja_combined_iphone.mp4 --lang ja
    python3 scripts/upload_preview.py --video /tmp/kotenocr_videos/demo_ja_combined_iphone.mp4 --lang ja --dry-run
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

# Preview type for iPhone 6.7"
PREVIEW_TYPE = "IPHONE_67"


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
    """Get app ID and latest editable version."""
    result = api_request("GET", f"apps?filter[bundleId]={BUNDLE_ID}")
    app_id = result["data"][0]["id"]

    result = api_request("GET", f"apps/{app_id}/appStoreVersions")

    for v in result["data"]:
        state = v["attributes"]["appStoreState"]
        if state == "PREPARE_FOR_SUBMISSION":
            return app_id, v["id"], v["attributes"]["versionString"], state

    # Find current version
    current_version = result["data"][0]["attributes"]["versionString"]
    state = result["data"][0]["attributes"]["appStoreState"]
    return app_id, result["data"][0]["id"], current_version, state


def get_localizations(version_id):
    """Get localization IDs."""
    result = api_request("GET",
        f"appStoreVersions/{version_id}/appStoreVersionLocalizations")
    return {loc["attributes"]["locale"]: loc["id"] for loc in result["data"]}


def get_or_create_preview_set(loc_id, preview_type):
    """Get existing preview set or create a new one."""
    result = api_request("GET",
        f"appStoreVersionLocalizations/{loc_id}/appPreviewSets")

    for ps in result["data"]:
        if ps["attributes"]["previewType"] == preview_type:
            return ps["id"]

    # Create new preview set
    result = api_request("POST", "appPreviewSets", {
        "data": {
            "type": "appPreviewSets",
            "attributes": {"previewType": preview_type},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                }
            }
        }
    })
    return result["data"]["id"]


def delete_existing_previews(loc_id, preview_type):
    """Delete all existing previews in a preview set."""
    result = api_request("GET",
        f"appStoreVersionLocalizations/{loc_id}/appPreviewSets"
        f"?include=appPreviews")

    for ps in result["data"]:
        if ps["attributes"]["previewType"] != preview_type:
            continue

        related_ids = [r["id"] for r in
                       ps["relationships"]["appPreviews"]["data"]]
        for preview in result.get("included", []):
            if preview["id"] in related_ids:
                print(f"  Deleting existing preview: {preview['attributes'].get('fileName', preview['id'])}")
                api_request("DELETE", f"appPreviews/{preview['id']}")

        return ps["id"]

    return None


def upload_preview(preview_set_id, filepath, filename):
    """Upload a preview video (reserve → upload binary → commit)."""
    with open(filepath, "rb") as f:
        file_data = f.read()
    filesize = len(file_data)
    checksum = base64.b64encode(hashlib.md5(file_data).digest()).decode()

    # Step 1: Reserve
    print(f"  Reserving upload for {filename} ({filesize / 1024 / 1024:.1f} MB)...")
    result = api_request("POST", "appPreviews", {
        "data": {
            "type": "appPreviews",
            "attributes": {
                "fileName": filename,
                "fileSize": filesize,
                "mimeType": "video/mp4"
            },
            "relationships": {
                "appPreviewSet": {
                    "data": {"type": "appPreviewSets", "id": preview_set_id}
                }
            }
        }
    })
    preview_id = result["data"]["id"]
    upload_ops = result["data"]["attributes"]["uploadOperations"]
    print(f"  Reserved: {preview_id} ({len(upload_ops)} chunk(s))")

    # Step 2: Upload binary chunks
    for i, op in enumerate(upload_ops):
        chunk = file_data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req)
        print(f"  Uploaded chunk {i + 1}/{len(upload_ops)}")

    # Step 3: Commit
    print("  Committing...")
    result = api_request("PATCH", f"appPreviews/{preview_id}", {
        "data": {
            "type": "appPreviews",
            "id": preview_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": checksum
            }
        }
    })
    state = result["data"]["attributes"]["assetDeliveryState"]["state"]
    print(f"  Done: {state}")
    return preview_id


def main():
    parser = argparse.ArgumentParser(
        description="Upload App Store preview video to App Store Connect")
    parser.add_argument("--video", required=True,
        help="Path to preview video (MP4, max 30s)")
    parser.add_argument("--lang", default="ja",
        help="Language: ja or en (default: ja)")
    parser.add_argument("--dry-run", action="store_true",
        help="Show what would be done without uploading")
    args = parser.parse_args()

    if not os.path.exists(args.video):
        print(f"Error: Video not found: {args.video}")
        return

    filesize = os.path.getsize(args.video)
    print(f"Video: {args.video} ({filesize / 1024 / 1024:.1f} MB)")

    # Get app info
    app_id, version_id, version, state = get_app_and_version()
    print(f"App: {app_id}, Version: {version} ({state})")

    locs = get_localizations(version_id)
    print(f"Localizations: {list(locs.keys())}")

    # Find matching locale
    locale_map = {"ja": "ja", "en": "en-US"}
    target_locale = locale_map.get(args.lang, args.lang)

    # Try exact match, then prefix match
    loc_id = locs.get(target_locale)
    if loc_id is None:
        for locale, lid in locs.items():
            if locale.startswith(args.lang):
                loc_id = lid
                target_locale = locale
                break

    if loc_id is None:
        print(f"Error: No localization found for '{args.lang}'. Available: {list(locs.keys())}")
        return

    print(f"Target locale: {target_locale} ({loc_id})")

    if args.dry_run:
        print(f"\n--- DRY RUN ---")
        print(f"Would delete existing {PREVIEW_TYPE} previews for {target_locale}")
        print(f"Would upload: {args.video}")
        print("Run without --dry-run to actually upload.")
        return

    # Delete existing previews and upload new one
    print(f"\nUploading preview for {target_locale} ({PREVIEW_TYPE})...")
    ps_id = delete_existing_previews(loc_id, PREVIEW_TYPE)
    if ps_id is None:
        ps_id = get_or_create_preview_set(loc_id, PREVIEW_TYPE)

    filename = os.path.basename(args.video)
    upload_preview(ps_id, args.video, filename)

    print("\n=== Upload complete ===")


if __name__ == "__main__":
    main()
