#!/usr/bin/env python3
"""Cosine similarity between the faces in two images, through the deployed embed_full endpoint.

    python modal/check_pairs.py a.jpg b.jpg [--url URL] [--max-side 1024]

Reads MODAL_EMBED_FULL_URL (or --url) and, when set, MODAL_KEY / MODAL_SECRET for proxy
auth. Images are downscaled in memory before upload; nothing is written anywhere.
Acceptance: same person > 0.5, different people < 0.3.
"""

import argparse
import base64
import io
import json
import math
import os
import sys
import time
import urllib.request

DEFAULT_URL = "https://balebbae--familiar-embed-embedder-embed-full.us-east.modal.run"


def auth_headers():
    h = {"Content-Type": "application/json"}
    key, secret = os.environ.get("MODAL_KEY"), os.environ.get("MODAL_SECRET")
    if key and secret:
        h["Modal-Key"], h["Modal-Secret"] = key, secret
    return h


def image_b64(path, max_side):
    from PIL import Image, ImageOps

    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    im.thumbnail((max_side, max_side))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=92)
    return base64.b64encode(buf.getvalue()).decode(), im.size


def post(url, payload, timeout=120):
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=auth_headers(), method="POST")
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = json.loads(r.read())
    return body, (time.perf_counter() - t0) * 1000


def best_face(resp):
    faces = resp.get("faces") or []
    if not faces:
        return None
    return max(faces, key=lambda f: (f["bbox"][2] - f["bbox"][0]) * (f["bbox"][3] - f["bbox"][1]))


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    return dot / (math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--url", default=os.environ.get("MODAL_EMBED_FULL_URL", DEFAULT_URL))
    ap.add_argument("--max-side", type=int, default=1024, help="downscale longest side before upload")
    args = ap.parse_args()

    embs = []
    for path in (args.a, args.b):
        b64, size = image_b64(path, args.max_side)
        resp, ms = post(args.url, {"image_b64": b64})
        if "error" in resp:
            sys.exit(f"{path}: server error: {resp['error']}")
        face = best_face(resp)
        if face is None:
            sys.exit(f"{path}: no face detected")
        print(f"{path}: {size[0]}x{size[1]} -> {len(resp['faces'])} face(s), det {face['det_score']:.3f}, "
              f"round-trip {ms:.0f} ms (server {resp.get('ms', '?')} ms)")
        embs.append(face["embedding"])

    sim = cosine(*embs)
    verdict = "same person (> 0.5)" if sim > 0.5 else "different people (< 0.3)" if sim < 0.3 else "ambiguous (0.3-0.5)"
    print(f"cosine({os.path.basename(args.a)}, {os.path.basename(args.b)}) = {sim:.4f}  -> {verdict}")


if __name__ == "__main__":
    main()
