"""Standalone Muse Image proof of concept.

This does not import or modify Familiar. It is intentionally easy to copy into
another project while the iOS integration is being designed.

Usage:
    python samples/muse/image.py "a simple high-contrast illustration of a red fox"

The script reads META_API_KEY from the root .env file or the environment. It
writes the generated image to samples/muse/output/muse-image-output.png.
"""

from __future__ import annotations

import base64
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request


ENDPOINT = "https://api.meta.ai/v1/images/generations"
MODEL = "muse-image-1.0"


def load_dotenv_value(name: str) -> str | None:
    """Read one simple KEY=value entry from the repo-root .env file."""
    env_path = pathlib.Path(__file__).resolve().parents[2] / ".env"
    try:
        lines = env_path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() == name:
            return value.strip().strip("\"'")
    return None


def api_key() -> str:
    value = os.environ.get("META_API_KEY") or os.environ.get("MODEL_API_KEY")
    value = value or load_dotenv_value("META_API_KEY")
    if not value:
        raise RuntimeError("META_API_KEY was not found in .env or the environment")
    return value


def generate_image(prompt: str) -> bytes:
    prompt = prompt.strip()
    if not prompt:
        raise ValueError("The prompt is empty")

    body = {
        "model": MODEL,
        "prompt": prompt,
        "n": 1,
        "response_format": "b64_json",
        "output_format": "png",
    }
    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key()}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Muse Image returned HTTP {error.code}: {detail}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"Could not reach Muse Image: {error.reason}") from error

    entries = payload.get("data") or []
    if not entries or not entries[0].get("b64_json"):
        raise RuntimeError(f"Muse Image returned no image data: {payload}")
    return base64.b64decode(entries[0]["b64_json"])


def main() -> int:
    prompt = " ".join(sys.argv[1:])
    if not prompt:
        prompt = input("What should Muse Image draw? ").strip()

    print(f"Sending prompt to {MODEL}...")
    image_bytes = generate_image(prompt)
    output_path = pathlib.Path(__file__).resolve().parent / "output" / "muse-image-output.png"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(image_bytes)
    print(f"Saved {len(image_bytes):,} bytes to {output_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError) as error:
        print(f"Test failed: {error}", file=sys.stderr)
        raise SystemExit(1)
