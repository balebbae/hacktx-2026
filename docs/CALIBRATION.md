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

## Loudness split (Settings → You → Calibrate my voice)
The wearer talks normally for 3 s; speech above 0.6 × that RMS is tagged `user`, the rest `other` (the value is saved). Re-run if the room gets louder. It matters: the conversation trigger needs both `user` and `other` speech, the assistant answers `user` speech, and the suggested-remember flow only accepts the other person's `other`-attributed yes.

## Hazards (`HazardPolicy` in Familiar/Perception/SceneAwareness.swift)
Defaults were chosen without glasses footage; tune them on the iPhone with the Judge view event log (`scene hazard(...)` lines):
- Stairs / escalator / crosswalk: Vision label confidence ≥ 0.5 in 2 of the last 3 classifications (≈1 per second). Face a staircase from 2 m: one "Stairs ahead." within ~2 s, none for 8 s after. Lower `hazardConfidence` if it is missed, raise it if a flat hallway triggers it.
- Obstacle: optical-flow expansion in the centre of the view, time-to-contact < 1.2 s on 2 consecutive pairs (≈4 per second). Walk at normal pace toward a wall or a door: "Obstacle ahead." at about 1.5 m. Walk down an open hallway: nothing. Standing still while turning the head: nothing. Adjust `obstacleTimeToContact`.
