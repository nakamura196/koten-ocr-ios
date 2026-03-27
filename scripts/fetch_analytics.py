#!/usr/bin/env python3
"""
Fetch and analyze App Store Connect Analytics reports.

Usage:
    python3 scripts/fetch_analytics.py
    python3 scripts/fetch_analytics.py --days 7
    python3 scripts/fetch_analytics.py --category APP_USAGE
"""

import argparse
import gzip
import io
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timedelta

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


def download_report(url):
    """Download a report file (possibly gzipped TSV)."""
    token = generate_token()
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "Accept-Encoding": "gzip",
    })
    resp = urllib.request.urlopen(req)
    data = resp.read()

    # Try to decompress gzip
    try:
        data = gzip.decompress(data)
    except (gzip.BadGzipFile, OSError):
        pass

    return data.decode("utf-8")


def parse_tsv(tsv_text):
    """Parse TSV text into list of dicts."""
    lines = tsv_text.strip().split("\n")
    if not lines:
        return []
    headers = lines[0].split("\t")
    rows = []
    for line in lines[1:]:
        values = line.split("\t")
        row = dict(zip(headers, values))
        rows.append(row)
    return rows


def ensure_ongoing_request():
    """Ensure there's an ONGOING analytics report request for the app."""
    # Check existing requests
    resp = api_request("GET", f"apps/{APP_ID}/analyticsReportRequests"
                       f"?filter[accessType]=ONGOING")
    existing = resp.get("data", [])
    if existing:
        print(f"Found existing ONGOING report request: {existing[0]['id']}")
        return existing[0]["id"]

    # Create new ONGOING request
    print("Creating new ONGOING analytics report request...")
    data = {
        "data": {
            "type": "analyticsReportRequests",
            "attributes": {
                "accessType": "ONGOING"
            },
            "relationships": {
                "app": {
                    "data": {"type": "apps", "id": APP_ID}
                }
            }
        }
    }
    resp = api_request("POST", "analyticsReportRequests", data)
    req_id = resp["data"]["id"]
    print(f"Created report request: {req_id}")
    print("Note: Reports may take up to 24-48 hours to become available for new requests.")
    return req_id


def list_reports(request_id, category_filter=None):
    """List available reports for a request."""
    path = f"analyticsReportRequests/{request_id}/reports"
    if category_filter:
        path += f"?filter[category]={category_filter}"
    resp = api_request("GET", path)
    return resp.get("data", [])


def get_report_instances(report_id):
    """Get downloadable instances for a report."""
    resp = api_request("GET", f"analyticsReports/{report_id}/instances"
                       f"?limit=10")
    return resp.get("data", [])


def analyze_data(rows, date_key, metric_key, days=7, group_key=None):
    """Analyze report data: show recent trends."""
    if not rows:
        print("  No data available.")
        return

    # Find date and metric columns
    if date_key not in rows[0]:
        # Try to find date-like column
        for k in rows[0]:
            if "date" in k.lower():
                date_key = k
                break

    cutoff = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")

    # Filter recent data
    recent = [r for r in rows if r.get(date_key, "") >= cutoff]
    if not recent:
        print(f"  No data in the last {days} days.")
        # Show what dates are available
        dates = sorted(set(r.get(date_key, "") for r in rows))
        if dates:
            print(f"  Available date range: {dates[0]} ~ {dates[-1]}")
        return

    if group_key and group_key in rows[0]:
        # Group by version/dimension
        from collections import defaultdict
        grouped = defaultdict(lambda: defaultdict(float))
        for r in recent:
            group = r.get(group_key, "unknown")
            date = r.get(date_key, "")
            try:
                val = float(r.get(metric_key, 0))
            except (ValueError, TypeError):
                val = 0
            grouped[group][date] += val

        for group in sorted(grouped.keys()):
            dates_data = grouped[group]
            total = sum(dates_data.values())
            print(f"  {group}: total={int(total)}")
            for d in sorted(dates_data.keys())[-7:]:
                print(f"    {d}: {int(dates_data[d])}")
    else:
        # Simple daily totals
        from collections import defaultdict
        daily = defaultdict(float)
        for r in recent:
            date = r.get(date_key, "")
            try:
                val = float(r.get(metric_key, 0))
            except (ValueError, TypeError):
                val = 0
            daily[date] += val

        total = sum(daily.values())
        avg = total / len(daily) if daily else 0
        print(f"  Total: {int(total)}  |  Daily avg: {avg:.1f}")
        for d in sorted(daily.keys()):
            print(f"    {d}: {int(daily[d])}")


