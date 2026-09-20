using Toybox.Activity;
using Toybox.Application;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

// A playful visual companion. It does not make health or fueling decisions.
class FuelGuideField extends WatchUi.DataField {
    const SAMPLE_PERIOD_SECONDS = 5;
    const MAX_SAMPLES = 120;
    const DEFAULT_INTERVAL_SECONDS = 60;
    const MIN_INTERVAL_SECONDS = 30;
    const MAX_INTERVAL_SECONDS = 600;
    const MAX_CALLS = 120;
    const TIMEOUT_MS = 20000;
    const RATE_LIMIT_MS = 300000;
    const STALE_SECONDS = 180;
    const JEV_URL = "https://api.typesafe.ai/v1/systemone";
    var samples; var lastSampleSeconds; var lastTimerSeconds; var sessionId; var sessionNumber; var sequence; var callsThisSession;
    var inFlight; var pendingSequence; var pendingSessionId; var pendingSinceMs; var nextRequestMs; var disabled;
    var characterMood; var characterConfidence; var fromJev; var characterExpiresSeconds; var displayStatus; var buddyRenderer;

    function initialize() {
        DataField.initialize(); samples = []; lastSampleSeconds = null; lastTimerSeconds = null; sessionNumber = 0; sessionId = makeSessionId(); sequence = 0; callsThisSession = 0;
        inFlight = false; pendingSequence = null; pendingSessionId = null; pendingSinceMs = null; nextRequestMs = 0; disabled = false;
        characterMood = "calm"; characterConfidence = null; fromJev = false; characterExpiresSeconds = 0; displayStatus = sameText(networkMode(), "jev") ? "JEV WAITING" : "DEMO / NO API"; buddyRenderer = new BuddyRenderer();
    }
    function onTimerReset() { resetSession(); }
    function onTimerStop() { invalidatePendingRequest(); }
    function onTimerPause() { invalidatePendingRequest(); }
    function onTimerStart() { }
    function onTimerResume() { }

    function compute(info) {
        var elapsed = secondsFromInfo(info);
        if (lastTimerSeconds != null && elapsed < lastTimerSeconds) { resetSession(); }
        lastTimerSeconds = elapsed;
        if (info.timerState != Activity.TIMER_STATE_ON) { invalidatePendingRequest(); displayStatus = "PAUSED"; return; }
        if (lastSampleSeconds == null || elapsed - lastSampleSeconds >= SAMPLE_PERIOD_SECONDS) { appendSample(info, elapsed); lastSampleSeconds = elapsed; }
        expireCharacterIfNeeded(elapsed);
        checkTimeout(); requestIfDue(info, elapsed);
    }
    function onUpdate(dc) { var elapsed = lastTimerSeconds == null ? 0 : lastTimerSeconds; if (!sameText(networkMode(), "jev")) { elapsed = nowMs() / 1000; showDemo(elapsed); } buddyRenderer.draw(dc, characterMood, characterConfidence, displayStatus, fromJev, elapsed); }
    function secondsFromInfo(info) { return info.timerTime == null ? 0 : info.timerTime / 1000; }
    function nowMs() { return System.getTimer(); }
    function appendSample(info, elapsed) { samples.add({ :time => elapsed, :heartRate => info.currentHeartRate, :speed => info.currentSpeed, :cadence => info.currentCadence }); if (samples.size() > MAX_SAMPLES) { samples = samples.slice(1, null); } }

    function requestIfDue(info, elapsed) {
        if (!sameText(networkMode(), "jev")) { showDemo(elapsed); return; }
        var key = getApiKey();
        if (key == null || key.length() == 0) { displayStatus = "JEV NO KEY"; return; }
        if (disabled) { displayStatus = "JEV DISABLED"; return; }
        if (!ready(info, elapsed)) { displayStatus = "JEV WAITING"; return; }
        var now = nowMs(); if (inFlight || now < nextRequestMs) { return; }
        if (callsThisSession >= maxCalls()) { displayStatus = "JEV LIMIT"; return; }
        sequence += 1; callsThisSession += 1; inFlight = true; pendingSequence = sequence; pendingSessionId = sessionId; pendingSinceMs = now; nextRequestMs = now + intervalMs(); displayStatus = "JEV WAITING";
        var headers = { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON, "Authorization" => "Bearer " + key };
        var body = { "model" => "jev-latest", "state" => observedState(info, elapsed), "questions" => { "character_mood" => { "type" => "choice", "instructions" => "Choose a playful visual mood from observed running data, not a health or fatigue diagnosis. Missing values are unknown.", "criteria" => { "calm" => "low motion or relaxed rhythm", "steady" => "consistent motion and rhythm", "bouncy" => "lively or changing rhythm", "focused" => "sustained purposeful movement" } } } };
        var options = { :method => Communications.HTTP_REQUEST_METHOD_POST, :headers => headers, :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON, :context => { "sessionId" => sessionId, "sequence" => sequence } };
        try { sendRequest(body, headers, options); } catch (ex) { inFlight = false; pendingSinceMs = null; displayStatus = "JEV ERROR"; }
    }
    function sendRequest(body, headers, options) { Communications.makeWebRequest(JEV_URL, body, options, method(:onJevResponse)); }
    function showDemo(elapsed) { var moods = ["calm", "steady", "bouncy", "focused"]; characterMood = moods[(elapsed / 8).toNumber() % 4]; characterConfidence = null; fromJev = false; displayStatus = "DEMO / NO API"; }
    function ready(info, elapsed) { return samples.size() >= 4 && elapsed - samples[0][:time] >= 15 && (inRange(info.currentHeartRate, 20, 250) || inRange(info.currentSpeed, 0, 15) || inRange(info.currentCadence, 0, 300)); }
    function observedState(info, elapsed) { return "schemaVersion=1;sessionId=" + sessionId + ";sequence=" + sequence + ";elapsedSeconds=" + elapsed + ";heartRate=" + observedNumber(info.currentHeartRate, 20, 250) + ";speedMps=" + observedNumber(info.currentSpeed, 0, 15) + ";cadenceRpm=" + observedNumber(info.currentCadence, 0, 300) + ";sampleCount=" + samples.size() + ";windowSeconds=" + (samples.size() > 0 ? elapsed - samples[0][:time] : 0) + ";recentSamples=" + recentSamplesText(); }
    function textOf(value) { return value == null ? "null" : value.toString(); }
    function observedNumber(value, minimum, maximum) { return inRange(value, minimum, maximum) ? value.toString() : "unknown"; }
    function recentSamplesText() { var text = ""; var start = samples.size() > 6 ? samples.size() - 6 : 0; for (var i = start; i < samples.size(); i += 1) { var s = samples[i]; text += (i == start ? "" : "|") + "t=" + textOf(s[:time]) + ",hr=" + observedNumber(s[:heartRate], 20, 250) + ",speed=" + observedNumber(s[:speed], 0, 15) + ",cad=" + observedNumber(s[:cadence], 0, 300); } return text; }
    function expireCharacterIfNeeded(elapsed) { if (fromJev && characterExpiresSeconds > 0 && elapsed >= characterExpiresSeconds) { characterMood = "calm"; characterConfidence = null; fromJev = false; characterExpiresSeconds = 0; displayStatus = "JEV STALE"; } }

