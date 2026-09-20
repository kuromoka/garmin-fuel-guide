using Toybox.Graphics;
using Toybox.Application;

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

    function draw(dc, mood, confidence, status, fromJev, elapsedSeconds) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var compact = h < 180;
        var radius = minimum(w * 0.22, h * (compact ? 0.22 : 0.19)).toNumber();
        var cx = (w / 2).toNumber();
        var phase = elapsedSeconds.toNumber() % 2;
        var bounce = "bouncy".equals(mood) ? (phase == 0 ? -6 : 2) : 0;
        var cy = (h * (compact ? 0.46 : 0.50)).toNumber() + bounce;
        var color = "calm".equals(mood) ? 0x9DB8FF : "steady".equals(mood) ? 0x7DE0C3 : "bouncy".equals(mood) ? 0xFFCB66 : 0xFF9DAB;
        dc.setColor(0xEAF0FF, Graphics.COLOR_BLACK);
        dc.clear();
        if (!compact) {
            dc.drawText(cx, h * 0.09, Graphics.FONT_TINY, "JEV BUDDY", Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(0x7D899E, Graphics.COLOR_BLACK);
        dc.drawText(cx, h * (compact ? 0.02 : 0.20), Graphics.FONT_XTINY, statusText(status), Graphics.TEXT_JUSTIFY_CENTER);

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
        dc.drawText(cx, h * (compact ? 0.80 : 0.77), Graphics.FONT_XTINY, moodText(mood), Graphics.TEXT_JUSTIFY_CENTER);
        if (!compact) {
            dc.setColor(0xA8B3C7, Graphics.COLOR_BLACK);
            var detail = fromJev && confidence != null ? Application.loadResource(Rez.Strings.ConfidencePrefix) + " " + (confidence * 100).format("%.0f") + "%" : ("DEMO / NO API".equals(status) ? Application.loadResource(Rez.Strings.StatusLocalDemo) : Application.loadResource(Rez.Strings.StatusWaiting));
            dc.drawText(cx, h * 0.87, Graphics.FONT_XTINY, detail, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
