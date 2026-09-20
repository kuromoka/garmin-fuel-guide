using Toybox.Test;
using Toybox.Math;
using Toybox.Time;
using Toybox.Position;

function closeEnough(first, second) { return first != null && second != null && (first - second).abs() < 0.01; }

class WeatherTestInfo {
    var currentSpeed; var currentLocationAccuracy; var currentLocation;
    function initialize() { currentSpeed = 2.0; currentLocationAccuracy = 3; currentLocation = location(0, 0); }
}

function location(latitude, longitude) { return new Position.Location({ :latitude => latitude, :longitude => longitude, :format => :degrees }); }
function movement(weather, info, first, second) { info.currentLocation = first; weather.updateMovement(info, true, 100); info.currentLocation = second; weather.updateMovement(info, true, 102); }

class WeatherStateInfo {
    var currentHeartRate; var currentSpeed; var currentCadence;
    function initialize() { currentHeartRate = 120; currentSpeed = 3.0; currentCadence = 170; }
}

(:test)
function windUsesCourseRelativeMeteorologicalFromAngle(logger) {
    var weather = new WeatherContext();
    weather.ingest({ "temperature" => 20, "relativeHumidity" => 40, "windSpeed" => 4.0, "windBearing" => 180, "observationTime" => 100 }, 100);
    var info = new WeatherTestInfo(); movement(weather, info, location(0, 0), location(0.0001, 0));
    var snapshot = weather.snapshot(102);
    return closeEnough(weather.normalizeDegrees(-10), 350) && closeEnough(snapshot["courseDeg"], 0) && closeEnough(snapshot["relativeWindFromDeg"], 180);
}

(:test)
function windCompassQuadrantsAndMissingCalmWind(logger) {
    var weather = new WeatherContext();
    var info = new WeatherTestInfo();
    var winds = [0, 90, 180, 270];
    for (var i = 0; i < winds.size(); i += 1) { weather.ingest({ "temperature" => 20, "relativeHumidity" => 40, "windSpeed" => 1.0, "windBearing" => winds[i], "observationTime" => 10 }, 10); movement(weather, info, location(0, 0), location(0.0001, 0)); if (!closeEnough(weather.snapshot(102)["relativeWindFromDeg"], winds[i])) { return false; } weather.clearMovement(); }
    weather.ingest({ "temperature" => 20, "relativeHumidity" => 40, "windSpeed" => 0.0, "windBearing" => 90, "observationTime" => 10 }, 10);
    movement(weather, info, location(0, 0), location(0.0001, 0));
    if (weather.snapshot(102)["relativeWindFromDeg"] != null) { return false; }
    weather.ingest({ "temperature" => 20, "relativeHumidity" => 40, "windBearing" => 90, "observationTime" => 10 }, 10);
    return weather.snapshot(102)["windSpeedMps"] == null && weather.snapshot(102)["relativeWindFromDeg"] == null;
}

(:test)
function movementHidesWindWhenSlowPausedOrPoorGps(logger) {
    var weather = new WeatherContext(); var info = new WeatherTestInfo();
    weather.updateMovement(info, false, 0);
    if (weather.snapshot(0)["courseDeg"] != null) { return false; }
    info.currentSpeed = 0.5; weather.updateMovement(info, true, 0);
    if (weather.snapshot(0)["courseDeg"] != null) { return false; }
    info.currentSpeed = 2.0; info.currentLocationAccuracy = 2; weather.updateMovement(info, true, 0);
    return weather.snapshot(0)["courseDeg"] == null;
}

(:test)
function weatherClearsMalformedAndRelativeWindExpires(logger) {
    var weather = new WeatherContext();
    weather.ingest({ "temperature" => 20, "relativeHumidity" => 40, "windSpeed" => 4.0, "windBearing" => 90, "observationTime" => 100 }, 100);
    var info = new WeatherTestInfo(); movement(weather, info, location(0, 0), location(0.0001, 0));
    weather.clearMovement();
    info.currentLocation = location(0, 0); weather.updateMovement(info, true, 21698);
    info.currentLocation = location(0.0001, 0); weather.updateMovement(info, true, 21700);
    if (!closeEnough(weather.snapshot(21700)["relativeWindFromDeg"], 90)) { return false; }
    var expired = weather.snapshot(21701);
    if (!closeEnough(expired["courseDeg"], 0) || expired["weatherAgeSeconds"] != 21601 || expired["relativeWindFromDeg"] != null) { return false; }
    weather.ingest({ "temperature" => 999, "relativeHumidity" => 101, "windSpeed" => -1, "windBearing" => 999, "observationTime" => 200 }, 200);
    var malformed = weather.snapshot(200);
    if (malformed["temperatureC"] != null || malformed["humidityPercent"] != null || malformed["windSpeedMps"] != null || malformed["windFromDeg"] != null) { return false; }
    weather.ingest(null, 201);
    return weather.snapshot(201)["weatherAgeSeconds"] == null;
}

