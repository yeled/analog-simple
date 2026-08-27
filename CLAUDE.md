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
(currently `connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`). The signing key is
`~/Downloads/developer_key` — don't hardcode a `/Users/<name>/` path, this
repo gets worked on from more than one account.

Resolve the SDK by glob rather than pinning the version, so a manager update
doesn't silently break every command below:

```sh
SDK="$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"/connectiq-sdk-mac-* | sort -V | tail -1)"
KEY=~/Downloads/developer_key

# Device build for the simulator
java -Xms1g -Dapple.awt.UIElement=true -jar "$SDK/bin/monkeybrains.jar" \
  -o bin/analog-simple.prg -f monkey.jungle -y "$KEY" -d venu445mm

# Store package (.iq, builds every device in the manifest). Name the output
# with the AppVersion in it, e.g. bin/analog-simple-1.0.10-beta12.iq
java -Xms1g -Dapple.awt.UIElement=true -jar "$SDK/bin/monkeybrains.jar" \
  -o bin/analog-simple-<version>.iq -f monkey.jungle -y "$KEY" -e

# Simulator: launch once, then (re)load the face onto it
"$SDK/bin/connectiq"
"$SDK/bin/monkeydo" bin/analog-simple.prg venu445mm
```

`bin/` is gitignored; build artifacts are never committed.

**Device profiles are installed per-SDK, and a fresh SDK ships with none of
them.** If a build dies with `ERROR: Invalid device id specified: 'venu445mm'`
the code is fine — the profile just isn't downloaded. Check with
`ls ~/Library/Application Support/Garmin/ConnectIQ/Devices/ | grep venu`, and
if it's empty install the Venu 4 sizes from the **Connect IQ SDK Manager**
(the `.dmg` is in `~/Downloads`; there is no CLI for this). Compiling against
some *other* already-installed device in the manifest is a perfectly good
syntax check while you wait.

## Versioning, branches & releases

Connect IQ manifests have no app-version field (`iq:manifest version="3"` is
the manifest *schema* version — never bump it). The app version lives in the
`AppVersion` string in `resources/strings/strings.xml`.

**`main` is the release source** — "what we ship to public" lives on `main`,
not on divergent branches. A published Connect IQ app can't move from beta to
public, so there are still two Garmin app ids, but the *only* thing that
differs between a beta build and the public build is `manifest.xml` (the app
id and the device list). Stamp it per target with `scripts/set-manifest.sh`
instead of hand-editing or merging it:
- `scripts/set-manifest.sh beta` — app id `b3a1e6c2-…`, the two Venu 4 sizes
  only (fast dev/testing). Tag betas `v<version>-beta`.
- `scripts/set-manifest.sh public` — app id `88c61d1d-…`, the full store
  device list (the global release). Tag `v<version>` (plain).

The two app ids' version numbers run independently, so `vX.Y.Z` and
`vX.Y.Z-beta` can coexist. (`public` is kept in sync with `main`, but `main`
is the source of truth.)

When asked to build the `.iq`: bump `AppVersion`, commit the bump, run the
right `set-manifest.sh` for the target, build the `.iq` **named with that
version** (`bin/analog-simple-<version>.iq`, e.g.
`bin/analog-simple-1.1.0.iq`), and report the version. Tag per the target's
scheme above. Docs-only changes (README, screenshots, CLAUDE.md) get no
version bump and no `.iq`.

**Pushing is OK** (re-enabled 2026-06-15) — Claude may `git push` branches and
tags as part of completing work. Still treat large branch-topology moves
(merging beta → `public` for a global release) and store uploads as deliberate
steps: do them when asked and report clearly.

**Commits are signed through 1Password** (`commit.gpgsign=true`,
`gpg.format=ssh`, signer `op-ssh-sign`). Signing needs a GUI approval, so in a
non-interactive shell `git commit` either dies with `1Password: failed to fill
whole buffer` or just hangs until it times out. That is not a repo problem and
**not a reason to reach for `--no-gpg-sign`** — it's the user's policy. Say the
commit is waiting on the prompt, and retry once they're at the keyboard.

## Simulator gotchas (learned the hard way)

- The simulator **persists app settings across reinstalls**: loading a new
  prg keeps stored property values, so changed defaults in `properties.xml`
  won't show up. After `monkeydo` finishes loading, use File → Reset All App
  Data (no confirmation dialog) to fall back to the prg's defaults.
- `monkeydo` can take 10-20s to swap an already-running app, and prints
  nothing on success — wait before judging what's on screen.
- Screenshots: `screencapture` needs Screen Recording permission (without it
  you silently get wallpaper-only images). The simulator's own
  **File → Save Screen Capture** saves just the device screen — but driving
  its save sheet via System Events UI scripting is unreliable (2026-08-16: the
  sheet opens, then swallows `Cmd+Shift+G`, typed paths and `set value of text
  field 1` alike, and closes without writing). Treat screenshots as a
  **human-in-the-loop step**: ask, rather than burning turns on the dialog.
  Save them into `bin/` named with the version (e.g.
  `bin/analog-simple-1.0.10-beta12.png`); `bin/` is gitignored so they're
  never committed.
- **The weather layers need cached data to draw anything.** A fresh simulator
  has no `rain_hourly` / `temp_hourly` in `Application.Storage`, so the rain,
  cloud and temperature draws all return early and the face looks bare — this
  is not a bug. Seed them via **File → Edit Persistent Storage**, or fire the
  background fetch with **Simulation → Background Events**.
- If `monkeydo` says "Unable to connect to simulator", the sim is wedged:
  `pkill -f "ConnectIQ.app/Contents/MacOS/simulator"` and relaunch.
- **The simulator does not enforce the device's execution watchdog.** A face
  that draws fine in the sim can be killed on the watch (the "IQ!" triangle)
  if one `onUpdate` runs too long — and the static-layer rebuild does all
  weather layers in a single call, so the stress test is a *stormy* day:
  heavy rain + 100% cloud on all three bands + a gusty wind line
  (2026-08-27: exactly that combination crashed 1.5.1 on the watch; the sim
  never blinked). When adding drawing work, budget for the day every layer
  is at maximum, keep trig/allocation out of inner loops, and prefer
  adaptive subdivision over fixed-fine.

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
