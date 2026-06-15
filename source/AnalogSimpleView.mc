import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Hand style options (see resources/settings/settings.xml)
const HAND_STYLE_CLASSIC = 0;
const HAND_STYLE_SWORD = 1;
const HAND_STYLE_DIAMOND = 2;
const HAND_STYLE_ROUNDED = 3;

// Battery ring data source options
const RING_SOURCE_BODY_BATTERY = 0;
const RING_SOURCE_WATCH_BATTERY = 1;

class AnalogSimpleView extends WatchUi.WatchFace {

    private var _screenWidth = 0;
    private var _screenHeight = 0;
    private var _centerX = 0;
    private var _centerY = 0;
    private var _radius = 0;
    private var _isAwake = true;
    private var _hasAlpha = false;

    // Precomputed sin/cos for the 12 hour positions (filled in onLayout) so
    // the fixed tick geometry isn't recomputed every frame.
    private var _tickSin = null;
    private var _tickCos = null;

    // Cached settings, refreshed in cacheSettings() rather than read from
    // Application.Properties on every draw. Colours are pre-dimmed.
    private var _brightness = 60;
    private var _bgColor = 0x000000;
    private var _tickColor = 0xAAAAAA;
    private var _hourColor = 0xFFFFFF;
    private var _minuteColor = 0xFFFFFF;
    private var _secondColor = 0xFF5500;
    private var _dateColor = 0xFFFFFF;
    private var _handStyle = HAND_STYLE_ROUNDED;
    private var _lengthScale = 1.0;
    private var _showSecondHand = true;
    private var _showRain = true;
    private var _showCloud = true;
    private var _cloudRipple = true;
    private var _weatherInAOD = false;
    private var _ringSource = RING_SOURCE_BODY_BATTERY;
    private var _ringByLevel = true;
    private var _ringColor = 0x00FFFF;
    private var _colorblind = false;

    // Offscreen buffer holding the static layer (background, ticks, weather
    // rings, battery ring). Rebuilt only when its inputs change; each frame
    // just blits it and draws the live hands on top. Null if the device has
    // no buffer support or allocation failed, in which case we draw direct.
    private var _buffer = null;
    private var _bufferValid = false;
    private var _bufferMinute = -1;
    private var _bufferRainStamp = null;
    private var _bufferAwake = true;

    // Throttled battery-ring percentage so the Body Battery history isn't
    // re-queried more than once a minute.
    private var _ringPercent = 0;
    private var _ringPercentTime = -1;

    function initialize() {
        WatchFace.initialize();
        _hasAlpha = (Graphics has :createColor);
        cacheSettings();
    }

    function onLayout(dc) {
        _screenWidth = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX = _screenWidth / 2.0;
        _centerY = _screenHeight / 2.0;
        _radius = (_screenWidth < _screenHeight ? _screenWidth : _screenHeight) / 2.0;

        _tickSin = new [12];
        _tickCos = new [12];
        for (var i = 0; i < 12; i++) {
            var angle = i * Math.PI / 6.0;
            _tickSin[i] = Math.sin(angle);
            _tickCos[i] = Math.cos(angle);
        }

        // Screen size is known now; drop any buffer so it's reallocated.
        _buffer = null;
        _bufferValid = false;
    }

    function onShow() {
    }

    //! Re-read all settings into member variables and invalidate the static
    //! buffer. Called once at startup and from the app's onSettingsChanged.
    function onSettingsUpdate() {
        cacheSettings();
    }

    private function cacheSettings() {
        _brightness     = getNumberProperty("Brightness", 60);
        _bgColor        = dimColor(getRawColor("BackgroundColor", Graphics.COLOR_BLACK));
        _tickColor      = dimColor(getRawColor("TickColor", Graphics.COLOR_LT_GRAY));
        _hourColor      = dimColor(getRawColor("HourHandColor", Graphics.COLOR_WHITE));
        _minuteColor    = dimColor(getRawColor("MinuteHandColor", Graphics.COLOR_WHITE));
        _secondColor    = dimColor(getRawColor("SecondHandColor", Graphics.COLOR_ORANGE));
        _dateColor      = dimColor(getRawColor("DateColor", Graphics.COLOR_WHITE));
        _handStyle      = getNumberProperty("HandStyle", HAND_STYLE_ROUNDED);
        _lengthScale    = getNumberProperty("HandLength", 100) / 100.0;
        _showSecondHand = getBooleanProperty("ShowSecondHand", true);
        _showRain       = getBooleanProperty("ShowRainForecast", true);
        _showCloud      = getBooleanProperty("ShowCloudCover", true);
        _cloudRipple    = getBooleanProperty("CloudCoverRipple", true);
        _weatherInAOD   = getBooleanProperty("ShowWeatherInAOD", false);
        _ringSource     = getNumberProperty("RingDataSource", RING_SOURCE_BODY_BATTERY);
        _ringByLevel    = getBooleanProperty("RingColorByLevel", true);
        _ringColor      = dimColor(getRawColor("RingColor", Graphics.COLOR_BLUE));
        _colorblind     = getBooleanProperty("ColorblindMode", false);

        _ringPercentTime = -1;   // force a battery refresh on the next draw
        _bufferValid = false;    // settings changed → rebuild the buffer
    }

