# Instagram contact card experiment

Exact public handle → Apify profile scraper → Muse Spark → short spoken summary and sourced topics.
Standalone Python; **no iOS changes, Instagram login, cookies, following, or Accounts Center integration**.
Replaces the old unofficial-login/follow experiment. Uses Muse Spark's model API, not the personal Muse agent.

## Run

Keep `APIFY_API_TOKEN` and `META_API_KEY` in the repository root `.env` (or environment). Never commit keys.
Python 3.10+; no packages to install. From this folder:

```powershell
python instagram.py --username sahasyy
```

Saved under ignored `output/`:

- `sahasyy.profile.json`: selected bio, up to 12 post captions, supplied alt text, source links and fetch time.
- `sahasyy.card.json`: profile plus Muse's spoken summary, sourced topics, aesthetic if supported, and limitations.
- `sahasyy.run.json`: Apify run ID/status for resuming interrupted fetches.

Repeated commands replay the saved card without API calls. `--refresh` fetches fresh data and regenerates it;
`--scrape-only` fetches/prints profile data without Muse. Cached data is a dated snapshot, not a live guarantee
that the account remains public. Refresh before reusing old snapshots; remove local output when no longer wanted.
Each new scrape requests one profile, disables paid account-about enrichment, sets a 180-second run timeout,
and requests a $0.05 maximum Apify charge (Muse usage is separate). If starting the run times out before its
ID arrives, inspect Apify Runs before retrying to avoid duplicate charges. Recorded runs resume automatically;
a failed run requires an explicit `--refresh` to start again.

## Integration handoff

Use `fetch_profile(username, apify_token)` and `summarize_profile(profile, meta_key)` from a trusted backend.
The future app should attach the resulting card to an existing, consenting contact after confirming their
handle; speak `result["card"]["spoken_summary"]` when requested. Do not guess handles from faces or names.
Keep API keys on that backend, never inside a shipped mobile app. This CLI is a prototype, not a deployed endpoint.

Muse receives text only: bio, captions, and any provided image descriptions. It does not view the photos.
An aesthetic description is allowed only when alt text supports it; otherwise it is null. Alt text can be
automatically generated and wrong. The card describes posted content, not inferred personality or sensitive traits.
Source IDs map back to the profile's `sources` list; output still needs human review before a public demo.

Apify is a third-party scraper, **not Meta's official Instagram API**. Availability and completeness are not
guaranteed; private or unknown-privacy results are rejected. Apify receives the handle and stores its raw dataset
in your Apify account; the local sample keeps only selected fields and sends those to Meta. This is not a
local-only data flow. Delete cloud runs/datasets in Apify when no longer needed and review provider retention
before production. No email/phone extraction, comments, related-account traversal, or image downloads are added.

Legacy ignored `.env`, `.sessions/` (under the old `samples/muse-instagram/` folder), and OS credential-vault entries are not read or modified by this sample.
They may still contain old Instagram credentials/session material; remove them locally when no longer needed.
Old installed packages are unused; a fresh Python environment needs none.

```powershell
python -m unittest -v
```

References: [Apify actor](https://apify.com/apify/instagram-profile-scraper),
[published input schema](https://api.apify.com/v2/acts/apify~instagram-profile-scraper/builds/default/openapi.json),
[run API](https://docs.apify.com/api/v2/actors-runs-post).