(:test)
function observationAgeComesFromConditionsAndRejectsFutureOrMissingTime(logger) {
    var weather = new WeatherContext();
    weather.ingest({ "temperature" => 20, "relativeHumidity" => 40, "windSpeed" => 4.0, "windBearing" => 90, "observationTime" => new Time.Moment(50) }, 100);
    if (weather.snapshot(100)["weatherAgeSeconds"] != 50) { return false; }
    weather.ingest({ "temperature" => 20, "relativeHumidity" => 40, "windSpeed" => 4.0, "windBearing" => 90, "observationTime" => 200 }, 100);
    if (weather.snapshot(100)["weatherAgeSeconds"] != null) { return false; }
    weather.ingest({ "temperature" => 20, "relativeHumidity" => 40, "windSpeed" => 4.0, "windBearing" => 90 }, 100);
    return weather.snapshot(100)["weatherAgeSeconds"] == null;
}

(:test)
function fieldStateContainsWeatherButNoCoordinates(logger) {
    var field = new FuelGuideField();
    field.weatherContext.ingest({ "temperature" => 20, "relativeHumidity" => 40, "windSpeed" => 4.0, "windBearing" => 90, "observationTime" => field.wallClockSeconds() }, field.wallClockSeconds());
    var state = field.observedState(new WeatherStateInfo(), 20);
    if (state.find("temperatureC=20;") == null || state.find("humidityPercent=40;") == null || state.find("windSpeedMps=4") == null || state.find("windFromDeg=90") == null || state.find("relativeWindFromDeg=unknown") == null || state.find("latitude") != null || state.find("longitude") != null || state.find("location") != null) { return false; }
    var motion = new WeatherTestInfo();
    var now = field.wallClockSeconds();
    field.weatherContext.updateMovement(motion, true, now - 2);
    motion.currentLocation = location(0.0001, 0);
    field.weatherContext.updateMovement(motion, true, now);
    if (!closeEnough(field.weatherContext.snapshot(field.wallClockSeconds())["relativeWindFromDeg"], 90)) { return false; }
    field.onTimerPause();
    if (field.weatherContext.snapshot(field.wallClockSeconds())["relativeWindFromDeg"] != null) { return false; }
    field.weatherContext.ingest(null, field.wallClockSeconds());
    var unknown = field.observedState(new WeatherStateInfo(), 20);
    return unknown.find("temperatureC=unknown;") != null && unknown.find("weatherAgeSeconds=unknown;") != null;
}

(:test)
function gpsCourseUsesPositionsAndExpiresWithoutNewMovement(logger) {
    var weather = new WeatherContext(); var info = new WeatherTestInfo();
    var points = [location(0.0001, 0), location(0, 0.0001), location(-0.0001, 0), location(0, -0.0001)];
    for (var i = 0; i < points.size(); i += 1) {
        weather.clearMovement(); movement(weather, info, location(0, 0), points[i]);
        if (!closeEnough(weather.snapshot(102)["courseDeg"], i * 90)) { return false; }
        if (weather.snapshot(113)["courseDeg"] != null) { return false; }
    }
    return true;
}

(:test)
function gpsRejectsJitterJumpsMissingFixAndResetsBaseline(logger) {
    var weather = new WeatherContext(); var info = new WeatherTestInfo();
    movement(weather, info, location(0, 0), location(0.000001, 0));
    if (weather.snapshot(102)["courseDeg"] != null) { return false; }
    info.currentLocation = location(1, 1); weather.updateMovement(info, true, 103);
    if (weather.snapshot(103)["courseDeg"] != null) { return false; }
    info.currentLocation = null; weather.updateMovement(info, true, 104);
    if (weather.anchorLatitude != null || weather.snapshot(104)["courseDeg"] != null) { return false; }
    info.currentLocation = location(0, 0); weather.updateMovement(info, true, 105);
    info.currentLocation = location(0.0001, 0); weather.updateMovement(info, true, 107);
    if (!closeEnough(weather.snapshot(107)["courseDeg"], 0)) { return false; }
    weather.updateMovement(info, true, 107);
    return closeEnough(weather.snapshot(107)["courseDeg"], 0);
}
