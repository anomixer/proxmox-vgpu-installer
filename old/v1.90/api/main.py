#!/usr/bin/env python3

import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse

app = FastAPI(title="Browser Download API")

RUN_USER = os.environ.get("BROWSER_USER", "user")
RUN_HOME = Path(os.environ.get("BROWSER_HOME", f"/home/{RUN_USER}"))
DOWNLOAD_DIR = Path(
    os.environ.get("DOWNLOAD_DIR", str(RUN_HOME / "Downloads"))
)
PROFILE_DIR = Path(
    os.environ.get(
        "CHROMIUM_PROFILE",
        f"/tmp/chromium-{RUN_USER}-download-profile",
    )
)
CHROMIUM_BIN = os.environ.get("CHROMIUM_BIN", "chromium")
DISPLAY = os.environ.get("DISPLAY", ":1")

state = {}


def safe_filename(value: str) -> str:
    value = os.path.basename(unquote(value)).strip()
    if not value or value in {".", ".."}:
        raise ValueError("invalid filename")
    return value


def filename_from_url(url: str) -> str:
    path_name = Path(urlparse(url).path).name
    try:
        return safe_filename(path_name or "downloaded-file")
    except ValueError:
        return "downloaded-file"


def prepare_profile() -> None:
    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)

    preferences = {
        "download": {
            "default_directory": str(DOWNLOAD_DIR),
            "prompt_for_download": False,
            "directory_upgrade": True,
        },
        "safebrowsing": {
            "enabled": True,
        },
    }

    default_dir = PROFILE_DIR / "Default"
    default_dir.mkdir(parents=True, exist_ok=True)
    (default_dir / "Preferences").write_text(
        json.dumps(preferences),
        encoding="utf-8",
    )

    os.chown(DOWNLOAD_DIR, os.getuid(), os.getgid())
    os.chown(PROFILE_DIR, os.getuid(), os.getgid())


def start_browser(url: str, filename: str) -> int:
    prepare_profile()

    command = [
        CHROMIUM_BIN,
        f"--display={DISPLAY}",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--disable-gpu",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-features=Translate",
        f"--user-data-dir={PROFILE_DIR}",
        "--start-maximized",
        url,
    ]

    process = subprocess.Popen(
        command,
        cwd=str(RUN_HOME),
        env={**os.environ, "HOME": str(RUN_HOME)},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    state[filename] = {
        "status": "browser_started",
        "pid": process.pid,
        "url": url,
        "started": int(time.time()),
    }

    return process.pid


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/api/check")
def check(filename: str = Query(...)):
    try:
        filename = safe_filename(filename)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid filename")

    path = DOWNLOAD_DIR / filename
    state_data = state.get(filename, {})

    if path.is_file() and path.stat().st_size > 0:
        return {
            "filename": filename,
            "exists": True,
            "status": "ready",
            "size": path.stat().st_size,
            "path": str(path),
        }

    return {
        "filename": filename,
        "exists": False,
        "status": state_data.get("status", "not_found"),
        **{
            key: state_data[key]
            for key in ("pid", "url", "started")
            if key in state_data
        },
        "download_dir": str(DOWNLOAD_DIR),
    }


@app.get("/api/download")
def download(url: str = Query(...)):
    if not url.startswith(("http://", "https://")):
        raise HTTPException(
            status_code=400,
            detail="url must start with http:// or https://",
        )

    filename = filename_from_url(url)
    pid = start_browser(url, filename)

    return JSONResponse(
        {
            "ok": True,
            "filename": filename,
            "status": "browser_started",
            "pid": pid,
            "download_dir": str(DOWNLOAD_DIR),
        }
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=6081,
    )
