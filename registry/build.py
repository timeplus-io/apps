#!/usr/bin/env python3
"""
Build the registry index.

Two modes:

  Local (default):
    BASE_URL=http://localhost:9090 python3 build.py
    Copies .tpapp files into registry/ and writes index.json with local URLs.

  GitHub releases (single registry release):
    GITHUB_REPO=org/repo GITHUB_RELEASE_TAG=registry-v1.0.0 python3 build.py
    Writes index.json with GitHub release download URLs.
    download_url = https://github.com/{GITHUB_REPO}/releases/download/{GITHUB_RELEASE_TAG}/{app}.tpapp
    Does NOT copy .tpapp files (they are uploaded by the CI workflow).
"""

import json
import os
import shutil

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPS_DIR = os.path.join(ROOT, "apps")
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

GITHUB_REPO = os.environ.get("GITHUB_REPO", "").strip()
GITHUB_RELEASE_TAG = os.environ.get("GITHUB_RELEASE_TAG", "").strip()
BASE_URL = os.environ.get("BASE_URL", "http://localhost:9090").rstrip("/")


def github_download_url(repo: str, release_tag: str, app_name: str) -> str:
    return f"https://github.com/{repo}/releases/download/{release_tag}/{app_name}.tpapp"


entries = []

for name in sorted(os.listdir(APPS_DIR)):
    manifest_path = os.path.join(APPS_DIR, name, "manifest.yaml")
    tpapp_src = os.path.join(APPS_DIR, name, f"{name}.tpapp")

    if not os.path.exists(manifest_path):
        continue

    with open(manifest_path) as f:
        manifest = yaml.safe_load(f)

    version = manifest.get("version", "0.0.0")
    tpapp_filename = f"{name}.tpapp"

    if GITHUB_REPO and GITHUB_RELEASE_TAG:
        manifest["download_url"] = github_download_url(GITHUB_REPO, GITHUB_RELEASE_TAG, name)
        print(f"  {name} v{version} → {manifest['download_url']}")
    else:
        if not os.path.exists(tpapp_src):
            print(f"  skip {name}: {tpapp_filename} not found (run 'make build-all' first)")
            continue
        manifest["download_url"] = f"{BASE_URL}/{tpapp_filename}"
        shutil.copy2(tpapp_src, os.path.join(OUT_DIR, tpapp_filename))
        print(f"  {name} v{version} → {manifest['download_url']}")

    entries.append(manifest)

index_path = os.path.join(OUT_DIR, "index.json")
with open(index_path, "w") as f:
    json.dump(entries, f, indent=2)

print(f"\nWrote {index_path} ({len(entries)} apps)")
