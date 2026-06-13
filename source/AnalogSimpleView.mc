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

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc) {
        _screenWidth = dc.getWidth();
        _screenHeight = dc.getHeight();
        _centerX = _screenWidth / 2.0;
        _centerY = _screenHeight / 2.0;
        _radius = (_screenWidth < _screenHeight ? _screenWidth : _screenHeight) / 2.0;
    }

    function onShow() {
    }

    function onUpdate(dc) {
        var backgroundColor = getColorProperty("BackgroundColor", Graphics.COLOR_BLACK);

        dc.setAntiAlias(true);
        dc.setColor(backgroundColor, backgroundColor);
        dc.clear();

        drawTicks(dc);
        drawRainForecast(dc);
        drawCloudCover(dc);
        drawBatteryRing(dc);
        drawHands(dc);
    }

    function onHide() {
    }

    function onExitSleep() {
        _isAwake = true;
    }

    function onEnterSleep() {
        _isAwake = false;
        WatchUi.requestUpdate();
    }

    //! Draw the 12 hour tick marks around the bezel
    function drawTicks(dc) {
        var tickColor = getColorProperty("TickColor", Graphics.COLOR_LT_GRAY);
        dc.setColor(tickColor, Graphics.COLOR_TRANSPARENT);

        for (var i = 0; i < 12; i++) {
            var angle = i * Math.PI / 6.0;
            var sin = Math.sin(angle);
            var cos = Math.cos(angle);
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
        if (!getBooleanProperty("ShowRainForecast", true)) {
            return;
        }

        var hourly = Application.Storage.getValue("rain_hourly");
        if (hourly == null || hourly.size() < 2) {
            return;
        }

        var n = hourly.size() < 13 ? hourly.size() : 13;
        var maxMm = 4.0;                  // mm/hr mapping to the deepest bulge
        var outerRadius = _radius * 0.97; // hug the rim (the "horizon")
        var maxDepth = _radius * 0.13;

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
        var bg = getColorProperty("BackgroundColor", Graphics.COLOR_BLACK);
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

                    dc.setColor(lerpColor(blue, bg, (f0 + f1) / 2.0), Graphics.COLOR_TRANSPARENT);
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

    //! Draw cloud cover as three concentric grey lines — low, mid and high
    //! altitude — each at its own fixed radius, with higher cloud nearer the
    //! centre (the rim is the horizon). A line's thickness tracks that band's
    //! hourly coverage with a soft grey gradient; nothing is drawn for an hour
    //! whose coverage is 0%. Data from RainService (Open-Meteo).
    function drawCloudCover(dc) {
        if (!getBooleanProperty("ShowCloudCover", true)) {
            return;
        }

        var grey = dimColor(0xCCCCCC);
        var bg = getColorProperty("BackgroundColor", Graphics.COLOR_BLACK);

        // Higher altitude band sits closer to the centre.
        drawCloudBand(dc, Application.Storage.getValue("cloud_low"), _radius * 0.80, grey, bg);
        drawCloudBand(dc, Application.Storage.getValue("cloud_mid"), _radius * 0.66, grey, bg);
        drawCloudBand(dc, Application.Storage.getValue("cloud_high"), _radius * 0.52, grey, bg);
    }

    //! Draw one cloud band: a soft grey line at a fixed radius whose thickness
    //! tracks the hourly coverage (0-100). Hours with no cloud are left blank,
    //! so the line only appears where there is cloud.
    function drawCloudBand(dc, cover, baseRadius, grey, bg) {
        if (cover == null || cover.size() < 2) {
            return;
        }

        var n = cover.size() < 13 ? cover.size() : 13;
        var minHalf = _radius * 0.004;   // thin line at light cover
        var maxHalf = _radius * 0.022;   // fat soft band when overcast

        var hw = new [n];
        for (var i = 0; i < n; i++) {
            var c = cover[i];
            if (c == null || c < 0) {
                c = 0;
            } else if (c > 100) {
                c = 100;
            }
            hw[i] = (c <= 0) ? 0.0 : minHalf + (maxHalf - minHalf) * (c / 100.0);
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

                for (var k = 0; k < layers; k++) {
                    var g0 = k * 1.0 / layers;
                    var g1 = (k + 1) * 1.0 / layers;
                    dc.setColor(lerpColor(grey, bg, k * 1.0 / (layers - 1)), Graphics.COLOR_TRANSPARENT);

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

    //! Draw the hour, minute and (optionally) second hands
    function drawHands(dc) {
        var clockTime = System.getClockTime();
        var hour = clockTime.hour % 12;
        var minute = clockTime.min;
        var second = clockTime.sec;

        var hourAngle = (hour + minute / 60.0) * Math.PI / 6.0;
        var minuteAngle = (minute + second / 60.0) * Math.PI / 30.0;

        var handStyle = getNumberProperty("HandStyle", HAND_STYLE_CLASSIC);

        var hourColor = getColorProperty("HourHandColor", Graphics.COLOR_WHITE);
        var minuteColor = getColorProperty("MinuteHandColor", Graphics.COLOR_WHITE);
        var lengthScale = getNumberProperty("HandLength", 100) / 100.0;

        // Hour hand
        drawHand(dc, hourAngle, _radius * 0.5 * lengthScale, _radius * 0.08, handStyle, hourColor);

        // Minute hand
        drawHand(dc, minuteAngle, _radius * 0.82 * lengthScale, _radius * 0.08, handStyle, minuteColor);

        // Second hand (skipped while sleeping to save power / avoid burn-in)
        if (_isAwake && getBooleanProperty("ShowSecondHand", true)) {
            var secondAngle = second * Math.PI / 30.0;
            var secondColor = getColorProperty("SecondHandColor", Graphics.COLOR_ORANGE);
            drawSecondHand(dc, secondAngle, _radius * 0.9, secondColor);
        }

        // Center cap
        dc.setColor(hourColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_centerX, _centerY, _radius * 0.035);
    }

    //! Build and draw a hand polygon for the requested style
    function drawHand(dc, angle, length, width, style, color) {
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

        var bg = getColorProperty("BackgroundColor", Graphics.COLOR_BLACK);

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
        if (getBooleanProperty("RingColorByLevel", true)) {
            ringColor = dimColor(levelColor(percent));
        } else {
            ringColor = getColorProperty("RingColor", Graphics.COLOR_BLUE);
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
        var dateColor = getColorProperty("DateColor", Graphics.COLOR_WHITE);
        var today = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);

        dc.setColor(dateColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, centerY, Graphics.FONT_XTINY, today.day.format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Pick the percentage to drive the ring based on the configured source
    function getRingPercent() {
        var source = getNumberProperty("RingDataSource", RING_SOURCE_BODY_BATTERY);
        var percent = null;

        if (source == RING_SOURCE_WATCH_BATTERY) {
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
        if (getBooleanProperty("ColorblindMode", false)) {
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
        var pct = getNumberProperty("Brightness", 60);
        if (pct >= 100 || color <= 0) {
            return color;
        }
        var r = ((color >> 16) & 0xFF) * pct / 100;
        var g = ((color >> 8) & 0xFF) * pct / 100;
        var b = (color & 0xFF) * pct / 100;
        return (r << 16) + (g << 8) + b;
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

    function getColorProperty(key, defaultValue) {
        var value = Application.Properties.getValue(key);
        return dimColor((value != null) ? value : defaultValue);
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
