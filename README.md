# analog-simple

A configurable analog watch face for the Garmin Venu 4 / Venu 4S, built with
the Connect IQ SDK.

## Features

- Analog hour/minute/second hands with independently configurable colors
  and a choice of three hand styles: Classic, Sword, and Diamond.
- 12 hour tick marks around the bezel (configurable color).
- A date complication at the 3 o'clock position showing the day of week
  and day of month.
- A progress ring around the date box that shows either your current
  **Body Battery** level or your **Watch Battery** level remaining
  (0-100%). The ring can either be a fixed color or automatically colored
  green/yellow/red based on the level.

## Project layout

- `manifest.xml` - app manifest (targets `venu4` and `venu4s`).
- `monkey.jungle` - build configuration.
- `source/AnalogSimpleApp.mc` - application entry point.
- `source/AnalogSimpleView.mc` - watch face drawing logic.
- `resources/settings/` - user-configurable properties (`properties.xml`)
  and the settings UI shown in Garmin Connect/Express (`settings.xml`).
- `resources/strings/` - localized strings.
- `resources/drawables/` - launcher icon.

## Settings

All settings are configurable from the Garmin Connect or Garmin Express
app after installing the watch face:

| Setting | Description |
| --- | --- |
| Hand Style | Classic, Sword, or Diamond hand shapes |
| Hour Hand Color / Minute Hand Color | Color of each hand |
| Show Second Hand / Second Hand Color | Toggle and color the second hand |
| Background Color | Watch face background |
| Tick Mark Color | Color of the bezel hour ticks |
| Date Color | Color of the day/date text |
| Battery Ring Source | Body Battery or Watch Battery |
| Color Ring By Level | Auto-color the ring green/yellow/red by level |
| Ring Color | Fixed ring color (used when "Color Ring By Level" is off) |

## Building

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
and a developer key. From this directory:

```sh
monkeyc -f monkey.jungle -d venu4 -o bin/analog-simple.prg -y developer_key.der
```

Then run it in the simulator:

```sh
connectiq
monkeydo bin/analog-simple.prg venu4
```
