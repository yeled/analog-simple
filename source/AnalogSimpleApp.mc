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
        registerRainFetch();
        WatchUi.requestUpdate();
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
