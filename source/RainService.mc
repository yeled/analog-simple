import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Time;

//! Fetches the hourly precipitation amount (mm) forecast from Open-Meteo
//! using the ECMWF model and caches it for the watch face to draw.
//!
//! Stored to Application.Storage (shared between background and foreground),
//! each the next 12 hours starting at the current hour:
//!   "rain_hourly"  => Array<Float>   precipitation in mm
//!   "rain_chance"  => Array<Number>  precipitation probability 0-100
//!   "cloud_low"    => Array<Number>  low-altitude cloud cover 0-100
//!   "cloud_mid"    => Array<Number>  mid-altitude cloud cover 0-100
//!   "cloud_high"   => Array<Number>  high-altitude cloud cover 0-100
//!   "rain_updated" => Number         epoch seconds of the last good fetch
(:background)
class RainService {

    function initialize() {}

    function fetch(lat as Float, lon as Float) as Void {
        Communications.makeWebRequest(
            "https://api.open-meteo.com/v1/forecast",
            {
                "latitude"       => lat,
                "longitude"      => lon,
                "hourly"         => "precipitation,precipitation_probability,cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high",
                "models"         => "ecmwf_ifs",
                "timeformat"     => "unixtime",
                "forecast_hours"  => 13
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

        var cloudLow = hourly.get("cloud_cover_low") as Array?;
        var cloudMid = hourly.get("cloud_cover_mid") as Array?;
        var cloudHigh = hourly.get("cloud_cover_high") as Array?;
        var rainChance = hourly.get("precipitation_probability") as Array?;

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
        var chance = [] as Array<Number>; // precipitation probability 0-100
        var low = [] as Array<Number>;    // low-altitude cloud cover 0-100
        var mid = [] as Array<Number>;    // mid-altitude cloud cover 0-100
        var high = [] as Array<Number>;   // high-altitude cloud cover 0-100
        for (var i = start; i < times.size() && rain.size() < 13; i++) {
            var mm = precip[i];
            rain.add(mm == null ? 0.0 : (mm as Float).toFloat());
            chance.add(num(rainChance, i));
            low.add(num(cloudLow, i));
            mid.add(num(cloudMid, i));
            high.add(num(cloudHigh, i));
        }

        Application.Storage.setValue("rain_hourly", rain);
        Application.Storage.setValue("rain_chance", chance);
        Application.Storage.setValue("cloud_low", low);
        Application.Storage.setValue("cloud_mid", mid);
        Application.Storage.setValue("cloud_high", high);
        Application.Storage.setValue("rain_updated", now);
    }

    // Read array[i] as a Number, defaulting to 0 when missing/null.
    hidden function num(arr as Array?, i as Number) as Number {
        if (arr == null || i >= arr.size() || arr[i] == null) { return 0; }
        return arr[i] as Number;
    }
}
