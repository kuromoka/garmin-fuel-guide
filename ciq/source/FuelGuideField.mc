using Toybox.Activity;
using Toybox.Application;
using Toybox.Communications;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

// This field only reports an experimental trend. It does not diagnose or alarm.
class FuelGuideField extends WatchUi.DataField {
    const SAMPLE_PERIOD_SECONDS = 5;
    const MAX_SAMPLES = 120;
    const TWO_MINUTES_SECONDS = 120;
    const DEFAULT_RELAY_INTERVAL_SECONDS = 60;
    const MIN_RELAY_INTERVAL_SECONDS = 30;
    const REQUEST_TIMEOUT_SECONDS = 20;

    var samples;
    var lastSampleSeconds;
    var lastTimerSeconds;
    var sessionId;
    var sessionNumber;
    var sequence;
    var inFlight;
    var pendingSequence;
    var pendingSessionId;
    var pendingSinceSeconds;
    var nextRelaySeconds;
    var relayBackoffSeconds;
    var relayStatus;
    var displayStatus;
    var candidate;
    var missingHeartRate;
    var missingSpeed;
    var missingCadence;
    var candidateExpiresSeconds;

    function initialize() {
        DataField.initialize();
        samples = [];
        lastSampleSeconds = null;
        lastTimerSeconds = null;
        sessionNumber = 0;
        sessionId = makeSessionId();
        sequence = 0;
        inFlight = false;
        pendingSequence = null;
        pendingSessionId = null;
        pendingSinceSeconds = null;
        nextRelaySeconds = 0;
        relayBackoffSeconds = 0;
        relayStatus = "RELAY OFF";
        displayStatus = "WAITING FOR DATA";
        candidate = "";
        missingHeartRate = 0;
        missingSpeed = 0;
        missingCadence = 0;
        candidateExpiresSeconds = 0;
    }

