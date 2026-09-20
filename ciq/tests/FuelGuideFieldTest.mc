using Toybox.Test;

function choiceResponse(choice, confidence) { return { "answers" => { "character_mood" => { "type" => "choice", "choice" => choice, "confidence" => confidence } } }; }

class TestFuelGuideField extends FuelGuideField {
    var fakeNow;
    var capturedBody;
    var sent;
    function initialize() { FuelGuideField.initialize(); fakeNow = 1000; capturedBody = null; sent = 0; }
    function getApiKey() { return "test-key"; }
    function networkMode() { return "jev"; }
    function nowMs() { return fakeNow; }
    function maxCalls() { return 1; }
    function sendRequest(body, headers, options) { capturedBody = body; sent += 1; }
}

class TestInfo {
    var currentHeartRate; var currentSpeed; var currentCadence;
    function initialize() { currentHeartRate = 124; currentSpeed = 3.0; currentCadence = 170; }
}

(:test)
function choiceParserAcceptsAllMoods(logger) {
    var field = new FuelGuideField();
    var result = field.parseJevResponse(200, choiceResponse("bouncy", 0.0f));
    var focused = field.parseJevResponse(200, choiceResponse("focused", 1.0d));
    return result != null && field.sameText(result[:mood], "bouncy") && result[:confidence] == 0.0f && focused != null && field.sameText(focused[:mood], "focused");
}

(:test)
function choiceParserRejectsInvalidValues(logger) {
    var field = new FuelGuideField();
    return field.parseJevResponse(200, choiceResponse("hungry", 0.5)) == null && field.parseJevResponse(200, choiceResponse("calm", -0.1)) == null && field.parseJevResponse(200, choiceResponse("calm", 1.1)) == null;
}

(:test)
function decodedStringsCompareByContent(logger) {
    var field = new FuelGuideField();
    return field.sameText("jev".substring(0, 3), "jev") && !field.sameText("jev".substring(0, 3), "offline");
}

(:test)
function lateAndDuplicateCallbacksAreIgnored(logger) {
    var field = new FuelGuideField();
    field.inFlight = true; field.pendingSequence = 2; field.pendingSessionId = field.sessionId; field.pendingSinceMs = field.nowMs();
    field.onJevResponse(200, choiceResponse("steady", 0.5), { "sessionId" => field.sessionId, "sequence" => 1 });
    if (field.fromJev) { return false; }
    field.onJevResponse(200, choiceResponse("steady", 0.5), { "sessionId" => field.sessionId, "sequence" => 2 });
    if (!field.fromJev || !field.sameText(field.characterMood, "steady")) { return false; }
    field.onJevResponse(200, choiceResponse("bouncy", 0.5), { "sessionId" => field.sessionId, "sequence" => 2 });
    return field.sameText(field.characterMood, "steady");
}

(:test)
function pauseCancelsAndQuotaRemainsBounded(logger) {
    var field = new FuelGuideField();
    field.callsThisSession = 1; field.inFlight = true; field.pendingSequence = 1; field.pendingSessionId = field.sessionId; field.pendingSinceMs = field.nowMs();
    field.onTimerPause();
    return !field.inFlight && field.callsThisSession == 1 && field.maxCalls() <= 120 && field.maxCalls() >= 1;
}

(:test)
function staleChoiceClearsToCalm(logger) {
    var field = new FuelGuideField();
    field.characterMood = "focused"; field.characterConfidence = 0.7; field.fromJev = true; field.characterExpiresSeconds = 20;
    field.expireCharacterIfNeeded(20);
    return !field.fromJev && field.characterConfidence == null && field.sameText(field.characterMood, "calm") && field.sameText(field.displayStatus, "JEV STALE");
}

(:test)
function initializedCharacterDefaultsNeedNoSecondInitialize(logger) {
    var field = new FuelGuideField();
    return field.sameText(field.characterMood, "calm") && field.characterConfidence == null && !field.fromJev && field.callsThisSession == 0;
}

