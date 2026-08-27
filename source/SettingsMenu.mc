import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! On-watch settings, hooked into the watch face picker: when this face is
//! selected in the Watch Face app, the same screen that offers Apply and
//! Delete grows a Settings entry, which the system serves by calling
//! AnalogSimpleApp.getSettingsView. Only the weather layers live here — the
//! phone app still owns colours, hands and everything else — because these
//! are the switches you actually want at the wrist when a stormy day turns
//! the face busy.
//!
//! Values read and write the same Application.Properties the phone settings
//! use, so the two stay one set of state; Garmin Connect merges on-watch
//! changes back on its next sync.
(:background_excluded)
class WeatherSettingsMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({ :title => WatchUi.loadResource(Rez.Strings.OnWatchMenuTitle) });
        addToggle(Rez.Strings.ShowRainForecastTitle, "ShowRainForecast", true);
        addToggle(Rez.Strings.ShowCloudCoverTitle, "ShowCloudCover", true);
        addToggle(Rez.Strings.CloudCoverRippleTitle, "CloudCoverRipple", true);
        addToggle(Rez.Strings.ShowWindTitle, "ShowWind", true);
        addToggle(Rez.Strings.ShowTemperatureTitle, "ShowTemperature", true);
        addToggle(Rez.Strings.ShowTempExtremesTitle, "ShowTempExtremes", false);
        addToggle(Rez.Strings.ShowWeatherInAODTitle, "ShowWeatherInAOD", false);
    }

    //! One toggle row, initialised from the property (falling back to the
    //! same default the drawing code uses). The property key doubles as the
    //! menu item id, so the delegate can write straight back.
    private function addToggle(label, key, defaultValue) {
        var value = Application.Properties.getValue(key);
        var enabled = (value != null) ? value : defaultValue;
        addItem(new WatchUi.ToggleMenuItem(
            WatchUi.loadResource(label), null, key, enabled, null));
    }
}

//! Writes toggles through to Application.Properties as they flip.
(:background_excluded)
class WeatherSettingsDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(menuItem) {
        if (menuItem instanceof ToggleMenuItem) {
            Application.Properties.setValue(menuItem.getId() as String, menuItem.isEnabled());
            // Run the same plumbing a phone-side settings push runs, so the
            // background fetch registration and the face's cached settings
            // both notice immediately.
            Application.getApp().onSettingsChanged();
        }
    }
}
