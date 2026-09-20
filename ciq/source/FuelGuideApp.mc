using Toybox.Application;
using Toybox.WatchUi;

class FuelGuideApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [new FuelGuideField()];
    }
}