    function onJevResponse(code as Lang.Number, data as Null or Lang.Dictionary or Lang.String or Toybox.PersistedContent.Iterator, context as Lang.Object) as Void {
        if (!(context instanceof Lang.Dictionary) || !inFlight || !sameText(context["sessionId"], pendingSessionId) || context["sequence"] != pendingSequence || !sameText(pendingSessionId, sessionId)) { return; }
        var now = nowMs(); if (pendingSinceMs == null || now < pendingSinceMs || now - pendingSinceMs >= TIMEOUT_MS) { invalidatePendingRequest(); displayStatus = "JEV TIMEOUT"; return; }
        inFlight = false; pendingSinceMs = null;
        if (code == 401 || code == 403) { disabled = true; displayStatus = "JEV DISABLED"; return; }
        if (code == 429) { nextRequestMs = now + maximum(RATE_LIMIT_MS, intervalMs()); displayStatus = "JEV RATE LIMIT"; return; }
        var result = parseJevResponse(code, data);
        if (result == null) { displayStatus = "JEV ERROR"; return; }
        characterMood = result[:mood]; characterConfidence = result[:confidence]; fromJev = true; characterExpiresSeconds = (lastTimerSeconds == null ? 0 : lastTimerSeconds) + STALE_SECONDS; displayStatus = "JEV";
    }
    function parseJevResponse(code, data) {
        if (code != 200 || !(data instanceof Lang.Dictionary)) { return null; }
        var answers = data["answers"]; if (!(answers instanceof Lang.Dictionary)) { return null; }
        var answer = answers["character_mood"];
        if (!(answer instanceof Lang.Dictionary) || !sameText(answer["type"], "choice") || !inRange(answer["confidence"], 0, 1)) { return null; }
        var mood = answer["choice"];
        if (!sameText(mood, "calm") && !sameText(mood, "steady") && !sameText(mood, "bouncy") && !sameText(mood, "focused")) { return null; }
        return { :mood => mood, :confidence => answer["confidence"] };
    }
    function checkTimeout() { var now = nowMs(); if (inFlight && pendingSinceMs != null && now >= pendingSinceMs && now - pendingSinceMs >= TIMEOUT_MS) { invalidatePendingRequest(); displayStatus = "JEV TIMEOUT"; } }
    function networkMode() { var mode = Application.getApp().getProperty("networkMode"); return sameText(mode, "jev") ? "jev" : "offline"; }
    function getApiKey() { return Application.getApp().getProperty("jevApiKey"); }
    function intervalMs() { var value = Application.getApp().getProperty("requestIntervalSeconds"); return !inRange(value, MIN_INTERVAL_SECONDS, MAX_INTERVAL_SECONDS) || value != value.toNumber() ? DEFAULT_INTERVAL_SECONDS * 1000 : value * 1000; }
    function maxCalls() { var value = Application.getApp().getProperty("maxCallsPerSession"); return !inRange(value, 1, MAX_CALLS) || value != value.toNumber() ? MAX_CALLS : value; }
    function inRange(value, minimum, maximum) { return (value instanceof Lang.Number || value instanceof Lang.Long || value instanceof Lang.Float || value instanceof Lang.Double) && value >= minimum && value <= maximum; }
    function sameText(first, second) { return first instanceof Lang.String && second instanceof Lang.String && first.equals(second); }
    function maximum(first, second) { return first > second ? first : second; }
    function invalidatePendingRequest() { if (inFlight) { pendingSequence = -1; pendingSessionId = ""; pendingSinceMs = null; inFlight = false; Communications.cancelAllRequests(); } }
    function resetSession() { invalidatePendingRequest(); samples = []; lastSampleSeconds = null; lastTimerSeconds = null; sessionNumber += 1; sessionId = makeSessionId(); sequence = 0; callsThisSession = 0; nextRequestMs = 0; disabled = false; characterMood = "calm"; characterConfidence = null; fromJev = false; characterExpiresSeconds = 0; }
    function makeSessionId() { return Time.now().value().toString() + "-" + sessionNumber.toString(); }
}