(:test)
function oneQuotaCapturesOneDirectChoiceRequest(logger) {
    var field = new TestFuelGuideField();
    field.samples = [
        { :time => 0, :heartRate => 120, :speed => 3.0, :cadence => 170 },
        { :time => 5, :heartRate => 121, :speed => 3.1, :cadence => 171 },
        { :time => 10, :heartRate => 122, :speed => 3.0, :cadence => 170 },
        { :time => 15, :heartRate => 123, :speed => 3.1, :cadence => 171 }
    ];
    var info = new TestInfo();
    field.requestIfDue(info, 20);
    if (field.sent != 1 || field.callsThisSession != 1 || field.capturedBody == null || !field.sameText(field.capturedBody["model"], "jev-latest") || field.capturedBody["state"] == null || field.capturedBody["state"].length() == 0) { return false; }
    var question = field.capturedBody["questions"]["character_mood"];
    if (!field.sameText(question["type"], "choice") || question["criteria"].size() != 4) { return false; }
    field.onJevResponse(500, null, { "sessionId" => field.sessionId, "sequence" => field.sequence });
    field.nextRequestMs = 0;
    field.requestIfDue(info, 21);
    return field.sent == 1 && field.callsThisSession == 1;
}

(:test)
function expiredAndPausedLateResponsesAreIgnored(logger) {
    var field = new TestFuelGuideField();
    field.inFlight = true; field.pendingSequence = 4; field.pendingSessionId = field.sessionId; field.pendingSinceMs = 0; field.fakeNow = 20001;
    field.onJevResponse(200, choiceResponse("focused", 0.5), { "sessionId" => field.sessionId, "sequence" => 4 });
    if (field.fromJev || !field.sameText(field.displayStatus, "JEV TIMEOUT")) { return false; }
    field.inFlight = true; field.pendingSequence = 5; field.pendingSessionId = field.sessionId; field.pendingSinceMs = field.fakeNow;
    field.onTimerPause();
    field.onJevResponse(200, choiceResponse("bouncy", 0.5), { "sessionId" => field.sessionId, "sequence" => 5 });
    return !field.fromJev && !field.sameText(field.characterMood, "bouncy");
}

class DisplayTestWeather extends WeatherContext {
    function refresh(nowSeconds) {}
    function updateMovement(info, running, nowSeconds) {}
}
class DisplayTestInfo extends TestInfo {
    var timerTime; var timerState;
    function initialize() { TestInfo.initialize(); timerTime = 20000; timerState = Toybox.Activity.TIMER_STATE_ON; }
}
(:test)
function resumedTimerRestoresCachedCharacterUntilExpiry(logger) {
    var field = new TestFuelGuideField();
    field.weatherContext = new DisplayTestWeather();
    field.nextRequestMs = 60000;
    field.samples = [
        { :time => 0, :heartRate => 120, :speed => 3.0, :cadence => 170 },
        { :time => 5, :heartRate => 121, :speed => 3.0, :cadence => 170 },
        { :time => 10, :heartRate => 122, :speed => 3.0, :cadence => 170 },
        { :time => 15, :heartRate => 123, :speed => 3.0, :cadence => 170 }
    ];
    field.characterMood = "focused"; field.fromJev = true; field.characterExpiresSeconds = 100;
    field.onTimerPause();
    if (!field.sameText(field.displayStatus, "PAUSED")) { return false; }
    var info = new DisplayTestInfo();
    field.compute(info);
    if (!field.fromJev || !field.sameText(field.displayStatus, "JEV")) { return false; }
    field.onTimerStop();
    if (!field.sameText(field.displayStatus, "PAUSED")) { return false; }
    info.timerTime = 100000;
    field.compute(info);
    return !field.fromJev && field.sameText(field.displayStatus, "JEV STALE");
}
