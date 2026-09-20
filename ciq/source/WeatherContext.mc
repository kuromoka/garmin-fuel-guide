using Toybox.Lang;
using Toybox.Math;
using Toybox.Time;
using Toybox.Weather;
using Toybox.Position;

// Wind bearings use the meteorological convention: the direction the wind comes FROM.
class WeatherContext {
    const REFRESH_SECONDS = 60;
    const MAX_RELATIVE_AGE_SECONDS = 21600;
    var temperatureC; var humidityPercent; var windSpeedMps; var windFromDeg; var observedAtSeconds; var courseDeg; var lastRefreshSeconds; var anchorLatitude; var anchorLongitude; var anchorSeconds; var lastCourseSeconds;

    function initialize() { temperatureC = null; humidityPercent = null; windSpeedMps = null; windFromDeg = null; observedAtSeconds = null; courseDeg = null; lastRefreshSeconds = null; anchorLatitude = null; anchorLongitude = null; anchorSeconds = null; lastCourseSeconds = null; }
    function refresh(nowSeconds) {
        if (lastRefreshSeconds != null && nowSeconds >= lastRefreshSeconds && nowSeconds - lastRefreshSeconds < REFRESH_SECONDS) { return; }
        lastRefreshSeconds = nowSeconds;
        try { ingest(Weather.getCurrentConditions(), nowSeconds); } catch (ex) { ingest(null, nowSeconds); }
    }
    function ingest(conditions, nowSeconds) {
        if (conditions == null) { temperatureC = null; humidityPercent = null; windSpeedMps = null; windFromDeg = null; observedAtSeconds = null; return; }
        var temp = conditionValue(conditions, "temperature"); var humidity = conditionValue(conditions, "relativeHumidity"); var wind = conditionValue(conditions, "windSpeed"); var bearing = conditionValue(conditions, "windBearing"); var observation = observationSeconds(conditionValue(conditions, "observationTime"));
        temperatureC = inRange(temp, -100, 100) ? temp : null; humidityPercent = inRange(humidity, 0, 100) ? humidity : null; windSpeedMps = inRange(wind, 0, 100) ? wind : null; windFromDeg = inRange(bearing, 0, 360) ? normalizeDegrees(bearing) : null; observedAtSeconds = observation;
    }
    function updateMovement(info, running, nowSeconds) {
        if (!running || !inRange(info.currentSpeed, 1, 15) || !inRange(info.currentLocationAccuracy, 3, 4) || !(info.currentLocation instanceof Position.Location)) { clearMovement(); return; }
        var radians = info.currentLocation.toRadians();
        if (radians == null || radians.size() != 2 || !inRange(radians[0], -Math.PI / 2, Math.PI / 2) || !inRange(radians[1], -Math.PI, Math.PI)) { clearMovement(); return; }
        if (anchorLatitude == null) { setAnchor(radians[0], radians[1], nowSeconds); return; }
        var deltaSeconds = nowSeconds - anchorSeconds;
        if (deltaSeconds == 0) { return; }
        if (deltaSeconds < 0 || deltaSeconds > 15) { clearMovement(); setAnchor(radians[0], radians[1], nowSeconds); return; }
        var deltaLongitude = radians[1] - anchorLongitude;
        while (deltaLongitude > Math.PI) { deltaLongitude -= Math.PI * 2; }
        while (deltaLongitude < -Math.PI) { deltaLongitude += Math.PI * 2; }
        var x = deltaLongitude * Math.cos((radians[0] + anchorLatitude) / 2) * 6371000;
        var y = (radians[0] - anchorLatitude) * 6371000;
        var distance = Math.sqrt(x * x + y * y);
        if (distance > 15 * deltaSeconds + 15) { clearMovement(); setAnchor(radians[0], radians[1], nowSeconds); return; }
        if (distance < 5) { if (lastCourseSeconds == null || nowSeconds - lastCourseSeconds > 10) { courseDeg = null; } return; }
        courseDeg = normalizeDegrees(Math.toDegrees(Math.atan2(x, y))); lastCourseSeconds = nowSeconds; setAnchor(radians[0], radians[1], nowSeconds);
    }
    function snapshot(nowSeconds) {
        var age = observedAtSeconds == null || nowSeconds < observedAtSeconds ? null : nowSeconds - observedAtSeconds;
        var validCourse = courseDeg == null || lastCourseSeconds == null || nowSeconds < lastCourseSeconds || nowSeconds - lastCourseSeconds > 10 ? null : courseDeg;
        var relative = age == null || age > MAX_RELATIVE_AGE_SECONDS || windSpeedMps == null || windSpeedMps < 0.1 || windFromDeg == null || validCourse == null ? null : normalizeDegrees(windFromDeg - validCourse);
        return { "temperatureC" => temperatureC, "humidityPercent" => humidityPercent, "windSpeedMps" => windSpeedMps, "windFromDeg" => windFromDeg, "weatherAgeSeconds" => age, "courseDeg" => validCourse, "relativeWindFromDeg" => relative };
    }
    function normalizeDegrees(value) { if (!inRange(value, -1000000, 1000000)) { return null; } var normalized = value - Math.floor(value / 360.0) * 360.0; return normalized < 0 ? normalized + 360.0 : normalized; }
    function setAnchor(latitude, longitude, nowSeconds) { anchorLatitude = latitude; anchorLongitude = longitude; anchorSeconds = nowSeconds; }
    function clearMovement() { courseDeg = null; anchorLatitude = null; anchorLongitude = null; anchorSeconds = null; lastCourseSeconds = null; }
    function observationSeconds(value) { if (value instanceof Time.Moment) { return value.value(); } return inRange(value, 0, 2147483647) ? value : null; }
    function conditionValue(conditions, key) { if (conditions instanceof Lang.Dictionary) { return conditions[key]; } if ("temperature".equals(key)) { return conditions.temperature; } if ("relativeHumidity".equals(key)) { return conditions.relativeHumidity; } if ("windSpeed".equals(key)) { return conditions.windSpeed; } if ("windBearing".equals(key)) { return conditions.windBearing; } return conditions.observationTime; }
    function inRange(value, minimum, maximum) { return (value instanceof Lang.Number || value instanceof Lang.Long || value instanceof Lang.Float || value instanceof Lang.Double) && value >= minimum && value <= maximum; }
}
