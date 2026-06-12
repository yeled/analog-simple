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
