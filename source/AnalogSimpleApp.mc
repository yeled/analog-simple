import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

class AnalogSimpleApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        registerRainFetch(false);
    }

    function onStop(state) {
    }

    // Background service that refreshes the rain forecast
    function getServiceDelegate() {
        return [ new RainServiceDelegate() ];
    }

    // Return the initial view of the watch face
    (:background_excluded)
    function getInitialView() {
        return [ new AnalogSimpleView() ];
    }

    // New app settings have been received so trigger a UI update
    function onSettingsChanged() {
        var locationChanged = invalidateCacheIfLocationChanged();
        registerRainFetch(locationChanged);
        WatchUi.requestUpdate();
    }

    // If the manual lat/long override has changed, drop the cached forecast so
    // the next fetch refreshes for the new location instead of serving stale
    // data for the old one. Returns true if the cache was invalidated.
    hidden function invalidateCacheIfLocationChanged() {
        var current = Application.Properties.getValue("LocationOverride");
        var currentStr = (current instanceof String) ? current : "";
        var applied = Application.Storage.getValue("loc_override_applied");
        var appliedStr = (applied instanceof String) ? applied : "";
        if (currentStr.equals(appliedStr)) {
            return false;
        }
        Application.Storage.deleteValue("rain_hourly");
        Application.Storage.deleteValue("cloud_low");
        Application.Storage.deleteValue("cloud_mid");
        Application.Storage.deleteValue("cloud_high");
        Application.Storage.deleteValue("rain_updated");
        Application.Storage.setValue("loc_override_applied", currentStr);
        return true;
    }

    // Register (or clear) the temporal event that drives the weather fetch.
    // When the cache was just invalidated (new location) or there is no data
    // yet, schedule the soonest allowed fetch (5 min is the platform floor for
    // background events); otherwise refresh every 15 minutes.
    hidden function registerRainFetch(fetchSoon) {
        if (!getBoolProperty("ShowRainForecast", true) && !getBoolProperty("ShowCloudCover", true)) {
            Background.deleteTemporalEvent();
            return;
        }
        var hasData = Application.Storage.getValue("rain_hourly") != null;
        var soon = fetchSoon || !hasData;
        Background.registerForTemporalEvent(new Time.Duration(soon ? 300 : 900));
    }

    hidden function getBoolProperty(key, defaultValue) {
        var v = Application.Properties.getValue(key);
        return (v != null) ? v : defaultValue;
    }

}
