using Toybox.Graphics;
using Toybox.Application;
using Toybox.Math;

// Lightweight vector character: no image assets, extra timers, or network calls.
class BuddyRenderer {
    function initialize() {}
    function minimum(a, b) { return a < b ? a : b; }
    function maximum(a, b) { return a > b ? a : b; }

    function moodText(mood) {
        if ("calm".equals(mood)) { return Application.loadResource(Rez.Strings.MoodCalm); }
        if ("steady".equals(mood)) { return Application.loadResource(Rez.Strings.MoodSteady); }
        if ("bouncy".equals(mood)) { return Application.loadResource(Rez.Strings.MoodBouncy); }
        return Application.loadResource(Rez.Strings.MoodFocused);
    }

    function statusText(status) {
        if ("DEMO / NO API".equals(status)) { return Application.loadResource(Rez.Strings.StatusDemoNoApi); }
        if ("LOCAL DEMO".equals(status)) { return Application.loadResource(Rez.Strings.StatusLocalDemo); }
        if ("WAITING".equals(status)) { return Application.loadResource(Rez.Strings.StatusWaiting); }
        if ("PAUSED".equals(status)) { return Application.loadResource(Rez.Strings.StatusPaused); }
        if ("JEV WAITING".equals(status)) { return Application.loadResource(Rez.Strings.StatusJevWaiting); }
        if ("JEV NO KEY".equals(status)) { return Application.loadResource(Rez.Strings.StatusJevNoKey); }
        if ("JEV DISABLED".equals(status)) { return Application.loadResource(Rez.Strings.StatusJevDisabled); }
        if ("JEV LIMIT".equals(status)) { return Application.loadResource(Rez.Strings.StatusJevLimit); }
        if ("JEV TIMEOUT".equals(status)) { return Application.loadResource(Rez.Strings.StatusJevTimeout); }
        if ("JEV RATE LIMIT".equals(status)) { return Application.loadResource(Rez.Strings.StatusJevRateLimit); }
        if ("JEV ERROR".equals(status)) { return Application.loadResource(Rez.Strings.StatusJevError); }
        if ("JEV STALE".equals(status)) { return Application.loadResource(Rez.Strings.StatusJevStale); }
        return status;
    }

    function numberText(value, format) { return value == null ? "--" : value.toFloat().format(format); }

    function ageText(age) {
        if (age == null) { return Application.loadResource(Rez.Strings.WeatherAgeUnknown); }
        var amount = age < 3600 ? (age / 60).toNumber() : (age / 3600).toNumber();
        var unit = Application.loadResource(age < 3600 ? Rez.Strings.WeatherMinutesAgo : Rez.Strings.WeatherHoursAgo);
        var prefix = age > 21600 ? Application.loadResource(Rez.Strings.WeatherOld) : Application.loadResource(Rez.Strings.WeatherObserved);
        return prefix + " " + amount.toString() + unit;
    }

    function windText(environment) {
        var angle = environment["relativeWindFromDeg"];
        if (angle != null) {
            var labels = [Rez.Strings.WindFront, Rez.Strings.WindFrontRight, Rez.Strings.WindRight, Rez.Strings.WindBackRight, Rez.Strings.WindBack, Rez.Strings.WindBackLeft, Rez.Strings.WindLeft, Rez.Strings.WindFrontLeft];
            return Application.loadResource(labels[((angle + 22.5) / 45).toNumber() % 8]);
        }
        var age = environment["weatherAgeSeconds"];
        if (age == null || age > 21600 || environment["windSpeedMps"] == null) { return Application.loadResource(Rez.Strings.WindUnknown); }
        if (environment["windSpeedMps"] < 0.1) { return Application.loadResource(Rez.Strings.WindCalm); }
        if (environment["courseDeg"] == null) { return Application.loadResource(Rez.Strings.WindNeedsMovement); }
        return Application.loadResource(Rez.Strings.WindUnknown);
    }

    // Screen top is travel direction. The arrow points from the wind source toward Buddy.
    function drawWind(dc, cx, cy, radius, angle, compact) {
        if (angle == null || compact) { return; }
        var radians = angle * Math.PI / 180.0;
        var sx = Math.sin(radians); var sy = -Math.cos(radians);
        var inner = radius * 1.48;
        var outer = radius * (compact ? 1.85 : 1.90);
        var tipX = cx + sx * inner; var tipY = cy + sy * inner;
        dc.setColor(0xA8CFFF, Graphics.COLOR_BLACK);
        dc.setPenWidth(compact ? 2 : 3);
        // Parallel trails make the direction visible without covering the face.
        for (var offset = -1; offset <= 1; offset += 1) {
            var shift = offset * (compact ? 5 : 9);
            dc.drawLine(cx + sx * outer - sy * shift, cy + sy * outer + sx * shift, tipX - sy * shift, tipY + sx * shift);
        }
        var wing = compact ? 4 : 7;
        dc.drawLine(tipX, tipY, tipX + sx * wing - sy * wing, tipY + sy * wing + sx * wing);
        dc.drawLine(tipX, tipY, tipX + sx * wing + sy * wing, tipY + sy * wing - sx * wing);
        dc.setPenWidth(1);
    }

