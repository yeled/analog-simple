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
                "hourly"         => "precipitation,cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high",
                "models"         => "ecmwf_ifs",
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

        var cloud = hourly.get("cloud_cover") as Array?;
        var cloudLow = hourly.get("cloud_cover_low") as Array?;
        var cloudMid = hourly.get("cloud_cover_mid") as Array?;
        var cloudHigh = hourly.get("cloud_cover_high") as Array?;

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

        var rain = [] as Array<Float>;
        var density = [] as Array<Number>;   // total cloud cover 0-100
        var height = [] as Array<Float>;     // 0 = low cloud, 1 = high cloud
        for (var i = start; i < times.size() && rain.size() < 12; i++) {
            var mm = precip[i];
            rain.add(mm == null ? 0.0 : (mm as Float).toFloat());

            density.add(num(cloud, i));
            // Weight the altitude bands by their coverage to get a single
            // representative cloud height fraction.
            var lo = num(cloudLow, i);
            var mi = num(cloudMid, i);
            var hi = num(cloudHigh, i);
            var total = lo + mi + hi;
            height.add(total > 0 ? (0.1 * lo + 0.5 * mi + 0.9 * hi) / total : 0.5);
        }

        Application.Storage.setValue("rain_hourly", rain);
        Application.Storage.setValue("cloud_density", density);
        Application.Storage.setValue("cloud_height", height);
        Application.Storage.setValue("rain_updated", now);
    }

    // Read array[i] as a Number, defaulting to 0 when missing/null.
    hidden function num(arr as Array?, i as Number) as Number {
        if (arr == null || i >= arr.size() || arr[i] == null) { return 0; }
        return arr[i] as Number;
    }
}
