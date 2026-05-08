#!/usr/bin/env python3
"""
Build the registry index.

Reads every app manifest under ../apps/, adds a download_url for each
.tpapp package, copies the packages into this directory, and writes
index.json.

Usage:
    BASE_URL=http://localhost:9090 python3 build.py
"""

import json
import os
import shutil

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPS_DIR = os.path.join(ROOT, "apps")
OUT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_URL = os.environ.get("BASE_URL", "http://localhost:9090").rstrip("/")

entries = []

for name in sorted(os.listdir(APPS_DIR)):
    manifest_path = os.path.join(APPS_DIR, name, "manifest.yaml")
    tpapp_src = os.path.join(APPS_DIR, name, f"{name}.tpapp")

    if not os.path.exists(manifest_path):
        continue
    if not os.path.exists(tpapp_src):
        print(f"  skip {name}: {name}.tpapp not found (run 'make build-all' first)")
        continue

    with open(manifest_path) as f:
        manifest = yaml.safe_load(f)

    tpapp_filename = f"{name}.tpapp"
    manifest["download_url"] = f"{BASE_URL}/{tpapp_filename}"
    entries.append(manifest)

    dest = os.path.join(OUT_DIR, tpapp_filename)
    shutil.copy2(tpapp_src, dest)
    print(f"  {name} v{manifest.get('version', '?')} → {tpapp_filename}")

index_path = os.path.join(OUT_DIR, "index.json")
with open(index_path, "w") as f:
    json.dump(entries, f, indent=2)

print(f"\nWrote {index_path} ({len(entries)} apps)")
