import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class WorkdayApp extends Application.AppBase {
    private var _view as WorkdayView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var v = new WorkdayView();
        _view = v;
        return [v];
    }

    // Called when you change settings in the Garmin Connect app on your phone.
    function onSettingsChanged() as Void {
        var v = _view;
        if (v != null) { v.loadSettings(); }
        WatchUi.requestUpdate();
    }
}