def main():
    parser = argparse.ArgumentParser(description="Fetch App Store Connect Analytics")
    parser.add_argument("--days", type=int, default=7, help="Number of days to analyze (default: 7)")
    parser.add_argument("--category", type=str, default=None,
                        help="Filter by category (APP_USAGE, APP_STORE_ENGAGEMENT, PERFORMANCE, FRAMEWORKS)")
    parser.add_argument("--list-reports", action="store_true", help="List available reports only")
    parser.add_argument("--download-all", action="store_true", help="Download and show all available reports")
    parser.add_argument("--raw", action="store_true", help="Show raw TSV data")
    args = parser.parse_args()

    print(f"=== KotenOCR Analytics Report ({datetime.now().strftime('%Y-%m-%d %H:%M')}) ===\n")

    # Step 1: Ensure ongoing request exists
    request_id = ensure_ongoing_request()

    # Step 2: List available reports
    reports = list_reports(request_id, args.category)
    if not reports:
        print("\nNo reports available yet.")
        if not args.category:
            print("Try specifying a category: APP_USAGE, APP_STORE_ENGAGEMENT, PERFORMANCE, FRAMEWORKS")
        return

    if args.list_reports:
        print(f"\nAvailable reports ({len(reports)}):")
        for r in reports:
            attrs = r["attributes"]
            print(f"  [{attrs.get('category', '?')}] {attrs.get('name', '?')} (id: {r['id']})")
        return

    # Step 3: Fetch and analyze each report
    # Target key metrics
    target_reports = {}
    for r in reports:
        attrs = r["attributes"]
        name = attrs.get("name", "")
        category = attrs.get("category", "")
        target_reports.setdefault(category, []).append(r)

    for category in sorted(target_reports.keys()):
        print(f"\n{'='*60}")
        print(f"  Category: {category}")
        print(f"{'='*60}")

        for report in target_reports[category]:
            attrs = report["attributes"]
            name = attrs.get("name", "unknown")
            print(f"\n--- {name} ---")

            # Get instances
            instances = get_report_instances(report["id"])
            if not instances:
                print("  No instances available.")
                continue

            # Download the most recent instance
            latest = instances[0]
            instance_attrs = latest.get("attributes", {})
            processing_date = instance_attrs.get("processingDate", "?")
            print(f"  Processing date: {processing_date}")

            # Get download URL from the instance
            # The URL might be in segments
            segments_link = latest.get("relationships", {}).get("segments", {}).get("links", {}).get("related")
            if segments_link:
                # Fetch segments to get download URL
                token = generate_token()
                req = urllib.request.Request(segments_link, headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json"
                })
                try:
                    seg_resp = urllib.request.urlopen(req)
                    seg_data = json.loads(seg_resp.read())
                    segments = seg_data.get("data", [])
                    if not segments:
                        print("  No segments available.")
                        continue

                    for seg in segments[:1]:  # Just first segment
                        seg_url = seg.get("attributes", {}).get("url")
                        if not seg_url:
                            print("  No download URL in segment.")
                            continue

                        print(f"  Downloading report data...")
                        tsv_text = download_report(seg_url)
                        rows = parse_tsv(tsv_text)

                        if not rows:
                            print("  Empty report.")
                            continue

                        if args.raw:
                            # Show raw first 20 lines
                            lines = tsv_text.strip().split("\n")
                            for line in lines[:20]:
                                print(f"  {line}")
                            if len(lines) > 20:
                                print(f"  ... ({len(lines)} total lines)")
                            continue

                        # Show column names
                        print(f"  Columns: {', '.join(rows[0].keys())}")
                        print(f"  Total rows: {len(rows)}")

                        # Try to find date and metric columns
                        date_col = None
                        metric_col = None
                        group_col = None
                        for k in rows[0].keys():
                            kl = k.lower()
                            if "date" in kl:
                                date_col = k
                            elif any(m in kl for m in ["count", "total", "units", "sessions",
                                                        "installs", "impressions", "views",
                                                        "crashes", "downloads"]):
                                metric_col = k
                            elif any(g in kl for g in ["version", "source", "device", "platform"]):
                                group_col = k

                        if date_col and metric_col:
                            analyze_data(rows, date_col, metric_col, args.days, group_col)
                        else:
                            # Just show sample rows
                            print(f"  Sample data (first 5 rows):")
                            for row in rows[:5]:
                                print(f"    {row}")

                except urllib.error.HTTPError as e:
                    print(f"  Failed to fetch segments: {e.code}")
                except Exception as e:
                    print(f"  Error: {e}")

    print(f"\n{'='*60}")
    print(f"Analysis complete. Period: last {args.days} days")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
