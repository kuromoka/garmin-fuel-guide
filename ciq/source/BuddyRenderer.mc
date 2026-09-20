using Toybox.Application;
using Toybox.Graphics;
using Toybox.Math;

// All marks are drawn locally. Screen top is the direction of travel.
class BuddyRenderer {
    function initialize() {}
    function minimum(a, b) { return a < b ? a : b; }
    function maximum(a, b) { return a > b ? a : b; }
    function moodText(mood, active) {
        if (!active) { return Application.loadResource(Rez.Strings.MoodResting); }
        if ("calm".equals(mood)) { return Application.loadResource(Rez.Strings.MoodCalm); }
        if ("steady".equals(mood)) { return Application.loadResource(Rez.Strings.MoodSteady); }
        if ("bouncy".equals(mood)) { return Application.loadResource(Rez.Strings.MoodBouncy); }
        return Application.loadResource(Rez.Strings.MoodFocused);
    }
    function drawWind(dc, cx, cy, radius, angle) {
        if (angle == null) { return; }
        var radians = angle * Math.PI / 180.0;
        var sx = Math.sin(radians); var sy = -Math.cos(radians);
        var inner = radius * 1.44; var outer = radius * 2.03;
        var tipX = cx + sx * inner; var tipY = cy + sy * inner;
        dc.setColor(0xA8CFFF, Graphics.COLOR_BLACK); dc.setPenWidth(maximum(3, radius * 0.065).toNumber());
        for (var offset = -1; offset <= 1; offset += 1) {
            var shift = offset * radius * 0.20;
            dc.drawLine(cx + sx * outer - sy * shift, cy + sy * outer + sx * shift, tipX - sy * shift, tipY + sx * shift);
        }
        var wing = radius * 0.18;
        dc.drawLine(tipX, tipY, tipX + sx * wing - sy * wing, tipY + sy * wing + sx * wing);
        dc.drawLine(tipX, tipY, tipX + sx * wing + sy * wing, tipY + sy * wing - sx * wing);
        dc.setPenWidth(1);
    }
    function draw(dc, mood, confidence, status, fromJev, elapsedSeconds, environment) {
        var w = dc.getWidth(); var h = dc.getHeight(); var compact = h < 240;
        dc.setColor(0xEDF3FF, Graphics.COLOR_BLACK); dc.clear();
        var hasJevMood = fromJev && ("JEV".equals(status) || "JEV WAITING".equals(status) || "JEV LIMIT".equals(status));
        var pose = hasJevMood ? mood : "calm";
        var radius = minimum(w * 0.19, h * 0.19).toNumber();
        var cx = (w / 2).toNumber(); var phase = elapsedSeconds.toNumber() % 2;
        var bounce = "bouncy".equals(pose) ? (phase == 0 ? -6 : 2) : 0;
        var cy = (h * 0.44).toNumber() + bounce;
        var color = !hasJevMood ? 0x78869B : "calm".equals(pose) ? 0x9DB8FF : "steady".equals(pose) ? 0x7DE0C3 : "bouncy".equals(pose) ? 0xFFCB66 : 0xFF9DAB;
        drawWind(dc, cx, cy, radius, environment["relativeWindFromDeg"]);
        dc.setColor(color, Graphics.COLOR_BLACK); dc.setPenWidth(maximum(2, radius / 10).toNumber());
        var stride = "steady".equals(pose) || "focused".equals(pose) ? (phase == 0 ? 8 : -8) : 0;
        dc.drawLine(cx - radius / 3, cy + radius - 2, cx - radius / 2 - stride, cy + radius + radius / 3);
        dc.drawLine(cx + radius / 3, cy + radius - 2, cx + radius / 2 + stride, cy + radius + radius / 3);
        var armRise = "bouncy".equals(pose) ? -radius / 2 : radius / 3;
        dc.drawLine(cx - radius + 3, cy + radius / 4, cx - radius - radius / 3, cy + armRise);
        dc.drawLine(cx + radius - 3, cy + radius / 4, cx + radius + radius / 3, cy + armRise);
        dc.fillCircle(cx, cy, radius);
        dc.setColor(0x18243C, Graphics.COLOR_BLACK);
        var eyeX = radius / 3; var eyeY = cy - radius / 7; var eyeR = maximum(2, radius / 12).toNumber();
        dc.setPenWidth(maximum(2, radius / 18).toNumber());
        if ("calm".equals(pose)) {
            dc.drawLine(cx - eyeX - eyeR, eyeY, cx - eyeX + eyeR, eyeY);
            dc.drawLine(cx + eyeX - eyeR, eyeY, cx + eyeX + eyeR, eyeY);
        } else {
            dc.fillCircle(cx - eyeX, eyeY, eyeR); dc.fillCircle(cx + eyeX, eyeY, eyeR);
            if ("focused".equals(pose)) {
                dc.drawLine(cx - eyeX - eyeR * 2, eyeY - eyeR * 3, cx - eyeX + eyeR, eyeY - eyeR * 2);
                dc.drawLine(cx + eyeX - eyeR, eyeY - eyeR * 2, cx + eyeX + eyeR * 2, eyeY - eyeR * 3);
            }
        }
        var mouthY = cy + radius / 4;
        if ("bouncy".equals(pose)) { dc.fillCircle(cx, mouthY, maximum(3, radius / 8).toNumber()); }
        else { dc.drawLine(cx - radius / 6, mouthY, cx, mouthY + radius / 12); dc.drawLine(cx, mouthY + radius / 12, cx + radius / 6, mouthY); }
        dc.setPenWidth(1);
        dc.setColor(hasJevMood ? color : 0xA0ABBC, Graphics.COLOR_BLACK);
        dc.drawText(cx, h * 0.86, compact ? Graphics.FONT_XTINY : Graphics.FONT_TINY,
            moodText(pose, hasJevMood), Graphics.TEXT_JUSTIFY_CENTER);
    }
}