    function onUpdate(dc) {
        var clockTime = System.getClockTime();
        var rainStamp = Application.Storage.getValue("rain_updated");

        // Rebuild the static buffer only when something it depends on changed:
        // settings, the displayed minute (battery/date), fresh weather data,
        // or an awake/asleep transition (which changes band detail).
        if (!_bufferValid
                || clockTime.min != _bufferMinute
                || rainStamp != _bufferRainStamp
                || _isAwake != _bufferAwake) {
            rebuildBuffer(clockTime, rainStamp);
        }

        if (_bufferValid && _buffer != null) {
            dc.drawBitmap(0, 0, _buffer);
        } else {
            // No buffer (unsupported / allocation failed): draw direct.
            drawStaticLayer(dc);
        }

        // Hands draw straight to the screen each frame, on top of the blit.
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        drawHands(dc);
    }

    //! (Re)allocate the offscreen buffer if needed and render the static layer
    //! into it. Falls back to per-frame direct drawing if no buffer is
    //! available.
    private function rebuildBuffer(clockTime, rainStamp) {
        ensureBuffer();
        if (_buffer == null) {
            _bufferValid = false;   // onUpdate will draw direct
            return;
        }

        var bdc = _buffer.getDc();
        drawStaticLayer(bdc);

        _bufferValid = true;
        _bufferMinute = clockTime.min;
        _bufferRainStamp = rainStamp;
        _bufferAwake = _isAwake;
    }

    //! Allocate the static-layer buffer once. Leaves _buffer null when the
    //! device lacks buffer support or the allocation fails.
    private function ensureBuffer() {
        if (_buffer != null) {
            return;
        }
        var opts = { :width => _screenWidth, :height => _screenHeight };
        if (_hasAlpha && (Graphics has :ALPHA_BLENDING_FULL)) {
            opts.put(:alphaBlending, Graphics.ALPHA_BLENDING_FULL);
        }
        if (Graphics has :createBufferedBitmap) {
            var ref = Graphics.createBufferedBitmap(opts);
            if (ref != null) {
                _buffer = ref.get();
            }
        } else if (Graphics has :BufferedBitmap) {
            _buffer = new Graphics.BufferedBitmap(opts);
        }
    }

    //! Draw the background and everything that doesn't change every second.
    private function drawStaticLayer(dc) {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(_bgColor, _bgColor);
        dc.clear();

        drawTicks(dc);
        // The full weather bands are the heaviest thing drawn (big lit area,
        // ~400 polygons) and blow the always-on power budget, so draw them
        // only while awake. In low-power / AOD mode draw nothing (default) or,
        // if the user opted in, a lightweight outline version that stays
        // within the budget.
        if (_isAwake) {
            if (_showRain) {
                drawRainForecast(dc);
            }
            if (_showCloud) {
                drawCloudCover(dc);
            }
        } else if (_weatherInAOD) {
            drawWeatherAod(dc);
        }
        drawBatteryRing(dc);
    }

    //! Low-power weather for always-on mode. The three real cloud bands are
    //! drawn as solid fills like the awake face, but in a dim grey that gets
    //! darker the more overcast it is: low brightness (not a smaller lit
    //! area) is what keeps the always-on power budget in check, and dimming
    //! with coverage stops it peaking when the sky is fully clouded. Rain is
    //! a thin stroke along the band's inner edge for rainy hours.
    private function drawWeatherAod(dc) {
        if (_showCloud) {
            // Darken the grey as overall cloudiness rises. The band area grows
            // with coverage (thicker = cloudier), so dropping the brightness
            // as the sky fills keeps total emitted light — and AOD power —
            // from peaking exactly when it's fully overcast.
            var grey = dimColor(lerpColor(0x4A4A4A, 0x141414, overcastFraction()));
            // Outline a quarter of the way toward white so the band edge stays
            // visible even when the fill is nearly black.
            var edge = lerpColor(grey, 0xFFFFFF, 0.25);

            drawCloudBandAod(dc, Application.Storage.getValue("cloud_low"),  _radius * 0.78, grey, edge);
            drawCloudBandAod(dc, Application.Storage.getValue("cloud_mid"),  _radius * 0.64, grey, edge);
            drawCloudBandAod(dc, Application.Storage.getValue("cloud_high"), _radius * 0.50, grey, edge);
        }
        if (_showRain) {
            drawRainAodOutline(dc);
        }
    }

    //! Mean cloud coverage across all three layers and hours, as 0.0-1.0.
    //! Drives how dark the always-on cloud fill is drawn.
    private function overcastFraction() {
        var total = 0.0;
        var count = 0;
        var keys = ["cloud_low", "cloud_mid", "cloud_high"];
        for (var k = 0; k < keys.size(); k++) {
            var arr = Application.Storage.getValue(keys[k]);
            if (arr == null) { continue; }
            var n = arr.size() < 13 ? arr.size() : 13;
            for (var i = 0; i < n; i++) {
                var v = arr[i];
                if (v == null) { continue; }
                if (v < 0) { v = 0; } else if (v > 100) { v = 100; }
                total += v;
                count++;
            }
        }
        return (count > 0) ? (total / count) / 100.0 : 0.0;
    }

