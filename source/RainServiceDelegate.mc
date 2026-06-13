import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Weather;

//! Background service: on each temporal event, resolve the current location
//! and ask RainService to refresh the Open-Meteo precipitation forecast.
(:background)
class RainServiceDelegate extends System.ServiceDelegate {

    // Minimum seconds between fetches (Open-Meteo updates hourly).
    private const REFRESH_INTERVAL = 3600;

    function initialize() {
        System.ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        // Skip if the cache is still fresh.
        var now = Time.now().value();
        var last = Application.Storage.getValue("rain_updated") as Number?;
        if (last != null && (now - last) < REFRESH_INTERVAL) {
            return;
        }

        var loc = resolveLocation();
        if (loc == null) { return; }

        new RainService().fetch(loc[0], loc[1]);
    }

    //! [lat, lon] in degrees. Prefers the manual "lat,long" override from
    //! settings, then the device's last known GPS fix, then the synced weather
    //! observation location. Null if none are available.
    hidden function resolveLocation() as Array<Float>? {
        var override = parseOverride(Application.Properties.getValue("LocationOverride"));
        if (override != null) {
            return override;
        }

        var info = Position.getInfo();
        if (info != null && info.position != null) {
            var deg = info.position.toDegrees();
            if (deg[0] != 0.0 || deg[1] != 0.0) {
                return [(deg[0] as Decimal).toFloat(), (deg[1] as Decimal).toFloat()];
            }
        }

        if (Weather has :getCurrentConditions) {
            var cc = Weather.getCurrentConditions();
            if (cc != null && cc.observationLocationPosition != null) {
                var wdeg = cc.observationLocationPosition.toDegrees();
                return [(wdeg[0] as Decimal).toFloat(), (wdeg[1] as Decimal).toFloat()];
            }
        }

        return null;
    }

    //! Parse a "lat,long" override string into [lat, lon], or null if empty
    //! or malformed.
    hidden function parseOverride(value) as Array<Float>? {
        if (!(value instanceof String) || value.length() == 0) {
            return null;
        }
        var comma = value.find(",");
        if (comma == null || comma <= 0) {
            return null;
        }
        var lat = value.substring(0, comma).toFloat();
        var lon = value.substring(comma + 1, value.length()).toFloat();
        if (lat == null || lon == null) {
            return null;
        }
        return [lat, lon];
    }
}
