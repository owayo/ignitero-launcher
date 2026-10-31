"""Fetch verified build-time models. OCR itself has no Python dependency."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
import urllib.request
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    source = (
        Path(os.environ.get("OCRUS_SOURCE_DIR", root / "Native/ocrus"))
        .expanduser()
        .resolve()
    )
    destination = (
        Path(os.environ.get("OCRUS_MODEL_DIR", Path.home() / ".ocrus/models"))
        .expanduser()
        .resolve()
    )
    destination.mkdir(parents=True, exist_ok=True)
    if (destination / "rec.ocnn").is_file() and (destination / "dict.txt").is_file():
        print("Existing OCR model retained.")
        return
    lock = json.loads((root / "Resources/ocr-model.lock.json").read_text())
    # Never replace an existing, potentially customized model or dictionary.
    if any(
        (destination / name).exists() for name in ("rec.ocnn", "rec.onnx", "dict.txt")
    ):
        raise SystemExit("Incomplete model directory. Choose a new OCRUS_MODEL_DIR.")
    with tempfile.TemporaryDirectory(
        prefix="ocr-model-", dir=destination.parent
    ) as temporary:
        staging = Path(temporary)
        for name, expected in lock["files"].items():
            url = f"{lock['base_url']}{lock['revision']}/languages/chinese/{name}"
            print(f"Downloading {name}", flush=True)
            path = staging / name
            with (
                urllib.request.urlopen(url, timeout=120) as response,
                path.open("wb") as output,
            ):
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
            if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                raise SystemExit(f"Checksum mismatch for {name}")
        subprocess.run(
            [
                "mise",
                "exec",
                "--",
                "uv",
                "run",
                "--project",
                "scripts",
                "--extra",
                "convert",
                "python",
                "scripts/src/ocrus_scripts/convert_to_ocnn.py",
                str(staging / "rec.onnx"),
                "-o",
                str(staging / "rec.ocnn"),
                "--dtype",
                "f16",
            ],
            cwd=source,
            check=True,
        )
        for name in ("rec.onnx", "rec.ocnn", "dict.txt"):
            (staging / name).replace(destination / name)
    print("OCR model is ready.")


if __name__ == "__main__":
    main()
