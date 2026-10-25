#!/usr/bin/env python3
"""Write a reference vector for the on-device embedder (S2).

    python modal/export_test_vector.py aligned112.jpg            # already-aligned 112x112 crop
    python modal/export_test_vector.py --from-photo photo.jpg    # let InsightFace detect + align first

Outputs modal/testdata/aligned112.jpg (the exact bytes that were embedded) and
modal/testdata/aligned112_embedding.json ({"model","dim","embedding","source"}).
The iOS OnDeviceEmbedder must give cosine > 0.99 against that embedding for that JPEG.

Uses MODAL_EMBED_URL / MODAL_EMBED_FULL_URL (or --embed-url / --embed-full-url) and
MODAL_KEY / MODAL_SECRET when set.
"""

import argparse
import base64
import io
import json
import os
import sys

from check_pairs import DEFAULT_URL as DEFAULT_FULL_URL
from check_pairs import best_face, image_b64, post

DEFAULT_EMBED_URL = "https://balebbae--familiar-embed-embedder-embed.us-east.modal.run"
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "testdata")


def aligned_bytes_from_file(path):
    from PIL import Image

    im = Image.open(path)
    if im.size != (112, 112):
        sys.exit(f"{path} is {im.size[0]}x{im.size[1]}, expected an aligned 112x112 crop (or use --from-photo)")
    with open(path, "rb") as f:
        return f.read()


def aligned_bytes_from_photo(path, url):
    b64, _ = image_b64(path, 1024)
    resp, _ = post(url, {"image_b64": b64, "return_aligned": True})
    face = best_face(resp)
    if face is None or not face.get("aligned_b64"):
        sys.exit(f"{path}: no face detected")
    return base64.b64decode(face["aligned_b64"])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("aligned", nargs="?", help="aligned 112x112 JPEG")
    ap.add_argument("--from-photo", help="unaligned photo; the server detects and aligns the largest face")
    ap.add_argument("--embed-url", default=os.environ.get("MODAL_EMBED_URL", DEFAULT_EMBED_URL))
    ap.add_argument("--embed-full-url", default=os.environ.get("MODAL_EMBED_FULL_URL", DEFAULT_FULL_URL))
    args = ap.parse_args()
    if bool(args.aligned) == bool(args.from_photo):
        ap.error("give exactly one of: aligned112.jpg or --from-photo photo.jpg")

    if args.aligned:
        jpg, source = aligned_bytes_from_file(args.aligned), os.path.basename(args.aligned)
    else:
        jpg, source = aligned_bytes_from_photo(args.from_photo, args.embed_full_url), f"embed_full(return_aligned) of {os.path.basename(args.from_photo)}"

    resp, ms = post(args.embed_url, {"image_b64": base64.b64encode(jpg).decode()})
    if "error" in resp:
        sys.exit(f"server error: {resp['error']}")
    vec = resp["embedding"]

    os.makedirs(OUT_DIR, exist_ok=True)
    jpg_path = os.path.join(OUT_DIR, "aligned112.jpg")
    json_path = os.path.join(OUT_DIR, "aligned112_embedding.json")
    with open(jpg_path, "wb") as f:
        f.write(jpg)
    with open(json_path, "w") as f:
        json.dump({"model": resp["model"], "dim": len(vec), "source": source,
                   "preprocess": "RGB, (x-127.5)/127.5, NCHW, L2-normalised output",
                   "embedding": vec}, f)
        f.write("\n")
    print(f"wrote {jpg_path} ({len(jpg)} bytes) and {json_path} ({len(vec)} floats, {ms:.0f} ms)")
    print("embedding[:5] =", [round(x, 5) for x in vec[:5]])


if __name__ == "__main__":
    main()
