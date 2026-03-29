#!/usr/bin/env python3
"""Download and import the latest MTGJSON AllPrintings data."""
from __future__ import annotations

import argparse
import bz2
import json
import sys
import tempfile
from pathlib import Path

import httpx

from app.services.mtgjson_index import import_all_printings

MTGJSON_META_URL = "https://mtgjson.com/api/v5/Meta.json"
MTGJSON_BZ2_URL = "https://mtgjson.com/api/v5/AllPrintings.json.bz2"
DOWNLOAD_CHUNK_SIZE = 65536
HTTP_TIMEOUT = 300.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download and import the latest MTGJSON AllPrintings data.",
    )
    parser.add_argument(
        "--db-path",
        type=Path,
        default=Path("services/api/data/mtgjson/mtgjson.sqlite"),
        help="Destination SQLite database path.",
    )
    parser.add_argument(
        "--manifest-path",
        type=Path,
        default=Path("services/api/data/mtgjson/manifest.json"),
        help="Destination manifest path.",
    )
    parser.add_argument(
        "--tmp-dir",
        type=Path,
        default=Path("tmp"),
        help="Directory for temporary decompressed file.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Force download even if local version matches remote.",
    )
    return parser.parse_args()


def fetch_remote_version() -> str | None:
    """Fetch the current MTGJSON version from the Meta endpoint."""
    try:
        resp = httpx.get(MTGJSON_META_URL, timeout=30.0, follow_redirects=True)
        resp.raise_for_status()
        return str(resp.json().get("data", {}).get("version", ""))
    except (httpx.HTTPError, json.JSONDecodeError, KeyError):
        return None


def read_local_version(manifest_path: Path) -> str | None:
    """Read the MTGJSON version from the local manifest file."""
    if not manifest_path.is_file():
        return None
    try:
        manifest = json.loads(manifest_path.read_text())
        return manifest.get("mtgjson_version")
    except (json.JSONDecodeError, OSError):
        return None


def _print_progress(downloaded: int, total: int) -> None:
    mb_down = downloaded // (1024 * 1024)
    if total:
        mb_total = total // (1024 * 1024)
        pct = downloaded * 100 // total
        print(f"\rDownloading: {mb_down}MB / {mb_total}MB ({pct}%)", end="", flush=True)
    else:
        print(f"\rDownloading: {mb_down}MB", end="", flush=True)


def download_and_decompress(dest_path: Path) -> None:
    """Stream-download AllPrintings.json.bz2 and decompress to dest_path."""
    decompressor = bz2.BZ2Decompressor()
    downloaded = 0
    with httpx.Client(follow_redirects=True, timeout=HTTP_TIMEOUT) as client:
        with client.stream("GET", MTGJSON_BZ2_URL) as response:
            response.raise_for_status()
            total = int(response.headers.get("content-length", 0))
            with dest_path.open("wb") as f:
                for chunk in response.iter_bytes(chunk_size=DOWNLOAD_CHUNK_SIZE):
                    downloaded += len(chunk)
                    f.write(decompressor.decompress(chunk))
                    _print_progress(downloaded, total)
    print()


def main() -> int:
    args = parse_args()

    if not args.force:
        print("Checking for updates...")
        remote_version = fetch_remote_version()
        if remote_version is None:
            print("Warning: could not fetch remote version, proceeding with download.")
        else:
            local_version = read_local_version(args.manifest_path)
            if local_version and local_version == remote_version:
                print(f"Already up to date (version {local_version}).")
                return 0
            print(f"Update available: {local_version or '(none)'} -> {remote_version}")

    args.tmp_dir.mkdir(parents=True, exist_ok=True)
    tmp_file = tempfile.NamedTemporaryFile(
        dir=args.tmp_dir, suffix=".json", delete=False,
    )
    tmp_path = Path(tmp_file.name)
    tmp_file.close()

    try:
        download_and_decompress(tmp_path)
        print("Importing into database...")
        summary = import_all_printings(
            source_path=tmp_path,
            db_path=args.db_path,
            manifest_path=args.manifest_path,
        )
        print(
            f"Imported {summary.card_count} card printings across "
            f"{summary.set_count} sets (skipped {summary.skipped_card_count})."
        )
        print(f"DB: {args.db_path}")
        print(f"Manifest: {args.manifest_path}")
    except httpx.HTTPError as exc:
        print(f"\nDownload failed: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"\nDecompression or I/O error: {exc}", file=sys.stderr)
        return 1
    finally:
        if tmp_path.exists():
            tmp_path.unlink()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
