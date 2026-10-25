# Devin session S9 — Modal embedding endpoint (branch `feat/modal`; starts once S1 is on `main`; Python only, runs on any platform)

Read `AGENTS.md`. You own `modal/`. Humans provide a Modal token (`modal token set --token-id … --token-secret …`, or `MODAL_TOKEN_ID` / `MODAL_TOKEN_SECRET` in the Devin secrets). Time budget: 90 minutes.

## Goal
A tiny HTTPS endpoint that runs the **same** InsightFace `w600k_mbf` model as the phone, so (a) the demo cannot be blocked by on-device inference problems and (b) S2 can verify its alignment and preprocessing (the same crop must give cosine > 0.99 against the phone). No storage: crops are processed in memory and discarded; nothing is logged beyond request timing.

## `modal/embed_server.py`
```python
import modal

app = modal.App("familiar-embed")
image = (modal.Image.debian_slim(python_version="3.12")
         .pip_install("fastapi[standard]", "onnxruntime", "numpy", "opencv-python-headless", "insightface")
         # download the buffalo_sc pack at build time so cold starts do not fetch it
         .run_commands("python -c \"from insightface.app import FaceAnalysis; FaceAnalysis(name='buffalo_sc', providers=['CPUExecutionProvider']).prepare(ctx_id=-1)\""))

@app.cls(image=image, cpu=2.0, memory=2048, scaledown_window=300, min_containers=0)
class Embedder:
    @modal.enter()
    def load(self):
        import glob, os, onnxruntime as ort
        from insightface.app import FaceAnalysis
        self.fa = FaceAnalysis(name="buffalo_sc", providers=["CPUExecutionProvider"])   # detector + recognizer, for embed_full
        self.fa.prepare(ctx_id=-1, det_size=(640, 640))
        path = glob.glob(os.path.expanduser("~/.insightface/models/buffalo_sc/w600k_mbf.onnx"))[0]
        self.sess = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
        self.input_name = self.sess.get_inputs()[0].name

    def _embed_aligned(self, bgr112):
        import numpy as np, cv2
        rgb = cv2.cvtColor(bgr112, cv2.COLOR_BGR2RGB).astype(np.float32)
        x = ((rgb - 127.5) / 127.5).transpose(2, 0, 1)[None]
        v = self.sess.run(None, {self.input_name: x})[0][0]
        return (v / np.linalg.norm(v)).tolist()

    @modal.fastapi_endpoint(method="POST", requires_proxy_auth=True)
    def embed(self, item: dict):
        """Aligned 112×112 face crop → embedding (what the phone calls)."""
        import base64, numpy as np, cv2
        img = cv2.imdecode(np.frombuffer(base64.b64decode(item["image_b64"]), np.uint8), cv2.IMREAD_COLOR)
        if img is None:
            return {"error": "bad image"}
        if img.shape[:2] != (112, 112):
            img = cv2.resize(img, (112, 112))
        return {"embedding": self._embed_aligned(img), "model": "w600k_mbf", "dim": 512}

    @modal.fastapi_endpoint(method="POST", requires_proxy_auth=True)
    def embed_full(self, item: dict):
        """Unaligned image → InsightFace detection + alignment + embedding (the oracle for S2)."""
        import base64, numpy as np, cv2
        img = cv2.imdecode(np.frombuffer(base64.b64decode(item["image_b64"]), np.uint8), cv2.IMREAD_COLOR)
        faces = self.fa.get(img) if img is not None else []
        return {"faces": [{"bbox": f.bbox.tolist(), "kps": f.kps.tolist(), "embedding": f.normed_embedding.tolist()} for f in faces],
                "model": "w600k_mbf"}

    @modal.fastapi_endpoint(method="GET", requires_proxy_auth=True)
    def health(self):
        return {"ok": True, "model": "w600k_mbf"}
```
Adjust the build-time download to whatever the installed `insightface` version supports (the `FaceAnalysis(...).prepare()` call downloads the pack to `~/.insightface/models/buffalo_sc/`); if `FaceAnalysis` insists on a GPU provider, keep `providers=["CPUExecutionProvider"]`. CPU is enough for MobileFaceNet (tens of ms).

## Deploy and verify
`modal deploy modal/embed_server.py` → endpoint URLs like `https://<workspace>--familiar-embed-embedder-embed.modal.run` (one per endpoint). Create proxy-auth tokens in the Modal dashboard → `MODAL_KEY` / `MODAL_SECRET`. Verify:
```bash
curl -s -H "Modal-Key: $MODAL_KEY" -H "Modal-Secret: $MODAL_SECRET" "$HEALTH_URL"
curl -s -X POST -H "Modal-Key: $MODAL_KEY" -H "Modal-Secret: $MODAL_SECRET" -H "Content-Type: application/json" \
  -d "{\"image_b64\": \"$(base64 -i aligned112.jpg)\"}" "$EMBED_URL" | head -c 300
```
Add `modal/check_pairs.py` (two image paths → cosine similarity through `embed_full`) and `modal/README.md`: deploy steps, the three URLs, cost notes (CPU container; cold start 5–15 s; set `min_containers=1` only during judging with `modal deploy` after editing the decorator, back to 0 afterwards), the curl commands, and the pair check.

## Acceptance
`health` returns the model id; `embed` returns 512 floats in < 400 ms warm; on two fixture frames of the same person `check_pairs.py` reports > 0.5 and on two different people < 0.3. Paste the outputs into the PR along with the URLs (not the secrets).
