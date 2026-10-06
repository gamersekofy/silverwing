#!/usr/bin/env python3
"""Fetch the Kaggle "Trending YouTube Video Statistics" dataset into ./data.

Source: https://www.kaggle.com/datasets/datasnaek/youtube-new

Kaggle offers several ways to obtain it; this script picks the most portable and
needs no third-party packages (standard library only):

  1. kagglehub   ->  kagglehub.dataset_download("datasnaek/youtube-new")
  2. plain HTTPS ->  https://www.kaggle.com/api/v1/datasets/download/datasnaek/youtube-new
  3. a local zip ->  python analysis/download_data.py --from-zip path/to/youtube-new.zip

By default it uses kagglehub if it is installed, otherwise falls back to HTTPS. The
public dataset downloads without credentials; if you do have a Kaggle account you can
set KAGGLE_USERNAME / KAGGLE_KEY (or ~/.kaggle/kaggle.json) and they will be used.

Whatever the source, the .csv and .json files are placed flat in ./data so that
analysis/*.py can read them, and the two US files are checksum-verified.

Usage:
  python analysis/download_data.py
  python analysis/download_data.py --force
  python analysis/download_data.py --from-zip ~/Downloads/youtube-new.zip
  python analysis/download_data.py --method http --dest /tmp/data
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DEST = ROOT / "data"
DATASET = "datasnaek/youtube-new"
API_URL = f"https://www.kaggle.com/api/v1/datasets/download/{DATASET}"
USER_AGENT = "Mozilla/5.0 (compatible; math448-download/1.0)"

# Files the analysis actually needs, with expected SHA-256 (see data/README.md).
REQUIRED = {
    "USvideos.csv":
        "09b4eb71295752705e472ebefeac9d2afab4177b7a818af795dea62744a48eb2",
    "US_category_id.json":
        "2e892c5a5e48d284e40fd37de0313912264041aef8833e5323bd2b2fd08c7e25",
}
KEEP_SUFFIXES = (".csv", ".json")


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def _auth_header() -> str | None:
    """Optional Kaggle basic-auth, from env vars or ~/.kaggle/kaggle.json."""
    user = os.environ.get("KAGGLE_USERNAME")
    key = os.environ.get("KAGGLE_KEY")
    if not (user and key):
        cfg = Path.home() / ".kaggle" / "kaggle.json"
        if cfg.exists():
            try:
                data = json.loads(cfg.read_text(encoding="utf-8"))
                user, key = data.get("username"), data.get("key")
            except (OSError, ValueError):
                pass
    if user and key:
        token = base64.b64encode(f"{user}:{key}".encode()).decode()
        return f"Basic {token}"
    return None


def _progress(done: int, total: int | None) -> None:
    mb = done / (1 << 20)
    if total:
        sys.stdout.write(f"\r  downloaded {mb:7.1f} / {total / (1 << 20):.1f} MiB"
                         f"  ({100 * done / total:5.1f}%)")
    else:
        sys.stdout.write(f"\r  downloaded {mb:7.1f} MiB")
    sys.stdout.flush()


def _download_http(url: str, out_path: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    auth = _auth_header()
    if auth:
        req.add_header("Authorization", auth)
    print(f"  GET {url}")
    with urllib.request.urlopen(req, timeout=180) as resp, open(out_path, "wb") as fh:
        length = resp.headers.get("Content-Length")
        total = int(length) if length and length.isdigit() else None
        print(f"  status {resp.status}, type {resp.headers.get('Content-Type')}")
        done = 0
        while True:
            chunk = resp.read(1 << 20)
            if not chunk:
                break
            fh.write(chunk)
            done += len(chunk)
            _progress(done, total)
    print()


def _extract_zip(zip_path: Path, dest: Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    count = 0
    with zipfile.ZipFile(zip_path) as zf:
        for member in zf.namelist():
            if member.endswith("/"):
                continue
            name = Path(member).name
            if name.lower().endswith(KEEP_SUFFIXES):
                with zf.open(member) as src, open(dest / name, "wb") as out:
                    shutil.copyfileobj(src, out)
                count += 1
    return count


def _copy_tree(src: Path, dest: Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    count = 0
    for path in src.rglob("*"):
        if path.is_file() and path.name.lower().endswith(KEEP_SUFFIXES):
            shutil.copy2(path, dest / path.name)
            count += 1
    return count


def _via_kagglehub(dest: Path) -> bool:
    try:
        import kagglehub  # type: ignore
    except ImportError:
        return False
    print("Using kagglehub ...")
    path = Path(kagglehub.dataset_download(DATASET))
    print(f"  kagglehub cache: {path}")
    if path.is_dir():
        n = _copy_tree(path, dest)
    else:
        n = _extract_zip(path, dest)
    print(f"  copied {n} file(s) into {dest}")
    return True


def _already_present(dest: Path) -> bool:
    return all((dest / name).exists() for name in REQUIRED)


def _verify(dest: Path) -> bool:
    print("Verifying required files:")
    ok = True
    for name, expected in REQUIRED.items():
        path = dest / name
        if not path.exists():
            print(f"  MISSING  {name}")
            ok = False
        elif _sha256(path) == expected:
            print(f"  ok       {name}")
        else:
            print(f"  WARN     {name}  (sha256 does not match data/README.md)")
    return ok


def _inventory(dest: Path) -> None:
    files = sorted(p for p in dest.iterdir()
                   if p.is_file() and p.name.lower().endswith(KEEP_SUFFIXES))
    if not files:
        return
    print(f"\n{len(files)} file(s) in {dest}:")
    for path in files:
        print(f"  {path.stat().st_size:>12,}  {path.name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dest", type=Path, default=DEFAULT_DEST,
                        help="target directory (default: ./data)")
    parser.add_argument("--force", action="store_true",
                        help="re-download even if the files already exist")
    parser.add_argument("--from-zip", type=Path, metavar="ZIP",
                        help="extract a locally downloaded zip instead of fetching")
    parser.add_argument("--method", choices=["auto", "http", "kagglehub"], default="auto",
                        help="download method (default: auto)")
    args = parser.parse_args()

    dest = args.dest.resolve()
    dest.mkdir(parents=True, exist_ok=True)

    if args.from_zip:
        if not args.from_zip.exists():
            print(f"error: zip not found: {args.from_zip}", file=sys.stderr)
            return 2
        print(f"Extracting {args.from_zip} -> {dest} ...")
        print(f"  extracted {_extract_zip(args.from_zip, dest)} file(s)")
        _verify(dest)
        _inventory(dest)
        return 0

    if _already_present(dest) and not args.force:
        print(f"Data already present in {dest} (use --force to re-download).")
        _verify(dest)
        _inventory(dest)
        return 0

    if args.method in ("auto", "kagglehub") and _via_kagglehub(dest):
        _verify(dest)
        _inventory(dest)
        return 0
    if args.method == "kagglehub":
        print("error: kagglehub is not installed (pip install kagglehub)", file=sys.stderr)
        return 2

    print("Downloading via HTTPS ...")
    with tempfile.TemporaryDirectory(prefix="youtube-new-") as td:
        zip_path = Path(td) / "youtube-new.zip"
        _download_http(API_URL, zip_path)
        print("Extracting ...")
        print(f"  extracted {_extract_zip(zip_path, dest)} file(s)")

    _verify(dest)
    _inventory(dest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
