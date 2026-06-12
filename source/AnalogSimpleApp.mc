import Toybox.Application;
import Toybox.WatchUi;

class AnalogSimpleApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    // Return the initial view of the watch face
    function getInitialView() {
        return [ new AnalogSimpleView() ];
    }

    // New app settings have been received so trigger a UI update
    function onSettingsChanged() {
        WatchUi.requestUpdate();
    }

}
