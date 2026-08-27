import Toybox.Lang;

//! The do-nothing twin of source-wfconfig/WatchFaceConfigSupport.mc, built
//! for every device without a native watch face editor. Same two entry
//! points, so the shared code can call them unconditionally; the editor's
//! APIs (WatchFaceConfig, WatchFaceDelegate.onWatchFaceConfigEdited) are
//! API level 5.1.0 and don't exist to be compiled against here.

//! No editor, so the style is always "leave the app settings alone".
function readWatchFaceStyle() {
    return WF_STYLE_APP_SETTINGS;
}

//! No editing session can start, so there is no delegate to hand back.
function makeWatchFaceDelegate(view) {
    return null;
}
