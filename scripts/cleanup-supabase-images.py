#!/usr/bin/env python3
"""
Delete all GIFs from the Supabase exercise-images storage bucket.
Run this AFTER confirming the R2 migration is working correctly.

Required environment variable: SUPABASE_KEY.
Optional: SUPABASE_URL and SUPABASE_BUCKET.
"""

import json
import os
import urllib.request


def require_env(name):
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://dtzlfvuazdrgyyutjysm.supabase.co")
SUPABASE_KEY = require_env("SUPABASE_KEY")
SUPABASE_BUCKET = os.environ.get("SUPABASE_BUCKET", "exercise-images")


def list_files(limit=10000):
    url = f"{SUPABASE_URL}/storage/v1/object/list/{SUPABASE_BUCKET}"
    data = json.dumps({"prefix": "", "limit": limit}).encode()
    req = urllib.request.Request(url, data=data, method="POST", headers={
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def delete_files(filenames):
    """Delete a batch of files from Supabase Storage (max ~100 at a time)."""
    url = f"{SUPABASE_URL}/storage/v1/object/{SUPABASE_BUCKET}"
    data = json.dumps({"prefixes": filenames}).encode()
    req = urllib.request.Request(url, data=data, method="DELETE", headers={
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def main():
    print("Listing files in Supabase exercise-images bucket...")
    files = list_files()
    filenames = [f["name"] for f in files]
    print(f"Found {len(filenames)} files to delete\n")

    if not filenames:
        print("Nothing to delete.")
        return

    # Confirm before deleting
    confirm = input(f"Delete all {len(filenames)} files? (yes/no): ")
    if confirm.lower() != "yes":
        print("Aborted.")
        return

    # Delete in batches of 100
    batch_size = 100
    deleted = 0
    for i in range(0, len(filenames), batch_size):
        batch = filenames[i:i + batch_size]
        try:
            result = delete_files(batch)
            deleted += len(batch)
            print(f"Deleted {deleted}/{len(filenames)}...")
        except Exception as e:
            print(f"Error deleting batch at offset {i}: {e}")

    print(f"\nDone! Deleted {deleted} files from Supabase Storage.")


if __name__ == "__main__":
    main()
