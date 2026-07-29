#!/usr/bin/env python3
"""
Migrate exercise GIFs from Supabase Storage to Cloudflare R2.

1. Lists all GIF files in the Supabase exercise-images bucket
2. Downloads each one
3. Uploads to Cloudflare R2 exercise-images bucket
4. Prints the SQL UPDATE needed to repoint image_url columns

Required environment variables: SUPABASE_KEY, R2_ACCOUNT_ID, R2_ACCESS_KEY,
R2_SECRET_KEY, and R2_PUBLIC_URL. Bucket names and SUPABASE_URL are optional.
"""

import json
import os
import urllib.request
import boto3

# --- Config ---


def require_env(name):
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://dtzlfvuazdrgyyutjysm.supabase.co")
SUPABASE_KEY = require_env("SUPABASE_KEY")
SUPABASE_BUCKET = os.environ.get("SUPABASE_BUCKET", "exercise-images")

R2_ACCOUNT_ID = require_env("R2_ACCOUNT_ID")
R2_ACCESS_KEY = require_env("R2_ACCESS_KEY")
R2_SECRET_KEY = require_env("R2_SECRET_KEY")
R2_BUCKET = os.environ.get("R2_BUCKET", "exercise-images")
R2_PUBLIC_URL = require_env("R2_PUBLIC_URL")
R2_ENDPOINT = f"https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

# --- Supabase helpers ---
def list_supabase_files(limit=10000):
    url = f"{SUPABASE_URL}/storage/v1/object/list/{SUPABASE_BUCKET}"
    data = json.dumps({"prefix": "", "limit": limit}).encode()
    req = urllib.request.Request(url, data=data, method="POST", headers={
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

def download_supabase_file(filename):
    url = f"{SUPABASE_URL}/storage/v1/object/public/{SUPABASE_BUCKET}/{filename}"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req) as resp:
        return resp.read()

# --- R2 client ---
def get_r2_client():
    return boto3.client(
        "s3",
        endpoint_url=R2_ENDPOINT,
        aws_access_key_id=R2_ACCESS_KEY,
        aws_secret_access_key=R2_SECRET_KEY,
        region_name="auto",
    )

def upload_to_r2(client, filename, data):
    client.put_object(
        Bucket=R2_BUCKET,
        Key=filename,
        Body=data,
        ContentType="image/gif",
        CacheControl="public, max-age=31536000",  # 1 year cache
    )

# --- Main ---
def main():
    print("Listing files in Supabase storage...")
    files = list_supabase_files()
    total = len(files)
    print(f"Found {total} files to migrate\n")

    r2 = get_r2_client()

    # Check what's already uploaded to R2
    print("Checking existing R2 files...")
    existing = set()
    try:
        paginator = r2.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=R2_BUCKET):
            for obj in page.get("Contents", []):
                existing.add(obj["Key"])
    except Exception:
        pass
    print(f"Already in R2: {len(existing)} files\n")

    migrated = 0
    skipped = 0
    failed = 0

    for i, f in enumerate(files):
        filename = f["name"]
        progress = f"[{i+1}/{total}]"

        if filename in existing:
            skipped += 1
            if skipped <= 3:
                print(f"{progress} Skipping {filename} (already exists)")
            elif skipped == 4:
                print(f"  ... skipping remaining existing files ...")
            continue

        try:
            data = download_supabase_file(filename)
            upload_to_r2(r2, filename, data)
            migrated += 1
            if migrated % 25 == 0 or migrated <= 5:
                size_kb = len(data) / 1024
                print(f"{progress} Migrated {filename} ({size_kb:.0f} KB)")
        except Exception as e:
            failed += 1
            print(f"{progress} FAILED {filename}: {e}")

    print(f"\nDone! Migrated: {migrated}, Skipped: {skipped}, Failed: {failed}")

    # Print the SQL needed to update URLs
    old_base = f"{SUPABASE_URL}/storage/v1/object/public/{SUPABASE_BUCKET}"
    print(f"\n--- SQL to update exercise image URLs ---")
    print(f"""
UPDATE exercises
SET image_url = REPLACE(image_url, '{old_base}', '{R2_PUBLIC_URL}')
WHERE image_url LIKE '{old_base}%';
""")

if __name__ == "__main__":
    main()
