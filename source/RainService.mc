import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Time;

//! Fetches the hourly precipitation amount (mm) forecast from Open-Meteo
//! using the ECMWF model and caches it for the watch face to draw.
//!
//! Stored to Application.Storage (shared between background and foreground):
//!   "rain_hourly"  => Array<Float>  next 12 hours of precipitation in mm,
//!                                    starting at the current hour
//!   "rain_updated" => Number        epoch seconds of the last good fetch
(:background)
class RainService {

    function initialize() {}

    function fetch(lat as Float, lon as Float) as Void {
        Communications.makeWebRequest(
            "https://api.open-meteo.com/v1/forecast",
            {
                "latitude"       => lat,
                "longitude"      => lon,
                "hourly"         => "precipitation",
                "models"         => "ecmwf_ifs025",
                "timeformat"     => "unixtime",
                "forecast_days"  => 2
            },
            { :method => Communications.HTTP_REQUEST_METHOD_GET,
              :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
            method(:onResponse)
        );
    }

    function onResponse(responseCode as Number, data as Dictionary?) as Void {
        if (responseCode != 200 || data == null) {
            // Network/server error — keep whatever is already cached.
            return;
        }

        var hourly = data.get("hourly") as Dictionary?;
        if (hourly == null) { return; }
        var times = hourly.get("time") as Array?;
        var precip = hourly.get("precipitation") as Array?;
        if (times == null || precip == null) { return; }

        // Find the slot for the current hour, then take the next 12 hours.
        var now = Time.now().value();
        var start = 0;
        for (var i = 0; i < times.size(); i++) {
            // Each slot covers an hour; treat the last slot whose start is
            // <= now as "current".
            if ((times[i] as Number) <= now) {
                start = i;
            } else {
                break;
            }
        }

        var out = [] as Array<Float>;
        for (var i = start; i < times.size() && out.size() < 12; i++) {
            var mm = precip[i];
            out.add(mm == null ? 0.0 : (mm as Float).toFloat());
        }

        Application.Storage.setValue("rain_hourly", out);
        Application.Storage.setValue("rain_updated", now);
    }
}