    function compute(info) {
        var elapsedSeconds = secondsFromInfo(info);
        var timerIsRunning = info.timerState == Activity.TIMER_STATE_ON;

        if (lastTimerSeconds != null && elapsedSeconds < lastTimerSeconds) {
            resetSession();
        }
        lastTimerSeconds = elapsedSeconds;

        if (!timerIsRunning) {
            invalidatePendingRequest();
            displayStatus = "TIMER STOPPED";
            candidate = "";
            return;
        }

        if (lastSampleSeconds == null || elapsedSeconds - lastSampleSeconds >= SAMPLE_PERIOD_SECONDS) {
            appendSample(info, elapsedSeconds);
            lastSampleSeconds = elapsedSeconds;
        }

        var summary = buildSummary(elapsedSeconds);
        displayStatus = statusFor(summary);
        if (summary[:hrDriftPercent] == null || summary[:validCount] < 48 || summary[:validCount] * 5 <= summary[:sampleCount] * 4 || info.currentHeartRate == null || info.currentCadence == null || info.currentSpeed == null || info.currentSpeed <= 0.5) {
            candidate = "";
        }
        if (candidateExpiresSeconds > 0 && elapsedSeconds >= candidateExpiresSeconds) {
            candidate = "";
            relayStatus = "RELAY STALE";
            candidateExpiresSeconds = 0;
        }
        checkTimedOutRequest(elapsedSeconds);
        requestRelayIfDue(elapsedSeconds, info, summary);
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var lineHeight = heightFor(dc) / 4;
        dc.drawText(width / 2, lineHeight / 2, Graphics.FONT_TINY, "FUEL GUIDE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, lineHeight + (lineHeight / 2), Graphics.FONT_TINY, displayStatus, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, (lineHeight * 2) + (lineHeight / 2), Graphics.FONT_TINY, relayStatus, Graphics.TEXT_JUSTIFY_CENTER);
        if (candidate != "") {
            dc.drawText(width / 2, (lineHeight * 3) + (lineHeight / 2), Graphics.FONT_TINY, candidate, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function secondsFromInfo(info) {
        if (info.timerTime == null) {
            return 0;
        }
        return info.timerTime / 1000;
    }

    function appendSample(info, elapsedSeconds) {
        var heartRate = info.currentHeartRate;
        var speed = info.currentSpeed;
        var cadence = info.currentCadence;
        if (heartRate == null) { missingHeartRate += 1; }
        if (speed == null) { missingSpeed += 1; }
        if (cadence == null) { missingCadence += 1; }

        samples.add({
            :time => elapsedSeconds,
            :heartRate => heartRate,
            :speed => speed,
            :cadence => cadence
        });
        if (samples.size() > MAX_SAMPLES) {
            samples = samples.slice(1, null);
        }
    }

    function buildSummary(elapsedSeconds) {
        var firstStart = elapsedSeconds - ((MAX_SAMPLES - 1) * SAMPLE_PERIOD_SECONDS);
        if (samples.size() > 0) {
            firstStart = samples[0][:time];
        }
        var firstEnd = firstStart + TWO_MINUTES_SECONDS;
        var recentStart = elapsedSeconds - TWO_MINUTES_SECONDS;
        var first = averagesFor(firstStart, firstEnd);
        var recent = averagesFor(recentStart, elapsedSeconds + SAMPLE_PERIOD_SECONDS);
        var validCount = validMovingCount();
        var windowsAreReady = first[:count] >= 12 && recent[:count] >= 12 && firstEnd <= recentStart;

        return {
            :sampleCount => samples.size(),
            :validCount => validCount,
            :windowSeconds => samples.size() > 0 ? elapsedSeconds - samples[0][:time] : 0,
            :hrDriftPercent => windowsAreReady ? normalizedHeartRateDrift(first, recent) : null,
            :cadenceCvPercent => windowsAreReady ? cadenceCoefficientOfVariation(recentStart) : null,
            :speedChangePercent => windowsAreReady ? percentChange(first[:speed], recent[:speed]) : null
        };
    }

    function averagesFor(startSeconds, endSeconds) {
        var heartRateTotal = 0.0;
        var heartRateCount = 0;
        var speedTotal = 0.0;
        var speedCount = 0;
        for (var i = 0; i < samples.size(); i += 1) {
            var sample = samples[i];
            if (sample[:time] < startSeconds || sample[:time] >= endSeconds || sample[:speed] == null || sample[:speed] <= 0.5 || sample[:heartRate] == null || sample[:heartRate] <= 0 || sample[:cadence] == null || sample[:cadence] <= 0) {
                continue;
            }
            heartRateTotal += sample[:heartRate];
            heartRateCount += 1;
            speedTotal += sample[:speed];
            speedCount += 1;
        }
        return {
            :heartRate => heartRateCount > 0 ? heartRateTotal / heartRateCount : null,
            :speed => speedCount > 0 ? speedTotal / speedCount : null,
            :count => speedCount
        };
    }

    function validMovingCount() {
        var count = 0;
        for (var i = 0; i < samples.size(); i += 1) {
            var sample = samples[i];
            if (sample[:heartRate] != null && sample[:heartRate] > 0 && sample[:speed] != null && sample[:speed] > 0.5 && sample[:cadence] != null && sample[:cadence] > 0) {
                count += 1;
            }
        }
        return count;
    }

    function cadenceCoefficientOfVariation(recentStart) {
        var total = 0.0;
        var count = 0;
        for (var i = 0; i < samples.size(); i += 1) {
            var sample = samples[i];
            if (sample[:time] >= recentStart && sample[:speed] != null && sample[:speed] > 0.5 && sample[:cadence] != null && sample[:cadence] > 0) {
                total += sample[:cadence];
                count += 1;
            }
        }
        if (count < 2) { return null; }
        var mean = total / count;
        var squaredDifferenceTotal = 0.0;
        for (var j = 0; j < samples.size(); j += 1) {
            var cadenceSample = samples[j];
            if (cadenceSample[:time] >= recentStart && cadenceSample[:speed] != null && cadenceSample[:speed] > 0.5 && cadenceSample[:cadence] != null && cadenceSample[:cadence] > 0) {
                var difference = cadenceSample[:cadence] - mean;
                squaredDifferenceTotal += difference * difference;
            }
        }
        return (Math.sqrt(squaredDifferenceTotal / count) / mean) * 100.0;
    }

    function percentChange(firstValue, recentValue) {
        if (firstValue == null || recentValue == null || firstValue == 0) {
            return null;
        }
        return ((recentValue - firstValue) / firstValue) * 100.0;
    }

    function normalizedHeartRateDrift(first, recent) {
        if (first[:heartRate] == null || recent[:heartRate] == null || first[:speed] == null || recent[:speed] == null || first[:speed] == 0 || recent[:speed] == 0) {
            return null;
        }
        return percentChange(first[:heartRate] / first[:speed], recent[:heartRate] / recent[:speed]);
    }

    function statusFor(summary) {
        if (summary[:validCount] < 12 || summary[:hrDriftPercent] == null) {
            return "COLLECTING " + summary[:validCount] + "/12";
        }
        return "EXPERIMENTAL TREND";
    }

    function requestRelayIfDue(elapsedSeconds, info, summary) {
        var relayUrl = Application.getApp().getProperty("relayUrl");
        if (relayUrl == null || relayUrl.length() == 0) {
            relayStatus = "RELAY OFF";
            return;
        }
        if (relayUrl.length() < 8 || relayUrl.substring(0, 8) != "https://") {
            relayStatus = "RELAY HTTPS ONLY";
            return;
        }
        if (inFlight || elapsedSeconds < nextRelaySeconds) {
            return;
        }

        sequence += 1;
        pendingSequence = sequence;
        pendingSessionId = sessionId;
        pendingSinceSeconds = elapsedSeconds;
        inFlight = true;
        relayStatus = "RELAY PENDING";
        var headers = {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON};
        var relayToken = Application.getApp().getProperty("relayToken");
        if (relayToken != null && relayToken.length() > 0) {
            headers["Authorization"] = "Bearer " + relayToken;
        }
        var body = {
            "schemaVersion" => 1,
            "sessionId" => sessionId,
            "sequence" => sequence,
            "elapsedSeconds" => elapsedSeconds,
            "heartRate" => info.currentHeartRate,
            "speedMps" => info.currentSpeed,
            "cadenceRpm" => info.currentCadence,
            "temperatureC" => null,
            "summary" => {
                "sampleCount" => summary[:sampleCount],
                "validCount" => summary[:validCount],
                "windowSeconds" => summary[:windowSeconds],
                "hrDriftPercent" => summary[:hrDriftPercent],
                "cadenceCvPercent" => summary[:cadenceCvPercent],
                "speedChangePercent" => summary[:speedChangePercent]
            }
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :context => {"sessionId" => sessionId, "sequence" => sequence}
        };
        Communications.makeWebRequest(relayUrl + "/evaluate", body, options, method(:onRelayResponse));
    }

    function onRelayResponse(responseCode as Lang.Number, data as Null or Lang.Dictionary or Lang.String or Toybox.PersistedContent.Iterator, context as Lang.Object) as Void {
        if (!(context instanceof Lang.Dictionary) || context["sessionId"] != pendingSessionId || context["sequence"] != pendingSequence) {
            return;
        }
        inFlight = false;
        pendingSinceSeconds = null;
        if (!isValidRelayResponse(responseCode, data)) {
            retryRelay();
            return;
        }
        relayBackoffSeconds = 0;
        nextRelaySeconds = (lastTimerSeconds == null ? 0 : lastTimerSeconds) + relayIntervalSeconds();
        var relayMode = data["mode"] == "jev" ? "JEV" : "MOCK";
        relayStatus = data["status"] == "experimental" ? relayMode + " " + data["fatigueLevel"] : relayMode + " NEEDS DATA";
        candidate = data["status"] == "experimental" ? candidateFor(data) : "";
        candidateExpiresSeconds = (lastTimerSeconds == null ? 0 : lastTimerSeconds) + 90;
    }

    function checkTimedOutRequest(elapsedSeconds) {
        if (inFlight && pendingSinceSeconds != null && elapsedSeconds - pendingSinceSeconds >= REQUEST_TIMEOUT_SECONDS) {
            invalidatePendingRequest();
            candidate = "";
            relayStatus = "RELAY TIMEOUT";
            retryRelay();
        }
    }

    function candidateFor(response) {
        if (response["notification"] == "review_carbs" && response["carbsCandidate"] == true) {
            return "REVIEW CARBS";
        }
        if (response["notification"] == "review_hydration" && response["hydrationCandidate"] == true) {
            return "REVIEW HYDRATION";
        }
        return "";
    }

    function isValidRelayResponse(responseCode, data) {
        if (responseCode != 200 || data == null || !(data instanceof Lang.Dictionary)) { return false; }
        if (data["schemaVersion"] != 1 || data["sessionId"] != sessionId || data["sequence"] != sequence || data["experimental"] != true) { return false; }
        if (data["status"] != "experimental" && data["status"] != "insufficient_data") { return false; }
        if (data["mode"] != "mock" && data["mode"] != "jev") { return false; }
        if (data["fatigueLevel"] != "low" && data["fatigueLevel"] != "medium" && data["fatigueLevel"] != "high" && data["fatigueLevel"] != "unknown") { return false; }
        if (data["hydrationCandidate"] != true && data["hydrationCandidate"] != false) { return false; }
        if (data["carbsCandidate"] != true && data["carbsCandidate"] != false) { return false; }
        return data["notification"] == "none" || data["notification"] == "review_hydration" || data["notification"] == "review_carbs";
    }

    function retryRelay() {
        relayBackoffSeconds = relayBackoffSeconds == 0 ? 30 : relayBackoffSeconds * 2;
        if (relayBackoffSeconds > 300) { relayBackoffSeconds = 300; }
        nextRelaySeconds = (lastTimerSeconds == null ? 0 : lastTimerSeconds) + relayBackoffSeconds;
        candidate = "";
        candidateExpiresSeconds = 0;
        relayStatus = "RELAY RETRY " + relayBackoffSeconds + "S";
    }

    function relayIntervalSeconds() {
        var configured = Application.getApp().getProperty("relayIntervalSeconds");
        if (configured == null || configured < MIN_RELAY_INTERVAL_SECONDS) {
            return DEFAULT_RELAY_INTERVAL_SECONDS;
        }
        return configured;
    }

    function invalidatePendingRequest() {
        if (inFlight) {
            pendingSequence = -1;
            pendingSessionId = "";
            inFlight = false;
            pendingSinceSeconds = null;
            Communications.cancelAllRequests();
        }
    }

    function resetSession() {
        invalidatePendingRequest();
        samples = [];
        lastSampleSeconds = null;
        sessionNumber += 1;
        sessionId = makeSessionId();
        sequence = 0;
        nextRelaySeconds = 0;
        relayBackoffSeconds = 0;
        candidate = "";
        candidateExpiresSeconds = 0;
    }

    function makeSessionId() {
        return Time.now().value().toString() + "-" + sessionNumber.toString();
    }

    function heightFor(dc) {
        return dc.getHeight();
    }
}
