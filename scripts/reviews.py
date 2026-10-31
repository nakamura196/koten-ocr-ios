#!/usr/bin/env python3
"""
List App Store customer reviews and post developer responses.

Usage:
    python3 scripts/reviews.py                       # all reviews, newest first
    python3 scripts/reviews.py --unanswered          # only reviews without a response
    python3 scripts/reviews.py --reply <REVIEW_ID> --body-file reply.txt
    python3 scripts/reviews.py --reply <REVIEW_ID> --body-file reply.txt --dry-run

Responses are public on the App Store. A posted response is PENDING_PUBLISH
until Apple publishes it (usually within a day).
"""

import argparse
import json
import os
import sys
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

APP_ID = "6760045646"


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
        error_body = e.read().decode()
        print(f"Error {e.code}: {error_body}")
        raise


def list_reviews(unanswered_only):
    d = api_request("GET", f"apps/{APP_ID}/customerReviews?limit=200&sort=-createdDate&include=response")
    responses = {i["id"]: i["attributes"] for i in d.get("included", [])}
    for r in d["data"]:
        a = r["attributes"]
        resp_id = (r["relationships"].get("response", {}).get("data") or {}).get("id")
        if unanswered_only and resp_id:
            continue
        status = "responded" if resp_id else "NO RESPONSE"
        print("=" * 60)
        print(f"{r['id']}  {a['createdDate'][:10]}  {a['territory']}  {'★' * a['rating']}  | {status}")
        print(f"Title: {a.get('title')}")
        print(a.get("body"))
        if resp_id:
            ra = responses.get(resp_id, {})
            print(f"  >> Response ({ra.get('state')}): {ra.get('responseBody', '')}")


def reply(review_id, body, dry_run):
    payload = {"data": {
        "type": "customerReviewResponses",
        "attributes": {"responseBody": body},
        "relationships": {"review": {"data": {"type": "customerReviews", "id": review_id}}},
    }}
    if dry_run:
        print(f"[dry-run] Would reply to {review_id}:\n{body}")
        return
    r = api_request("POST", "customerReviewResponses", payload)
    print(f"Posted {r['data']['id']} ({r['data']['attributes'].get('state')})")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--unanswered", action="store_true", help="Show only reviews without a response")
    parser.add_argument("--reply", metavar="REVIEW_ID", help="Post a response to this review")
    parser.add_argument("--body-file", help="Text file with the response body (required with --reply)")
    parser.add_argument("--dry-run", action="store_true", help="Show the response without posting")
    args = parser.parse_args()

    if args.reply:
        if not args.body_file:
            sys.exit("--body-file is required with --reply")
        with open(args.body_file) as f:
            reply(args.reply, f.read().strip(), args.dry_run)
    else:
        list_reviews(args.unanswered)


if __name__ == "__main__":
    main()
