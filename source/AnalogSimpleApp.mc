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
        registerRainFetch();
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
        invalidateCacheIfLocationChanged();
        registerRainFetch();
        WatchUi.requestUpdate();
    }

    // If the manual lat/long override has changed, drop the cached forecast so
    // the next fetch refreshes for the new location instead of serving stale
    // data for the old one.
    hidden function invalidateCacheIfLocationChanged() {
        var current = Application.Properties.getValue("LocationOverride");
        var currentStr = (current instanceof String) ? current : "";
        var applied = Application.Storage.getValue("loc_override_applied");
        var appliedStr = (applied instanceof String) ? applied : "";
        if (!currentStr.equals(appliedStr)) {
            Application.Storage.deleteValue("rain_hourly");
            Application.Storage.deleteValue("cloud_low");
            Application.Storage.deleteValue("cloud_mid");
            Application.Storage.deleteValue("cloud_high");
            Application.Storage.deleteValue("rain_updated");
            Application.Storage.setValue("loc_override_applied", currentStr);
        }
    }

    // Register (or clear) the temporal event that drives the rain fetch.
    // First run with no cached data fetches soon; afterwards, every 15 min.
    hidden function registerRainFetch() {
        if (!getBoolProperty("ShowRainForecast", true)) {
            Background.deleteTemporalEvent();
            return;
        }
        var hasData = Application.Storage.getValue("rain_hourly") != null;
        Background.registerForTemporalEvent(new Time.Duration(hasData ? 900 : 300));
    }

    hidden function getBoolProperty(key, defaultValue) {
        var v = Application.Properties.getValue(key);
        return (v != null) ? v : defaultValue;
    }

}
