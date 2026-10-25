"""Familiar: Modal fallback for the on-device w600k_mbf face embedder.

Runs the same InsightFace buffalo_sc pack (det_500m detector + w600k_mbf
recogniser) as the phone. Crops are decoded in memory and discarded; nothing is
stored and nothing is logged beyond request timing.

Deploy:   modal deploy modal/embed_server.py
Endpoints (one URL per method, see modal/README.md):
  POST embed        aligned 112x112 JPEG -> 512-float embedding (what the phone calls)
  POST embed_full   any image -> detection + alignment + embedding (the oracle for S2)
  GET  health       {"ok": true, "model": "w600k_mbf"}

All three require Modal proxy auth (headers Modal-Key / Modal-Secret).
A fourth, GET health_public, has NO auth and exists only so a human can confirm the
service is up from a browser; it carries no data.

Local verification only: `FAMILIAR_OPEN_ENDPOINTS=1 modal serve modal/embed_server.py`
serves an ephemeral copy with proxy auth switched off (never deploy that way).
Keep min_containers=0 in git; bump to 1 only during judging (see README).
"""

import os

import modal

MODEL_ID = "w600k_mbf"
PACK = "buffalo_sc"
MODEL_DIR = f"/root/.insightface/models/{PACK}"
REQUIRE_PROXY_AUTH = os.environ.get("FAMILIAR_OPEN_ENDPOINTS") != "1"

app = modal.App("familiar-embed")

image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install("build-essential", "libgl1", "libglib2.0-0")
    .pip_install(
        "fastapi[standard]==0.115.12",
        "onnxruntime==1.20.1",
        "numpy<2",
        "opencv-python-headless==4.10.0.84",
        "insightface==0.7.3",
    )
    # Download the buffalo_sc pack at image build time so cold starts never fetch it.
    .run_commands(
        "python -c \"from insightface.app import FaceAnalysis; "
        f"FaceAnalysis(name='{PACK}', providers=['CPUExecutionProvider']).prepare(ctx_id=-1)\"",
        f"ls -la {MODEL_DIR} && test -f {MODEL_DIR}/{MODEL_ID}.onnx",
    )
)


def _decode(item: dict):
    """Base64 (optionally a data: URL) -> BGR uint8 image, or None."""
    import base64

    import cv2
    import numpy as np

    b64 = item.get("image_b64") or ""
    if "," in b64 and b64.lstrip().startswith("data:"):
        b64 = b64.split(",", 1)[1]
    try:
        buf = np.frombuffer(base64.b64decode(b64, validate=False), np.uint8)
    except Exception:
        return None
    return cv2.imdecode(buf, cv2.IMREAD_COLOR)


@app.cls(image=image, cpu=2.0, memory=2048, scaledown_window=300, min_containers=0)
class Embedder:
    @modal.enter()
    def load(self):
        import onnxruntime as ort
        from insightface.app import FaceAnalysis

        self.fa = FaceAnalysis(name=PACK, root="/root/.insightface", providers=["CPUExecutionProvider"])
        self.fa.prepare(ctx_id=-1, det_size=(640, 640))
        self.sess = ort.InferenceSession(f"{MODEL_DIR}/{MODEL_ID}.onnx", providers=["CPUExecutionProvider"])
        self.input_name = self.sess.get_inputs()[0].name
        # warm the recogniser once so the first real request is not the slow one
        import numpy as np

        self.sess.run(None, {self.input_name: np.zeros((1, 3, 112, 112), np.float32)})

    def _embed_aligned(self, bgr112):
        import cv2
        import numpy as np

        rgb = cv2.cvtColor(bgr112, cv2.COLOR_BGR2RGB).astype(np.float32)
        x = ((rgb - 127.5) / 127.5).transpose(2, 0, 1)[None]
        v = self.sess.run(None, {self.input_name: x})[0][0]
        return (v / np.linalg.norm(v)).tolist()

    @modal.fastapi_endpoint(method="POST", requires_proxy_auth=REQUIRE_PROXY_AUTH)
    def embed(self, item: dict):
        """Aligned 112x112 face crop -> embedding (what the phone calls)."""
        import time

        import cv2

        t0 = time.perf_counter()
        img = _decode(item)
        if img is None:
            return {"error": "bad image"}
        if img.shape[:2] != (112, 112):
            img = cv2.resize(img, (112, 112))
        vec = self._embed_aligned(img)
        ms = (time.perf_counter() - t0) * 1000
        print(f"embed {ms:.1f} ms")
        return {"embedding": vec, "model": MODEL_ID, "dim": len(vec), "ms": round(ms, 1)}

    @modal.fastapi_endpoint(method="POST", requires_proxy_auth=REQUIRE_PROXY_AUTH)
    def embed_full(self, item: dict):
        """Unaligned image -> InsightFace detection + alignment + embedding (the oracle for S2)."""
        import time

        t0 = time.perf_counter()
        img = _decode(item)
        if img is None:
            return {"error": "bad image"}
        faces = self.fa.get(img)
        out = []
        for f in faces:
            face = {
                "bbox": f.bbox.tolist(),
                "kps": f.kps.tolist(),
                "det_score": float(f.det_score),
                "embedding": f.normed_embedding.tolist(),
            }
            if item.get("return_aligned"):
                # the exact 112x112 crop InsightFace embedded, so S2 can diff its FaceAligner
                import base64

                import cv2
                from insightface.utils.face_align import norm_crop

                ok, jpg = cv2.imencode(".jpg", norm_crop(img, f.kps), [cv2.IMWRITE_JPEG_QUALITY, 95])
                face["aligned_b64"] = base64.b64encode(jpg.tobytes()).decode() if ok else None
            out.append(face)
        ms = (time.perf_counter() - t0) * 1000
        print(f"embed_full {ms:.1f} ms faces={len(faces)}")
        return {"faces": out, "model": MODEL_ID, "ms": round(ms, 1)}

    @modal.fastapi_endpoint(method="GET", requires_proxy_auth=REQUIRE_PROXY_AUTH)
    def health(self):
        return {"ok": True, "model": MODEL_ID}

    @modal.fastapi_endpoint(method="GET", requires_proxy_auth=False)
    def health_public(self):
        """UNAUTHENTICATED liveness check for humans without proxy-auth tokens. Returns no data."""
        return {"ok": True, "model": MODEL_ID, "auth": "none", "note": "liveness only; embed/embed_full/health need Modal-Key/Modal-Secret"}
