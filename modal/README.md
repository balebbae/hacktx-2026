# modal/ — Familiar embedding fallback (S9)

A tiny HTTPS service on [Modal](https://modal.com) that runs the same InsightFace `buffalo_sc` pack as the phone: `det_500m` detector and the `w600k_mbf` (MobileFaceNet, 512-d) recogniser. It exists so the demo cannot be blocked by on-device inference problems, and so S2 can check that the phone's alignment and preprocessing match InsightFace (same crop, cosine > 0.99).

No storage. Crops are decoded in memory and discarded. The only log line per request is its timing.

## Endpoints (workspace `balebbae`, app `familiar-embed`)

| Method | URL | Auth | Purpose |
| --- | --- | --- | --- |
| POST | `https://balebbae--familiar-embed-embedder-embed.us-east.modal.run` | proxy auth | aligned 112x112 JPEG -> 512 floats. What the phone calls. |
| POST | `https://balebbae--familiar-embed-embedder-embed-full.us-east.modal.run` | proxy auth | any image -> detect + align + embed each face. The oracle for S2 and `check_pairs.py`. |
| GET | `https://balebbae--familiar-embed-embedder-health.us-east.modal.run` | proxy auth | `{"ok": true, "model": "w600k_mbf"}` |
| GET | `https://balebbae--familiar-embed-embedder-health-public.us-east.modal.run` | none | liveness only, so a human can open it in a browser without tokens. Carries no data. |

Request / response:

```
POST embed        {"image_b64": "<base64 JPEG/PNG, 112x112; anything else is resized>"}
                  -> {"embedding": [512 floats, L2-normalised], "model": "w600k_mbf", "dim": 512, "ms": 10.7}
POST embed_full   {"image_b64": "<base64 JPEG/PNG>", "return_aligned": false}
                  -> {"faces": [{"bbox": [x1,y1,x2,y2], "kps": [[x,y] x5], "det_score": 0.84,
                                 "embedding": [512 floats], "aligned_b64": "<112x112 JPEG, only if return_aligned>"}],
                      "model": "w600k_mbf", "ms": 31.0}
GET  health       -> {"ok": true, "model": "w600k_mbf"}
```

Preprocessing inside `embed` (the phone's `OnDeviceEmbedder` must do the same): BGR -> RGB, `(x - 127.5) / 127.5`, NCHW `1x3x112x112` float32, output L2-normalised.

## Proxy auth (what a human must do once)

The three real endpoints are deployed with `requires_proxy_auth=True`; Modal rejects any request that does not carry a valid token pair with `401 modal-http: missing credentials for proxy authorization`. Devin cannot log into the Modal dashboard, so a human creates the token pair:

1. Open https://modal.com/settings/proxy-auth-tokens (dashboard -> **Settings** -> **Proxy Auth Tokens**; make sure the `balebbae` workspace is selected at the top left).
2. Click **New Token**, give it a name like `familiar-ios`, copy the **Token ID** and **Token Secret** (the secret is shown once).
3. Put them in the app's `Secrets.xcconfig` (never committed):
   ```
   MODAL_EMBED_URL = https:/$()/balebbae--familiar-embed-embedder-embed.us-east.modal.run
   MODAL_KEY = wk-...
   MODAL_SECRET = ws-...
   ```
   (`$()` keeps xcconfig from treating `//` as a comment.)
4. The phone sends them as headers `Modal-Key: $MODAL_KEY` and `Modal-Secret: $MODAL_SECRET`.

Revoking a token in the same page cuts the phone off instantly; nothing needs redeploying.

## Deploy

```bash
python3.12 -m venv .venv && . .venv/bin/activate
pip install -r modal/requirements.txt
modal token set --token-id "$MODAL_TOKEN_ID" --token-secret "$MODAL_TOKEN_SECRET"   # or export both vars
modal deploy modal/embed_server.py
```

The first deploy builds the image (about 80 s): it apt-installs a compiler for the `insightface` wheel, pins `onnxruntime 1.20.1`, `numpy<2`, `opencv-python-headless 4.10`, `insightface 0.7.3`, and downloads `buffalo_sc.zip` into `/root/.insightface/models/buffalo_sc/` **at build time**, so a cold container never fetches the model. Later deploys reuse the cached image and take about 2 s.

## Verify with curl

```bash
export MODAL_KEY=wk-... MODAL_SECRET=ws-...
H='-H Modal-Key:'"$MODAL_KEY"' -H Modal-Secret:'"$MODAL_SECRET"

curl -s $H https://balebbae--familiar-embed-embedder-health.us-east.modal.run
# {"ok":true,"model":"w600k_mbf"}

curl -s -X POST $H -H "Content-Type: application/json" \
  -d "{\"image_b64\": \"$(base64 -i modal/testdata/aligned112.jpg)\"}" \
  https://balebbae--familiar-embed-embedder-embed.us-east.modal.run | head -c 300
# {"embedding":[0.0340227335691452,-0.03441357985138893,-0.0013132450403645635,...

# no tokens needed:
curl -s https://balebbae--familiar-embed-embedder-health-public.us-east.modal.run
```

Measured from a laptop with the container warm: `embed` round-trip 330-400 ms, of which about 11 ms is inference (`"ms"` in the response); `embed_full` on a 1024 px photo about 30 ms server side. A cold start (container boot + ONNX session load, model already in the image) is 5-10 s.

## Pair check

`check_pairs.py` sends two photos through `embed_full`, takes the largest face in each, and prints the cosine similarity. Photos are downscaled to 1024 px in memory before upload.

```bash
export MODAL_KEY=... MODAL_SECRET=...        # optional; omit when pointing --url at an open dev server
python modal/check_pairs.py a.jpg b.jpg      # same person   -> expect > 0.5
python modal/check_pairs.py a.jpg c.jpg      # different     -> expect < 0.3
```

Fixture frames, once `Familiar/Resources/Fixtures/*.mp4` exist:

```bash
ffmpeg -ss 3 -i Familiar/Resources/Fixtures/enroll_marcus.mp4   -frames:v 1 /tmp/a.jpg
ffmpeg -ss 3 -i Familiar/Resources/Fixtures/approach_marcus.mp4 -frames:v 1 /tmp/b.jpg
ffmpeg -ss 3 -i Familiar/Resources/Fixtures/strangers.mp4       -frames:v 1 /tmp/c.jpg
```

## Test vector for the on-device embedder (S2)

`testdata/aligned112.jpg` is an aligned 112x112 crop produced by InsightFace's `norm_crop` (via `embed_full` with `return_aligned`), and `testdata/aligned112_embedding.json` is what the deployed `embed` returned for exactly those JPEG bytes. Feed the JPEG to `OnDeviceEmbedder` and require cosine > 0.99 against `embedding`. Regenerate with

```bash
python modal/export_test_vector.py some_aligned_112.jpg          # or
python modal/export_test_vector.py --from-photo some_photo.jpg   # server detects + aligns the largest face
```

## Local verification without proxy-auth tokens

`FAMILIAR_OPEN_ENDPOINTS=1 modal serve modal/embed_server.py` serves an ephemeral copy (`*-dev.us-east.modal.run` URLs) with proxy auth switched off, for curl and the scripts above. It dies when you Ctrl-C. Never `modal deploy` with that variable set.

## Cost and capacity

- CPU-only container (2 vCPU, 2 GiB). Modal bills per second of container time; `min_containers=0` means the bill is zero while idle, and `scaledown_window=300` keeps a container alive for 5 minutes after the last request.
- Cold start is 5-10 s. The phone falls back to on-device embedding, so a cold start only delays the fallback path.
- For judging only: edit the decorator to `min_containers=1`, run `modal deploy modal/embed_server.py` (2 s), and the container stays warm the whole time (about $0.10-0.20 per hour on Modal's CPU pricing). Set it back to `min_containers=0` and deploy again afterwards. The committed code keeps `min_containers=0`.
- Each request is tiny (a 112x112 JPEG is 5-10 KB), so bandwidth is negligible.
