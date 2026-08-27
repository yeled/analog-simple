import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Lang;
import Toybox.WatchUi;

//! Native watch face editor support, for devices that have one (fenix 8 and
//! newer, both Venu 4 sizes among them). Everything here touches APIs that
//! only exist at API level 5.1.0+, so the whole file is scoped to those
//! devices through monkey.jungle's sourcePath rather than guarded at
//! runtime — a `has` check wouldn't save the *compile* on a fenix 5 Plus.
//! source-nowfconfig/ holds the do-nothing twin for everyone else.

//! Read the style the user picked in the editor, or WF_STYLE_APP_SETTINGS
//! when nothing is saved yet. Defensive because it runs on every settings
//! refresh: a face that can't read its config should fall back to the phone
//! settings, not die.
function readWatchFaceStyle() {
    if (!(Toybox.Application has :WatchFaceConfig)) {
        return WF_STYLE_APP_SETTINGS;
    }
    try {
        var settings = WatchFaceConfig.getSettings(null);
        if (settings == null) {
            return WF_STYLE_APP_SETTINGS;
        }
        var styleId = settings.styleId;
        return (styleId == null) ? WF_STYLE_APP_SETTINGS : styleId;
    } catch (e) {
        return WF_STYLE_APP_SETTINGS;
    }
}

//! Delegate for the editing session, handed to the system only while the
//! face is launched from the editor.
function makeWatchFaceDelegate(view) {
    return new AnalogSimpleWatchFaceDelegate(view);
}

//! Receives edits as the user scrolls the editor's style carousel, so the
//! preview under the editor is the face they're actually choosing.
class AnalogSimpleWatchFaceDelegate extends WatchUi.WatchFaceDelegate {

    private var _view;

    function initialize(view) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onWatchFaceConfigEdited(options) {
        if (_view != null) {
            _view.onWatchFaceConfigUpdate();
        }
        WatchUi.requestUpdate();
    }
}
