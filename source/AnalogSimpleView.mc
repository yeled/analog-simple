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

        // Hour hand
        drawHand(dc, hourAngle, _radius * 0.5, _radius * 0.12, handStyle, hourColor);

        // Minute hand
        drawHand(dc, minuteAngle, _radius * 0.82, _radius * 0.08, handStyle, minuteColor);

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
            var tipWidth = width * 0.18;
            points = [
                [-width / 2, tail],
                [-tipWidth / 2, -length],
                [tipWidth / 2, -length],
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

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(rotatePoints(points, angle));
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
    //! body battery progress ring around it
    function drawBatteryRing(dc) {
        var ringCenterX = _centerX + (_radius * 0.62);
        var ringCenterY = _centerY;
        var ringRadius = _radius * 0.165;
        var penWidth = (_radius * 0.045).toNumber();
        if (penWidth < 2) {
            penWidth = 2;
        }

        var percent = getRingPercent();

        var ringColor;
        if (getBooleanProperty("RingColorByLevel", true)) {
            ringColor = levelColor(percent);
        } else {
            ringColor = getColorProperty("RingColor", Graphics.COLOR_CYAN);
        }

        // Track (background) ring
        dc.setPenWidth(penWidth);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(ringCenterX, ringCenterY, ringRadius);

        // Foreground arc representing remaining percentage
        dc.setColor(ringColor, Graphics.COLOR_TRANSPARENT);
        if (percent >= 100) {
            dc.drawCircle(ringCenterX, ringCenterY, ringRadius);
        } else if (percent > 0) {
            var endAngle = 90.0 - (percent / 100.0) * 360.0;
            dc.drawArc(ringCenterX, ringCenterY, ringRadius, Graphics.ARC_CLOCKWISE, 90, endAngle);
        }

        drawDate(dc, ringCenterX, ringCenterY, ringRadius);
    }

    //! Draw the day-of-week and day-of-month inside the ring
    function drawDate(dc, centerX, centerY, ringRadius) {
        var dateColor = getColorProperty("DateColor", Graphics.COLOR_WHITE);
        var today = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);

        dc.setColor(dateColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, centerY - ringRadius * 0.42, Graphics.FONT_XTINY, today.day_of_week,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(centerX, centerY + ringRadius * 0.25, Graphics.FONT_SMALL, today.day.format("%d"),
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

    //! Map a 0-100 level to a green / yellow / red color
    function levelColor(percent) {
        if (percent <= 20) {
            return Graphics.COLOR_RED;
        } else if (percent <= 50) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_GREEN;
    }

    function getColorProperty(key, defaultValue) {
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
