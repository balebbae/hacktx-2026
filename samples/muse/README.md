# Muse features for Familiar

Both experiments live here, outside Caleb's iOS app. They share the repository-root `.env`,
use Python 3.10+ with no third-party packages, and save results under ignored `output/`.

| Feature | Entry point | Input → output | Voice-agent integration point |
| --- | --- | --- | --- |
| Contact context | `instagram.py` | Public handle → Apify data → Muse Spark contact card | `fetch_profile(...)`, then `summarize_profile(...)`; speak `card.spoken_summary` |
| Express an idea visually | `image.py` | User's words → Muse Image → PNG | `generate_image(prompt)` returns PNG bytes to display |
| Swift image reference | `image.swift` | Same text-to-image experiment in Swift | `MuseImageClient.generate(prompt:)`; standalone, not in the app target |

These are separate callable features in one handoff folder, not a voice agent or server yet.
The image feature visualizes what the user **chooses to describe**; it does not infer their thoughts.
Keep generated images user-controlled: show them after an explicit request, never auto-post or send them.

## Setup and test

In your repository-root `.env` (never commit it):

```dotenv
META_API_KEY=your_meta_key
APIFY_API_TOKEN=your_apify_token
```

`META_API_KEY` is used by both features; `APIFY_API_TOKEN` is only for Instagram.
From the repository root, on Windows:

```powershell
py -3 samples/muse/instagram.py --username sahasyy
py -3 samples/muse/image.py "A glowing tree with music notes instead of leaves"
py -3 -m unittest discover -s samples/muse -v
```

On macOS/Linux, replace `py -3` with `python3`.
For the existing Windows setup, `samples/muse-instagram/.venv/Scripts/python.exe` still works
as the interpreter instead of `py -3`; the old folder now holds ignored local runtime/credential data only.

Instagram caches its contact card; add `--refresh` for a new paid lookup, or `--scrape-only` to skip Muse.
Image generation calls the API each time and replaces `output/muse-image-output.png`; copy any image you
want to keep before generating another. It currently accepts text, not microphone audio.
The cached Instagram card and generated images are **not included in Git**; Caleb runs his own test with keys.

For the Swift reference, from the repository root on a Mac:

```sh
swiftc -parse-as-library samples/muse/image.swift -o /tmp/muse-image-skeleton
/tmp/muse-image-skeleton "A glowing tree with music notes instead of leaves"
```

## Handoff boundaries

- Route an explicit voice request to the appropriate function after transcription; no always-running listener is added here.
- Keep provider keys on a trusted backend for a shipped app. The Swift file's direct-key approach is a local prototype only.
- Instagram uses a third-party Apify scrape, not Meta's official Instagram API. It sends selected text to Muse Spark; no image analysis.
- Muse Image receives the user's text prompt and returns an image. No camera frames, faces, or embeddings are uploaded.
- These optional cloud experiments are not part of the app's current local-only storage guarantees. Confirm data handling before integrating.
- Python tests mock providers and do not spend API credits. Swift requires a separate Mac build check.

See [Instagram details](INSTAGRAM.md) for caching, data flow, limits, and source references.
