# Calibration (do this at the real table, both phones)

## Recognition threshold T (Settings → Embedding → threshold slider, default 0.40, margin 0.08)
1. Enroll a teammate through the consent flow.
2. Open the Judge view: every box shows the live best cosine score. The enrolled person should sit well above T at 1–2 m (expect 0.55–0.75); every stranger should sit below T − 0.08 (expect < 0.30).
3. Move T to the midpoint of the gap. Mistaken identity is worse than no identity: when in doubt, raise T.
4. The fixture test log (`PerceptionFixtureTests`) prints the same-person and different-person cosine distributions for the clips.

## Distance bins (Settings → Embedding → distance thresholds, default close < 1.5 m, medium 1.5–3 m, far > 3 m)
Put tape marks at 1 m, 2 m, 3 m. A teammate stands on each for 3 s; read the face height in px from the Judge view and adjust the bin thresholds (or the assumed 0.20 m face height) until the spoken distance matches. The formula is `distance = 0.20 / (2 · tan((faceHeightPx / frameHeightPx) · vFOV / 2))`.

## Field of view
Phone camera: computed from `activeFormat.videoFieldOfView` (portrait hFOV ≈ 2·atan(tan(vFOV/2)·W/H)). Glasses stream: defaults hFOV 53°, vFOV 85° (504×896 portrait). To measure: stand a person at a known angle (e.g. 20° right, 2 m away → 0.73 m to the right of centre) and check that the Judge view reports ≈ 20°; adjust the FOV in Settings until it does. Record the result here:

| Source | hFOV | vFOV | fps | first frame | audio on glasses during stream |
|---|---|---|---|---|---|
| Phone camera | | | | | n/a |
| Glasses (Classic) | | | | | |

## Loudness split (Settings → Audio → Calibrate my voice)
The wearer reads one sentence; speech above 0.6 × that RMS is tagged `user`, the rest `other`. Re-run if the room gets louder; the consent question only uses names from `other`-attributed speech.