    function draw(dc, mood, confidence, status, fromJev, elapsedSeconds, environment) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var compact = h < 360;
        var radius = minimum(w * 0.22, h * (compact ? 0.18 : 0.115)).toNumber();
        var cx = (w / 2).toNumber();
        var phase = elapsedSeconds.toNumber() % 2;
        var bounce = "bouncy".equals(mood) ? (phase == 0 ? -6 : 2) : 0;
        var cy = (h * (compact ? 0.43 : 0.49)).toNumber() + bounce;
        var color = "calm".equals(mood) ? 0x9DB8FF : "steady".equals(mood) ? 0x7DE0C3 : "bouncy".equals(mood) ? 0xFFCB66 : 0xFF9DAB;
        dc.setColor(0xEAF0FF, Graphics.COLOR_BLACK);
        dc.clear();
        if (h < 140) {
            dc.drawText(cx, h * 0.12, Graphics.FONT_XTINY, moodText(mood), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, h * 0.52, Graphics.FONT_XTINY, windText(environment), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        if (!compact) {
            var heading = environment["relativeWindFromDeg"] == null ? "JEV BUDDY" : Application.loadResource(Rez.Strings.WindScreenUp);
            dc.drawText(cx, h * 0.055, environment["relativeWindFromDeg"] == null ? Graphics.FONT_TINY : Graphics.FONT_XTINY, heading, Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(0x7D899E, Graphics.COLOR_BLACK);
        dc.drawText(cx, h * (compact ? 0.01 : 0.13), Graphics.FONT_XTINY, statusText(status), Graphics.TEXT_JUSTIFY_CENTER);

        if (!compact) {
            dc.setColor(0xD2DCEB, Graphics.COLOR_BLACK);
            var weather = numberText(environment["temperatureC"], "%.0f") + "°C  " + numberText(environment["humidityPercent"], "%.0f") + "%  " + numberText(environment["windSpeedMps"], "%.1f") + "m/s";
            dc.drawText(cx, h * 0.205, Graphics.FONT_XTINY, weather, Graphics.TEXT_JUSTIFY_CENTER);
        }
        drawWind(dc, cx, cy, radius, environment["relativeWindFromDeg"], compact);

        // Feet and arms provide a distinct silhouette for each pose.
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.setPenWidth(maximum(2, radius / 10).toNumber());
        var stride = "steady".equals(mood) || "focused".equals(mood) ? (phase == 0 ? 8 : -8) : 0;
        dc.drawLine(cx - radius / 3, cy + radius - 2, cx - radius / 2 - stride, cy + radius + radius / 3);
        dc.drawLine(cx + radius / 3, cy + radius - 2, cx + radius / 2 + stride, cy + radius + radius / 3);
        var armRise = "bouncy".equals(mood) ? -radius / 2 : radius / 3;
        dc.drawLine(cx - radius + 3, cy + radius / 4, cx - radius - radius / 3, cy + armRise);
        dc.drawLine(cx + radius - 3, cy + radius / 4, cx + radius + radius / 3, cy + armRise);
        dc.fillCircle(cx, cy, radius);

        // The face remains readable on a full-screen running data page.
        dc.setColor(0x18243C, Graphics.COLOR_BLACK);
        var eyeX = radius / 3;
        var eyeY = cy - radius / 7;
        var eyeR = maximum(2, radius / 12).toNumber();
        dc.setPenWidth(maximum(2, radius / 18).toNumber());
        if ("calm".equals(mood)) {
            dc.drawLine(cx - eyeX - eyeR, eyeY, cx - eyeX + eyeR, eyeY);
            dc.drawLine(cx + eyeX - eyeR, eyeY, cx + eyeX + eyeR, eyeY);
        } else {
            dc.fillCircle(cx - eyeX, eyeY, eyeR);
            dc.fillCircle(cx + eyeX, eyeY, eyeR);
            if ("focused".equals(mood)) {
                dc.drawLine(cx - eyeX - eyeR * 2, eyeY - eyeR * 3, cx - eyeX + eyeR, eyeY - eyeR * 2);
                dc.drawLine(cx + eyeX - eyeR, eyeY - eyeR * 2, cx + eyeX + eyeR * 2, eyeY - eyeR * 3);
            }
        }
        var mouthY = cy + radius / 4;
        if ("bouncy".equals(mood)) {
            dc.fillCircle(cx, mouthY, maximum(3, radius / 8).toNumber());
        } else {
            dc.drawLine(cx - radius / 6, mouthY, cx, mouthY + radius / 12);
            dc.drawLine(cx, mouthY + radius / 12, cx + radius / 6, mouthY);
        }
        dc.setPenWidth(1);
        dc.setColor(color, Graphics.COLOR_BLACK);
        var moodLabel = moodText(mood);
        if (fromJev && confidence != null) {
            moodLabel += "  " + Application.loadResource(Rez.Strings.ConfidencePrefix) + " " + (confidence * 100).format("%.0f") + "%";
        }
        dc.drawText(cx, h * (compact ? 0.66 : 0.785), Graphics.FONT_XTINY, moodLabel, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0xA8CFFF, Graphics.COLOR_BLACK);
        dc.drawText(cx, h * (compact ? 0.83 : 0.71), Graphics.FONT_XTINY, windText(environment), Graphics.TEXT_JUSTIFY_CENTER);
        if (!compact) {
            dc.setColor(0xA8B3C7, Graphics.COLOR_BLACK);
            dc.drawText(cx, h * 0.86, Graphics.FONT_XTINY, ageText(environment["weatherAgeSeconds"]), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
