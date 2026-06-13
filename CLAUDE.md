# analog-simple

Analog watch face for the Garmin Venu 4, written in Monkey C against the
Connect IQ SDK. No tests; verification is "build it, then look at it in the
simulator".

## Devices

The Venu 4 product ids in the SDK are `venu445mm` (45mm) and `venu441mm`
(41mm / "4S"). There are **no** `venu4`/`venu4s` ids — don't "fix" the
manifest to use them.

## Build & run

The SDK lives under `~/Library/Application Support/Garmin/ConnectIQ/Sdks/`
(currently `connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b`). The signing key
is `/Users/yeled/Downloads/developer_key`.

```sh
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b"
KEY=/Users/yeled/Downloads/developer_key

# Device build for the simulator
java -Xms1g -Dapple.awt.UIElement=true -jar "$SDK/bin/monkeybrains.jar" \
  -o bin/analog-simple.prg -f monkey.jungle -y "$KEY" -d venu445mm

# Store package (.iq, builds every device in the manifest)
java -Xms1g -Dapple.awt.UIElement=true -jar "$SDK/bin/monkeybrains.jar" \
  -o bin/analog-simple.iq -f monkey.jungle -y "$KEY" -e

# Simulator: launch once, then (re)load the face onto it
"$SDK/bin/connectiq"
"$SDK/bin/monkeydo" bin/analog-simple.prg venu445mm
```

`bin/` is gitignored; build artifacts are never committed.

## Versioning, branches & releases

Connect IQ manifests have no app-version field (`iq:manifest version="3"` is
the manifest *schema* version — never bump it). The app version lives in the
`AppVersion` string in `resources/strings/strings.xml`.

**Two Garmin app ids, two branches** (a published Connect IQ app can't move
from beta to public — it needs a fresh app id):
- **beta** — app id `b3a1e6c2-…`, on `main` and dev branches (e.g.
  `claude/rain-gradient`). For ongoing development/testing. Tag betas
  `v<version>-beta`.
- **public** — app id `88c61d1d-…`, on the `public` branch. The global
  release. Tag `v<version>` (plain). The two app ids' version numbers run
  independently, so the same `vX.Y.Z` and `vX.Y.Z-beta` can coexist.

When asked to build the `.iq`: bump `AppVersion`, commit the bump, build the
`.iq`, and report the version. Tag per the branch's scheme above. Docs-only
changes (README, screenshots, CLAUDE.md) get no version bump and no `.iq`.

**Do not `git push`** — the user pushes and manages merges/branch topology
(beta → `public`) themselves. Commit and tag locally; leave pushing to them.

## Simulator gotchas (learned the hard way)

- The simulator **persists app settings across reinstalls**: loading a new
  prg keeps stored property values, so changed defaults in `properties.xml`
  won't show up. After `monkeydo` finishes loading, use File → Reset All App
  Data (no confirmation dialog) to fall back to the prg's defaults.
- `monkeydo` can take 10-20s to swap an already-running app, and prints
  nothing on success — wait before judging what's on screen.
- Screenshots: `screencapture` needs Screen Recording permission (without it
  you silently get wallpaper-only images). Use the simulator's own
  **File → Save Screen Capture** instead — it saves just the device screen
  and can be driven via System Events UI scripting.
- If `monkeydo` says "Unable to connect to simulator", the sim is wedged:
  `pkill -f "ConnectIQ.app/Contents/MacOS/simulator"` and relaunch.

## SDK gotchas (learned the hard way)

- This SDK's jungle parser rejects `project.typeCheckLevel` (and is picky in
  general) — keep `monkey.jungle` to `project.manifest = manifest.xml`.
- `Graphics` has no `COLOR_CYAN`. Named colors stop at the basic set
  (BLUE, RED, GREEN, ORANGE, PINK, PURPLE, YELLOW, the grays); use a packed
  RGB literal like `0x00FFFF` for anything else.

## Layout

- `source/AnalogSimpleView.mc` — all drawing logic (hands, ticks, battery
  ring, date). Hand styles are polygons in `drawHand`.
- `source/AnalogSimpleApp.mc` — app entry; `onSettingsChanged` triggers a
  redraw, so settings edits in the simulator apply live.
- `resources/settings/properties.xml` — property defaults;
  `settings.xml` — the settings UI shown in Garmin Connect/Express and the
  simulator (Settings → Trigger App Settings).