    //! One cloud band in low-power mode: a solid `fillColor` fill from the
    //! inner to the outer edge, with a lighter `outlineColor` stroke around
    //! both edges so the band stays visible when the fill is nearly black.
    //! Subdivided per hour to round the facets; cloud-free hours are skipped.
    private function drawCloudBandAod(dc, cover, baseRadius, fillColor, outlineColor) {
        if (cover == null || cover.size() < 2) {
            return;
        }

        var n = cover.size() < 13 ? cover.size() : 13;
        var minHalf = _radius * 0.004;
        var maxHalf = _radius * 0.07;

        var hw = new [n];
        for (var i = 0; i < n; i++) {
            var c = cover[i];
            if (c == null || c < 0) { c = 0; } else if (c > 100) { c = 100; }
            hw[i] = (c <= 0) ? 0.0 : minHalf + (maxHalf - minHalf) * (c / 100.0);
        }

        var sub = 4;   // sub-steps per hour, to round the facets
        var aa = (dc has :setAntiAlias);

        // Fill pass: AA off so the contiguous sub-step quads don't seam.
        if (aa) { dc.setAntiAlias(false); }
        // When the ripple is on, the fill grey undulates along the band (a
        // sine wave, its own phase per band) from solid down to black — which
        // reads as transparent on the black AOD background — so the cloud
        // fades in and out; otherwise it's a single grey set once.
        if (!_cloudRipple) {
            dc.setColor(fillColor, Graphics.COLOR_TRANSPARENT);
        }
        for (var i = 0; i < n - 1; i++) {
            if (hw[i] <= 0.0 && hw[i + 1] <= 0.0) {
                continue;  // gap where there's no cloud
            }
            for (var s = 0; s < sub; s++) {
                var t0 = s * 1.0 / sub;
                var t1 = (s + 1) * 1.0 / sub;
                var a0 = (i + t0) * Math.PI / 6.0;
                var a1 = (i + t1) * Math.PI / 6.0;
                var s0 = Math.sin(a0);
                var c0 = Math.cos(a0);
                var s1 = Math.sin(a1);
                var c1 = Math.cos(a1);
                var h0 = hw[i] + (hw[i + 1] - hw[i]) * t0;
                var h1 = hw[i] + (hw[i + 1] - hw[i]) * t1;

                if (_cloudRipple) {
                    var mid = (a0 + a1) / 2.0;
                    // 0.0 at the trough (black / "transparent") up to 1.4x
                    // (solid, slightly boosted) at the peak.
                    var f = 0.7 + 0.7 * Math.sin(mid * 5.0 + baseRadius * 0.7);
                    dc.setColor(scaleColor(fillColor, f), Graphics.COLOR_TRANSPARENT);
                }

                dc.fillPolygon([
                    [_centerX + (baseRadius + h0) * s0, _centerY - (baseRadius + h0) * c0],
                    [_centerX + (baseRadius + h1) * s1, _centerY - (baseRadius + h1) * c1],
                    [_centerX + (baseRadius - h1) * s1, _centerY - (baseRadius - h1) * c1],
                    [_centerX + (baseRadius - h0) * s0, _centerY - (baseRadius - h0) * c0]
                ]);
            }
        }

        // Outline pass: AA on for smooth edges, in the lighter colour.
        if (aa) { dc.setAntiAlias(true); }
        dc.setColor(outlineColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var i = 0; i < n - 1; i++) {
            if (hw[i] <= 0.0 && hw[i + 1] <= 0.0) {
                continue;
            }
            for (var s = 0; s < sub; s++) {
                var t0 = s * 1.0 / sub;
                var t1 = (s + 1) * 1.0 / sub;
                var a0 = (i + t0) * Math.PI / 6.0;
                var a1 = (i + t1) * Math.PI / 6.0;
                var s0 = Math.sin(a0);
                var c0 = Math.cos(a0);
                var s1 = Math.sin(a1);
                var c1 = Math.cos(a1);
                var h0 = hw[i] + (hw[i + 1] - hw[i]) * t0;
                var h1 = hw[i] + (hw[i + 1] - hw[i]) * t1;

                dc.drawLine(_centerX + (baseRadius + h0) * s0, _centerY - (baseRadius + h0) * c0,
                            _centerX + (baseRadius + h1) * s1, _centerY - (baseRadius + h1) * c1);
                dc.drawLine(_centerX + (baseRadius - h0) * s0, _centerY - (baseRadius - h0) * c0,
                            _centerX + (baseRadius - h1) * s1, _centerY - (baseRadius - h1) * c1);
            }
        }
    }

