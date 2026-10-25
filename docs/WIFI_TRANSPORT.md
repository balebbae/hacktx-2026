# Glasses video transport: Bluetooth Classic now, Wi-Fi as a fallback

The Meta Wearables Device Access Toolkit (DAT 1.0.1) can move the glasses camera stream
over two links. Familiar ships with **Bluetooth Classic only**. This note says why, and
exactly what to flip if we ever need Wi-Fi.

## What we use: Bluetooth Classic

Selected by `Familiar/Info.plist`:

- `UISupportedExternalAccessoryProtocols` = `com.meta.ar.wearable`
- `UIBackgroundModes` includes `external-accessory` (plus `bluetooth-central`,
  `bluetooth-peripheral`, `processing`, `audio`)
- `NSBluetoothAlwaysUsageDescription`

Stream config: HEVC (`.hvc1`), `.medium` resolution, 24 fps. HEVC rather than `.raw`
because raw frames are foreground-only; HEVC keeps streaming when the phone is locked
or the app is in the background, which is the normal state for a blind user.

Why Classic:

- The glasses stay a Bluetooth audio device at the same time, so TTS cues play through
  the glasses speakers over A2DP while the camera streams. That is the whole point of
  the product.
- No Wi-Fi join step, no extra permission prompts, no local-network dialog.

Known costs (measured by Meta, confirm on hardware and record in `docs/CALIBRATION.md`):

- First frame arrives up to ~12 s after the SDK reports `streaming`. The UI says
  "Waiting for frames" until a decoded frame lands.
- Lower bitrate than Wi-Fi; medium resolution at 24 fps is the practical ceiling.
- The Classic transport leaks roughly 4 MB/min inside the SDK. Restart the app before
  a long demo block.
- The glasses mic over the stream is not beamformed and runs ~200 ms behind video,
  which is why the default audio path is the phone mic (`GlassesFrameSource.Options.streamAudio`
  is a dev-only toggle).

## The fallback: Wi-Fi

Wi-Fi gives higher bitrate and resolution (`.high`), but the glasses then drop their
Bluetooth audio role: **app audio to the glasses is muted while a Wi-Fi stream runs.**
Cues would have to come out of the phone speaker. That is acceptable for a
video-quality demo at a table, not for the wearer walking around.

To enable Wi-Fi transport (not done in this repo):

1. `Familiar/Info.plist`
   - `NSLocalNetworkUsageDescription` — already present (harmless without the rest).
   - `NSBonjourServices` = `["_bonjour._tcp"]` — **not present on purpose**. Adding it
     is what makes the SDK consider the Wi-Fi link.
2. Entitlements: add the Hotspot Configuration capability
   (`com.apple.developer.networking.HotspotConfiguration`) to the app target so the SDK
   can join the glasses' network. Requires a paid developer team and a provisioning
   profile that includes it.
3. Expect a one-time iOS "Familiar would like to find and connect to devices on your
   local network" prompt and a Wi-Fi join prompt on first use.
4. Audio: route TTS to the phone speaker while `GlassesFrameSource.isStreaming` is true
   (the `GlassesStreamCoordinator` protocol exposes exactly this so S5/S3 can switch).

The SDK picks the link itself from what Info.plist declares; there is no code switch.
Removing `NSBonjourServices` and the entitlement returns the app to Classic.

## Verification checklist on real glasses

- Meta AI app: Developer Mode on, glasses paired and updated.
- Familiar → Glasses → Connect glasses → approve in Meta AI → "Connected".
- Start streaming → "Waiting for frames" → "Streaming" with fps shown within ~15 s.
- Play any cue: it should come from the glasses, not the phone.
- Fold the glasses: the screen shows "Stopped: Glasses folded".
- Record first-frame delay, fps, and whether audio was audible in `docs/CALIBRATION.md`.
