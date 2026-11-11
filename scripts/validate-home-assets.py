#!/usr/bin/env python3
"""Validate MusicX homepage image assets against HomeArtwork.swift."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "MusicX" / "Assets.xcassets"
ARTWORK = ROOT / "MusicX" / "Features" / "Home" / "HomeArtwork.swift"
EXPECTED = {
    "home_hero", "daily_recommend", "featured_playlist",
    "chart_hot", "chart_rising", "chart_new",
    *(f"album_{i:02d}" for i in range(1, 6)),
    "playlist_relax", "playlist_night", "playlist_drive",
    *(f"song_{i:02d}" for i in range(1, 7)),
    *(f"guess_{i:02d}" for i in range(1, 4)),
    "player_cover",
}

def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)

source = ARTWORK.read_text(encoding="utf-8")
match = re.search(r"private let names = \[(.*?)\]", source, re.S)
if not match:
    fail("Could not locate HomeArtwork.names")
declared = set(re.findall(r'"([a-zA-Z0-9_]+)"', match.group(1)))
if declared != EXPECTED:
    fail(f"HomeArtwork.names mismatch; missing={sorted(EXPECTED - declared)}, unexpected={sorted(declared - EXPECTED)}")

for name in sorted(EXPECTED):
    folder = ASSETS / f"{name}.imageset"
    metadata = folder / "Contents.json"
    image = folder / f"{name}.jpg"
    if not metadata.is_file():
        fail(f"Missing {metadata.relative_to(ROOT)}")
    if not image.is_file():
        fail(f"Missing {image.relative_to(ROOT)}")
    try:
        data = json.loads(metadata.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"Invalid {metadata.relative_to(ROOT)}: {error}")
    filenames = {item.get("filename") for item in data.get("images", [])}
    if image.name not in filenames:
        fail(f"{metadata.relative_to(ROOT)} does not reference {image.name}")

print(f"OK: validated {len(EXPECTED)} homepage image sets, JPG files, and Contents.json references.")