    //! Thin stroke along the rain band's inner edge for rainy hours.
    private function drawRainAodOutline(dc) {
        var hourly = Application.Storage.getValue("rain_hourly");
        if (hourly == null || hourly.size() < 2) {
            return;
        }

        var n = hourly.size() < 13 ? hourly.size() : 13;
        var maxMm = 4.0;
        var outerRadius = _radius * 0.97;
        var maxDepth = _radius * 0.18;   // shallower than the awake band

        var inner = new [n];
        for (var i = 0; i < n; i++) {
            var mm = hourly[i];
            var frac = (mm == null) ? 0.0 : mm / maxMm;
            if (frac > 1.0) { frac = 1.0; } else if (frac < 0.0) { frac = 0.0; }
            inner[i] = (frac <= 0.0) ? outerRadius : outerRadius - frac * maxDepth;
        }

        dc.setColor(dimColor(0x2E5A87), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var sub = 4;
        for (var i = 0; i < n - 1; i++) {
            if (inner[i] >= outerRadius && inner[i + 1] >= outerRadius) {
                continue;  // no rain across this segment
            }
            for (var s = 0; s < sub; s++) {
                var t0 = s * 1.0 / sub;
                var t1 = (s + 1) * 1.0 / sub;
                var a0 = (i + t0) * Math.PI / 6.0;
                var a1 = (i + t1) * Math.PI / 6.0;
                var r0 = inner[i] + (inner[i + 1] - inner[i]) * t0;
                var r1 = inner[i] + (inner[i + 1] - inner[i]) * t1;
                dc.drawLine(_centerX + r0 * Math.sin(a0), _centerY - r0 * Math.cos(a0),
                            _centerX + r1 * Math.sin(a1), _centerY - r1 * Math.cos(a1));
            }
        }
    }

    function onHide() {
    }

    function onExitSleep() {
        _isAwake = true;
        _bufferValid = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() {
        _isAwake = false;
        _bufferValid = false;
        WatchUi.requestUpdate();
    }

    //! Draw the 12 hour tick marks around the bezel
    function drawTicks(dc) {
        dc.setColor(_tickColor, Graphics.COLOR_TRANSPARENT);

        for (var i = 0; i < 12; i++) {
            var sin = _tickSin[i];
            var cos = _tickCos[i];
            var isMajor = (i % 3 == 0);
            var outerRadius = _radius * 0.96;
            var innerRadius = isMajor ? _radius * 0.85 : _radius * 0.91;

            var x1 = _centerX + outerRadius * sin;
            var y1 = _centerY - outerRadius * cos;
            var x2 = _centerX + innerRadius * sin;
            var y2 = _centerY - innerRadius * cos;

            dc.setPenWidth(isMajor ? 4 : 2);
            dc.drawLine(x1, y1, x2, y2);
        }
    }

    //! Draw the next 12 hours of rain *amount* (mm) as a solid blue ribbon
    //! just inside the bezel: a continuous band whose inner edge pulls inward
    //! with the hourly precipitation amount (a thin ring when dry, a deep
    //! bulge for heavy rain). 12 o'clock is the soonest hour, going clockwise;
    //! the band spans 11 hours and stops short of wrapping past 12 o'clock so
    //! the start and end don't touch. Data comes from RainService (Open-Meteo,
    //! cached in Application.Storage).
    function drawRainForecast(dc) {
        var hourly = Application.Storage.getValue("rain_hourly");
        if (hourly == null || hourly.size() < 2) {
            return;
        }

        var n = hourly.size() < 13 ? hourly.size() : 13;
        var maxMm = 4.0;                  // mm/hr that maps to the deepest band
        var outerRadius = _radius * 0.97; // hug the rim (the "horizon")
        var maxDepth = _radius * 0.30;    // exaggerated: 4mm+ reads as heavy

        // Inner-edge radius for each hour. Depth is 0 (nothing drawn) for a
        // dry hour, so the blue band only appears where it actually rains.
        var inner = new [n];
        for (var i = 0; i < n; i++) {
            var mm = hourly[i];
            var frac = (mm == null) ? 0.0 : mm / maxMm;
            if (frac > 1.0) {
                frac = 1.0;
            } else if (frac < 0.0) {
                frac = 0.0;
            }
            inner[i] = outerRadius - frac * maxDepth;
        }

        // Fill the band as a radial gradient: solid blue at the bezel fading
        // to the background colour at the inner edge (reads as blue fading to
        // transparent on a dark face). Each angular column is split into
        // radial layers, each lerped from blue toward the background.
        var blue = dimColor(0x4DA6FF);
        var bg = _bgColor;
        var sub = 3;       // angular sub-steps per hour
        var layers = 7;    // radial gradient bands
        for (var i = 0; i < n - 1; i++) {
            if (inner[i] >= outerRadius && inner[i + 1] >= outerRadius) {
                continue;  // no rain across this segment
            }
            for (var s = 0; s < sub; s++) {
                var t0 = s * 1.0 / sub;
                var t1 = (s + 1) * 1.0 / sub;
                var angA = (i + t0) * Math.PI / 6.0;
                var angB = (i + t1) * Math.PI / 6.0;
                var sinA = Math.sin(angA);
                var cosA = Math.cos(angA);
                var sinB = Math.sin(angB);
                var cosB = Math.cos(angB);
                var depthA = inner[i] + (inner[i + 1] - inner[i]) * t0 - outerRadius;
                var depthB = inner[i] + (inner[i + 1] - inner[i]) * t1 - outerRadius;

                for (var k = 0; k < layers; k++) {
                    var f0 = k * 1.0 / layers;
                    var f1 = (k + 1) * 1.0 / layers;
                    var rA0 = outerRadius + depthA * f0;
                    var rA1 = outerRadius + depthA * f1;
                    var rB0 = outerRadius + depthB * f0;
                    var rB1 = outerRadius + depthB * f1;

                    dc.setColor(bandColor(blue, bg, (f0 + f1) / 2.0), Graphics.COLOR_TRANSPARENT);
                    dc.fillPolygon([
                        [_centerX + rA0 * sinA, _centerY - rA0 * cosA],
                        [_centerX + rB0 * sinB, _centerY - rB0 * cosB],
                        [_centerX + rB1 * sinB, _centerY - rB1 * cosB],
                        [_centerX + rA1 * sinA, _centerY - rA1 * cosA]
                    ]);
                }
            }
        }
    }

    //! Draw cloud cover as three concentric lines — low, mid and high
    //! altitude — each at its own fixed radius, with higher cloud nearer the
    //! centre (the rim is the horizon). A line's thickness tracks that band's
    //! hourly coverage, and its colour shifts from white (thin/wispy) through
    //! grey to a blue-grey (thick/stormy), with the blue-grey only kicking in
    //! for hours where rain is forecast or has a non-zero chance; nothing is
    //! drawn for an hour whose coverage is 0%. Data from RainService
    //! (Open-Meteo).
    function drawCloudCover(dc) {
        var bg = _bgColor;
        var rainMm = Application.Storage.getValue("rain_hourly");
        var rainChance = Application.Storage.getValue("rain_chance");
        var ripple = _cloudRipple;

        // Many small adjacent fills make up each band; with anti-aliasing on,
        // each one gets its own blended edge against the background, leaving
        // a fine grid of seam lines between segments. Turn it off for these
        // fills and restore it afterwards for the ring and hands.
        var hadAA = (dc has :setAntiAlias);
        if (hadAA) {
            dc.setAntiAlias(false);
        }

        // Higher altitude band sits closer to the centre. Radii are spaced so
        // the thick bands overlap a little, stacking the gradients.
        drawCloudBand(dc, Application.Storage.getValue("cloud_low"), _radius * 0.78, bg, rainMm, rainChance, ripple);
        drawCloudBand(dc, Application.Storage.getValue("cloud_mid"), _radius * 0.64, bg, rainMm, rainChance, ripple);
        drawCloudBand(dc, Application.Storage.getValue("cloud_high"), _radius * 0.50, bg, rainMm, rainChance, ripple);

        if (hadAA) {
            dc.setAntiAlias(true);
        }
    }

    //! Draw one cloud band: a line at a fixed radius whose thickness tracks
    //! the hourly coverage (0-100) and whose colour runs from white at light
    //! cover to grey to blue-grey at heavy cover. The blue-grey shift is
    //! gated by `rainMm`/`rainChance` (mm forecast and probability 0-100 for
    //! the same hours) — heavy cloud with no rain in the forecast stays grey
    //! rather than reading as a storm. Hours with no cloud are left blank, so
    //! the line only appears where there is cloud. When `ripple` is false the
    //! colour is a flat tint per segment instead of waving along the ring.
    function drawCloudBand(dc, cover, baseRadius, bg, rainMm, rainChance, ripple) {
        if (cover == null || cover.size() < 2) {
            return;
        }

        var n = cover.size() < 13 ? cover.size() : 13;
        var minHalf = _radius * 0.006;   // thin line at light cover
        var maxHalf = _radius * 0.065;   // exaggerated: 100% reads as heavy

        var hw = new [n];
        var cf = new [n];
        var sf = new [n];  // storm fraction: how much rain/rain-chance backs this hour
        for (var i = 0; i < n; i++) {
            var c = cover[i];
            if (c == null || c < 0) {
                c = 0;
            } else if (c > 100) {
                c = 100;
            }
            cf[i] = c / 100.0;
            hw[i] = (c <= 0) ? 0.0 : minHalf + (maxHalf - minHalf) * cf[i];

            var mm = (rainMm != null && i < rainMm.size()) ? rainMm[i] : null;
            var mmFrac = (mm == null) ? 0.0 : mm / 1.0; // 1mm/hr is already "raining"
            var chance = (rainChance != null && i < rainChance.size()) ? rainChance[i] : null;
            var chanceFrac = (chance == null) ? 0.0 : chance / 100.0;
            var storm = mmFrac > chanceFrac ? mmFrac : chanceFrac;
            sf[i] = storm > 1.0 ? 1.0 : storm;
        }

        var sub = 2;
        var layers = 3;
        for (var i = 0; i < n - 1; i++) {
            if (hw[i] <= 0.0 && hw[i + 1] <= 0.0) {
                continue;  // no cloud across this segment
            }
            for (var s = 0; s < sub; s++) {
                var t0 = s * 1.0 / sub;
                var t1 = (s + 1) * 1.0 / sub;
                var angA = (i + t0) * Math.PI / 6.0;
                var angB = (i + t1) * Math.PI / 6.0;
                var sinA = Math.sin(angA);
                var cosA = Math.cos(angA);
                var sinB = Math.sin(angB);
                var cosB = Math.cos(angB);
                var hwA = hw[i] + (hw[i + 1] - hw[i]) * t0;
                var hwB = hw[i] + (hw[i + 1] - hw[i]) * t1;
                var cfA = cf[i] + (cf[i + 1] - cf[i]) * t0;
                var cfB = cf[i] + (cf[i + 1] - cf[i]) * t1;
                var sfA = sf[i] + (sf[i + 1] - sf[i]) * t0;
                var sfB = sf[i] + (sf[i + 1] - sf[i]) * t1;

                // Ripple the colour along the band so it doesn't read as a
                // flat tint: a gentle sine wave nudges the coverage fraction
                // up and down, shifting whiter/greyer/bluer in waves. Each
                // band gets its own phase (from baseRadius) so the three
                // rings don't ripple in lockstep. Optional: the extra sine
                // call and per-segment colour changes add draw work that can
                // trip a device's Always-On Display power budget.
                var rippleAmt = 0.0;
                if (ripple) {
                    var midAngle = (angA + angB) / 2.0;
                    rippleAmt = Math.sin(midAngle * 5.0 + baseRadius * 0.7) * 0.12;
                }
                var cf2 = (cfA + cfB) / 2.0 + rippleAmt;
                if (cf2 < 0.0) {
                    cf2 = 0.0;
                } else if (cf2 > 1.0) {
                    cf2 = 1.0;
                }
                var base = dimColor(cloudColor(cf2, (sfA + sfB) / 2.0));

                var fadeDenom = (layers > 1) ? (layers - 1) : 1;
                for (var k = 0; k < layers; k++) {
                    var g0 = k * 1.0 / layers;
                    var g1 = (k + 1) * 1.0 / layers;
                    dc.setColor(bandColor(base, bg, k * 1.0 / fadeDenom), Graphics.COLOR_TRANSPARENT);

                    // Outer half of the band.
                    dc.fillPolygon([
                        [_centerX + (baseRadius + hwA * g0) * sinA, _centerY - (baseRadius + hwA * g0) * cosA],
                        [_centerX + (baseRadius + hwB * g0) * sinB, _centerY - (baseRadius + hwB * g0) * cosB],
                        [_centerX + (baseRadius + hwB * g1) * sinB, _centerY - (baseRadius + hwB * g1) * cosB],
                        [_centerX + (baseRadius + hwA * g1) * sinA, _centerY - (baseRadius + hwA * g1) * cosA]
                    ]);
                    // Inner half of the band.
                    dc.fillPolygon([
                        [_centerX + (baseRadius - hwA * g1) * sinA, _centerY - (baseRadius - hwA * g1) * cosA],
                        [_centerX + (baseRadius - hwB * g1) * sinB, _centerY - (baseRadius - hwB * g1) * cosB],
                        [_centerX + (baseRadius - hwB * g0) * sinB, _centerY - (baseRadius - hwB * g0) * cosB],
                        [_centerX + (baseRadius - hwA * g0) * sinA, _centerY - (baseRadius - hwA * g0) * cosA]
                    ]);
                }
            }
        }
    }

    //! Map a cloud band's coverage (0.0-1.0) to a colour: thin/wispy cloud is
    //! near-white, fading through grey as coverage (and thus the drawn
    //! line's thickness) increases. Past 50% coverage, `stormFraction`
    //! (0.0-1.0, how much rain or rain chance backs this hour) gates a
    //! further shift toward a blue-grey "storm" tint — heavy cloud with no
    //! rain in the forecast stays grey rather than reading as a storm.
    function cloudColor(coverFraction, stormFraction) {
        if (coverFraction <= 0.5) {
            return lerpColor(0xFFFFFF, 0xCCCCCC, coverFraction / 0.5);
        }
        return lerpColor(0xCCCCCC, 0x8FA3BF, (coverFraction - 0.5) / 0.5 * stormFraction);
    }

    //! Draw the hour, minute and (optionally) second hands
    function drawHands(dc) {
        var clockTime = System.getClockTime();
        var hour = clockTime.hour % 12;
        var minute = clockTime.min;
        var second = clockTime.sec;

        var hourAngle = (hour + minute / 60.0) * Math.PI / 6.0;
        var minuteAngle = (minute + second / 60.0) * Math.PI / 30.0;

        // Hour hand
        drawHand(dc, hourAngle, _radius * 0.5 * _lengthScale, _radius * 0.08, _handStyle, _hourColor);

        // Minute hand
        drawHand(dc, minuteAngle, _radius * 0.82 * _lengthScale, _radius * 0.08, _handStyle, _minuteColor);

        // Second hand (skipped while sleeping to save power / avoid burn-in)
        if (_isAwake && _showSecondHand) {
            var secondAngle = second * Math.PI / 30.0;
            drawSecondHand(dc, secondAngle, _radius * 0.9, _secondColor);
        }

        // Center cap
        dc.setColor(_hourColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_centerX, _centerY, _radius * 0.035);
    }

    //! Build and draw a hand polygon for the requested style
    function drawHand(dc, angle, length, width, style, color) {
        if (style == HAND_STYLE_ROUNDED) {
            drawRoundedHand(dc, angle, length, width, color);
            return;
        }

        var tail = _radius * 0.15;
        var points;

        if (style == HAND_STYLE_SWORD) {
            // Parallel-sided blade with a pointed tip
            var tipLen = width * 1.2;
            points = [
                [-width / 2, tail],
                [-width / 2, -(length - tipLen)],
                [0, -length],
                [width / 2, -(length - tipLen)],
                [width / 2, tail]
            ];
        } else if (style == HAND_STYLE_DIAMOND) {
            var midWidth = width * 1.3;
            var midPoint = -length * 0.58;
            points = [
                [0, tail],
                [-midWidth / 2, midPoint],
                [0, -length],
                [midWidth / 2, midPoint]
            ];
        } else {
            // Classic: straight baton
            points = [
                [-width / 2, tail],
                [-width / 2, -length],
                [width / 2, -length],
                [width / 2, tail]
            ];
        }

        var shape = rotatePoints(points, angle);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(shape);

        var bg = _bgColor;

        if (style == HAND_STYLE_SWORD) {
            // Transparent lume channel down the middle of the blade
            var tipLen = width * 1.2;
            var insetWidth = width * 0.34;
            var insetPoints = [
                [-insetWidth / 2, -length * 0.18],
                [-insetWidth / 2, -(length - tipLen * 1.5)],
                [insetWidth / 2, -(length - tipLen * 1.5)],
                [insetWidth / 2, -length * 0.18]
            ];
            dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(rotatePoints(insetPoints, angle));
        }

        // Thin outline in the background color so overlapping hands stay
        // visually separated at the center
        dc.setPenWidth(1);
        dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < shape.size(); i++) {
            var p0 = shape[i];
            var p1 = shape[(i + 1) % shape.size()];
            dc.drawLine(p0[0], p0[1], p1[0], p1[1]);
        }
    }

    //! Draw a rounded "lume" hand: a capsule (rounded ends) in the hand colour
    //! with a thinner rounded channel of background colour down the middle,
    //! inset from the ends so the tip and base stay solid. A slightly larger
    //! background capsule underneath keeps overlapping hands separated.
    function drawRoundedHand(dc, angle, length, width, color) {
        var bg = _bgColor;
        var tail = _radius * 0.15;

        var ends = rotatePoints([[0, tail], [0, -length]], angle);
        var base = ends[0];
        var tip = ends[1];

        var w = width.toNumber();
        if (w < 2) { w = 2; }
        var half = w / 2;

        // Background outline capsule (slightly larger) for separation.
        capsule(dc, base, tip, w + 2, half + 1, bg);
        // Body capsule.
        capsule(dc, base, tip, w, half, color);

        // Lume channel: thinner capsule, inset from both ends.
        var lumeEnds = rotatePoints([[0, tail - width], [0, -(length - width)]], angle);
        var lw = (width * 0.42).toNumber();
        if (lw < 2) { lw = 2; }
        capsule(dc, lumeEnds[0], lumeEnds[1], lw, lw / 2, bg);
    }

    //! Draw a filled capsule (thick line with rounded ends) of the given
    //! pen width and end radius, in one colour.
    function capsule(dc, p0, p1, penWidth, endRadius, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(penWidth);
        dc.drawLine(p0[0], p0[1], p1[0], p1[1]);
        dc.fillCircle(p0[0], p0[1], endRadius);
        dc.fillCircle(p1[0], p1[1], endRadius);
    }

    //! Draw a thin second hand with a small counterweight tail
    function drawSecondHand(dc, angle, length, color) {
        var tail = _radius * 0.2;
        var width = _radius * 0.015;

        var points = [
            [-width / 2, tail],
            [-width / 2, -length],
            [width / 2, -length],
            [width / 2, tail]
        ];

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(rotatePoints(points, angle));

        var counterDist = tail * 0.85;
        var ccx = _centerX - counterDist * Math.sin(angle);
        var ccy = _centerY + counterDist * Math.cos(angle);
        dc.fillCircle(ccx, ccy, width * 1.4);
    }

    //! Rotate local hand points (where local +y points toward 6 o'clock)
    //! clockwise by angle (radians, 0 = 12 o'clock) and translate to center
    function rotatePoints(points, angle) {
        var cosA = Math.cos(angle);
        var sinA = Math.sin(angle);
        var result = new [points.size()];

        for (var i = 0; i < points.size(); i++) {
            var lx = points[i][0];
            var ly = points[i][1];
            var dx = lx * cosA - ly * sinA;
            var dy = lx * sinA + ly * cosA;
            result[i] = [_centerX + dx, _centerY + dy];
        }

        return result;
    }

    //! Draw the date box at the 3 o'clock position with a battery /
    //! body battery progress ring (a rounded square) around it
    function drawBatteryRing(dc) {
        var boxCenterX = _centerX + (_radius * 0.62);
        var boxCenterY = _centerY;
        var halfSize = _radius * 0.125;
        var cornerRadius = halfSize * 0.45;
        var penWidth = (_radius * 0.0225).toNumber();
        if (penWidth < 1) {
            penWidth = 1;
        }

        var percent = getRingPercent();

        var ringColor;
        if (_ringByLevel) {
            ringColor = dimColor(levelColor(percent));
        } else {
            ringColor = _ringColor;
        }

        var perimeter = roundedSquarePerimeter(boxCenterX, boxCenterY, halfSize, cornerRadius);

        // Dark grey box fill behind the date
        dc.setColor(dimColor(0x333333), Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(boxCenterX - halfSize, boxCenterY - halfSize,
            halfSize * 2, halfSize * 2, cornerRadius);

        // Track (background) outline
        dc.setPenWidth(penWidth);
        dc.setColor(dimColor(Graphics.COLOR_DK_GRAY), Graphics.COLOR_TRANSPARENT);
        drawPerimeterFraction(dc, perimeter, 1.0);

        // Foreground portion representing remaining percentage
        dc.setColor(ringColor, Graphics.COLOR_TRANSPARENT);
        drawPerimeterFraction(dc, perimeter, percent / 100.0);

        drawDate(dc, boxCenterX, boxCenterY);
    }

    //! Sample points along a rounded-square outline, starting at the top
    //! center and going clockwise. Straight edges fall out of the gaps
    //! between consecutive corner arcs.
    function roundedSquarePerimeter(cx, cy, half, corner) {
        var straight = half - corner;
        var arcSteps = 6;
        var pts = [[cx, cy - half]];

        // Corner arc centers, clockwise from top-right, with start angles
        var corners = [
            [cx + straight, cy - straight, -Math.PI / 2],
            [cx + straight, cy + straight, 0.0],
            [cx - straight, cy + straight, Math.PI / 2],
            [cx - straight, cy - straight, Math.PI]
        ];

        for (var c = 0; c < 4; c++) {
            for (var i = 0; i <= arcSteps; i++) {
                var a = corners[c][2] + (Math.PI / 2) * i / arcSteps;
                pts = pts.add([corners[c][0] + corner * Math.cos(a),
                               corners[c][1] + corner * Math.sin(a)]);
            }
        }

        return pts.add([cx, cy - half]);
    }

    //! Draw the first `fraction` (0.0-1.0) of a polyline's length
    function drawPerimeterFraction(dc, points, fraction) {
        if (fraction <= 0.0) {
            return;
        }

        var total = 0.0;
        var lengths = new [points.size() - 1];
        for (var i = 0; i < lengths.size(); i++) {
            var dx = points[i + 1][0] - points[i][0];
            var dy = points[i + 1][1] - points[i][1];
            lengths[i] = Math.sqrt(dx * dx + dy * dy);
            total += lengths[i];
        }

        var budget = total * fraction;
        for (var i = 0; i < lengths.size() && budget > 0; i++) {
            var p0 = points[i];
            var p1 = points[i + 1];
            if (budget >= lengths[i]) {
                dc.drawLine(p0[0], p0[1], p1[0], p1[1]);
            } else {
                var t = budget / lengths[i];
                dc.drawLine(p0[0], p0[1],
                            p0[0] + (p1[0] - p0[0]) * t,
                            p0[1] + (p1[1] - p0[1]) * t);
            }
            budget -= lengths[i];
        }
    }

    //! Draw the day of month inside the ring
    function drawDate(dc, centerX, centerY) {
        var today = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);

        dc.setColor(_dateColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, centerY, Graphics.FONT_XTINY, today.day.format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Pick the percentage to drive the ring based on the configured source.
    //! The (relatively expensive) Body Battery history query is throttled to
    //! once a minute; the level changes slowly enough that re-reading it more
    //! often just wastes power.
    function getRingPercent() {
        var now = Time.now().value();
        if (_ringPercentTime >= 0 && (now - _ringPercentTime) < 60) {
            return _ringPercent;
        }

        var percent = null;
        if (_ringSource == RING_SOURCE_WATCH_BATTERY) {
            percent = getWatchBatteryPercent();
        } else {
            percent = getBodyBatteryPercent();
            if (percent == null) {
                percent = getWatchBatteryPercent();
            }
        }

        if (percent == null) {
            percent = 0;
        }
        if (percent < 0) {
            percent = 0;
        }
        if (percent > 100) {
            percent = 100;
        }

        _ringPercent = percent;
        _ringPercentTime = now;
        return percent;
    }

    //! Current watch battery level, 0-100
    function getWatchBatteryPercent() {
        var stats = System.getSystemStats();
        return Math.round(stats.battery).toNumber();
    }

    //! Most recent Body Battery reading, 0-100, or null if unavailable
    function getBodyBatteryPercent() {
        if (!(Toybox has :SensorHistory)) {
            return null;
        }
        if (!(Toybox.SensorHistory has :getBodyBatteryHistory)) {
            return null;
        }

        var iterator = Toybox.SensorHistory.getBodyBatteryHistory({
            :period => 1,
            :order => Toybox.SensorHistory.ORDER_NEWEST_FIRST
        });

        if (iterator == null) {
            return null;
        }

        var sample = iterator.next();
        if (sample == null || sample.data == null) {
            return null;
        }

        return Math.round(sample.data).toNumber();
    }

    //! Map a 0-100 level to a low / mid / high color. The default scheme is
    //! red / yellow / green; Colorblind Mode swaps to a red-green-safe
    //! red / amber / blue scale that also varies in lightness.
    function levelColor(percent) {
        if (_colorblind) {
            if (percent <= 20) {
                return 0xFF2222; // red
            } else if (percent <= 50) {
                return 0xFFAA00; // amber
            }
            return 0x33AAFF;     // blue
        }

        if (percent <= 20) {
            return Graphics.COLOR_RED;
        } else if (percent <= 50) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_GREEN;
    }

    //! Scale a 24-bit RGB color by the configured brightness percentage.
    //! Dimmer pixels draw less power on the Venu's AMOLED display.
    function dimColor(color) {
        var pct = _brightness;
        if (pct >= 100 || color <= 0) {
            return color;
        }
        var r = ((color >> 16) & 0xFF) * pct / 100;
        var g = ((color >> 8) & 0xFF) * pct / 100;
        var b = (color & 0xFF) * pct / 100;
        return (r << 16) + (g << 8) + b;
    }

    //! Multiply each channel of a 24-bit RGB colour by `f`, clamped to 0-255.
    //! Used to undulate the AOD cloud fill lighter/darker.
    function scaleColor(color, f) {
        var r = (((color >> 16) & 0xFF) * f).toNumber();
        var g = (((color >> 8) & 0xFF) * f).toNumber();
        var b = ((color & 0xFF) * f).toNumber();
        if (r > 255) { r = 255; } else if (r < 0) { r = 0; }
        if (g > 255) { g = 255; } else if (g < 0) { g = 0; }
        if (b > 255) { b = 255; } else if (b < 0) { b = 0; }
        return (r << 16) + (g << 8) + b;
    }

    //! Colour for a gradient layer fading out by `fade` (0 = solid base,
    //! 1 = gone). With alpha support the base colour is drawn at decreasing
    //! opacity so overlapping bands blend (stack); otherwise it falls back to
    //! lerping toward the background, which only looks right where bands don't
    //! overlap.
    function bandColor(base, bg, fade) {
        if (fade < 0.0) {
            fade = 0.0;
        } else if (fade > 1.0) {
            fade = 1.0;
        }
        if (_hasAlpha) {
            var a = ((1.0 - fade) * 255).toNumber();
            return Graphics.createColor(a, (base >> 16) & 0xFF, (base >> 8) & 0xFF, base & 0xFF);
        }
        return lerpColor(base, bg, fade);
    }

    //! Linearly blend two 24-bit RGB colors; t=0 returns c0, t=1 returns c1.
    function lerpColor(c0, c1, t) {
        if (t < 0.0) {
            t = 0.0;
        } else if (t > 1.0) {
            t = 1.0;
        }
        var r = (((c0 >> 16) & 0xFF) + (((c1 >> 16) & 0xFF) - ((c0 >> 16) & 0xFF)) * t).toNumber();
        var g = (((c0 >> 8) & 0xFF) + (((c1 >> 8) & 0xFF) - ((c0 >> 8) & 0xFF)) * t).toNumber();
        var b = ((c0 & 0xFF) + ((c1 & 0xFF) - (c0 & 0xFF)) * t).toNumber();
        return (r << 16) + (g << 8) + b;
    }

    //! Raw (undimmed) colour property value. cacheSettings applies dimColor.
    function getRawColor(key, defaultValue) {
        var value = Application.Properties.getValue(key);
        return (value != null) ? value : defaultValue;
    }

    function getNumberProperty(key, defaultValue) {
        var value = Application.Properties.getValue(key);
        return (value != null) ? value : defaultValue;
    }

    function getBooleanProperty(key, defaultValue) {
        var value = Application.Properties.getValue(key);
        return (value != null) ? value : defaultValue;
    }

}
