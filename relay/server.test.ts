import assert from "node:assert/strict";
import test from "node:test";
import { createRelay, createRelayServer, parseUpstream, validateRequest } from "./server.ts";

const base = () => ({ schemaVersion: 1 as const, sessionId: "run-1", sequence: 1, elapsedSeconds: 300, heartRate: 150, speedMps: 3, cadenceRpm: 170, temperatureC: null, summary: { sampleCount: 60, validCount: 60, windowSeconds: 300, hrDriftPercent: 12, cadenceCvPercent: 12, speedChangePercent: -12 } });

test("rejects malformed, non-finite, out-of-range, and missing samples", async () => {
  assert.equal(validateRequest({}), null);
  assert.equal(validateRequest({ ...base(), heartRate: Infinity }), null);
  assert.equal(validateRequest({ ...base(), speedMps: 99 }), null);
  assert.equal("gps" in (validateRequest({ ...base(), gps: "private" }) as object), false);
  const relay = createRelay({ env: { JEV_MODE: "mock" } });
  assert.equal((await relay.evaluate({ ...base(), heartRate: null })).body.status, "insufficient_data");
});

test("mock mode honours strict Noul confidence boundary", async () => {
  const relay = createRelay({ env: { JEV_MODE: "mock" } });
  const boundary = { ...base(), summary: { ...base().summary, hrDriftPercent: 6.5, speedChangePercent: 0, cadenceCvPercent: 0 } };
  assert.equal((await relay.evaluate(boundary)).body.hydrationCandidate, false);
  const over = { ...boundary, sequence: 2, elapsedSeconds: 301, summary: { ...boundary.summary, hrDriftPercent: 7 } };
  assert.equal((await relay.evaluate(over)).body.hydrationCandidate, true);
});

test("sequence races and confirmation/cooldown suppress duplicate notifications", async () => {
  let clock = 0; const relay = createRelay({ env: { JEV_MODE: "mock" }, now: () => clock });
  const first = await relay.evaluate(base()); assert.equal(first.body.notification, "none");
  const second = await relay.evaluate({ ...base(), sequence: 2, elapsedSeconds: 301 }); assert.equal(second.body.notification, "review_hydration");
  const old = await relay.evaluate(base()); assert.equal(old.code, 409);
  const third = await relay.evaluate({ ...base(), sequence: 3, elapsedSeconds: 302 }); assert.equal(third.body.notification, "none");
  clock += 15 * 60_000; const fourth = await relay.evaluate({ ...base(), sequence: 4, elapsedSeconds: 303 }); assert.equal(fourth.body.notification, "review_hydration");
});

test("upstream response shape is strict", () => {
  const response = { answers: { fatigue_level: { type: "score", score: 2, confidence: .9 }, needs_hydration: { type: "noul", noul: .9 }, needs_carbs: { type: "noul", noul: .2 } } };
  assert.equal(parseUpstream(response)?.fatigue, "high");
  assert.equal(parseUpstream({ answers: { ...response.answers, fatigue_level: { type: "score", score: 1.43, confidence: .9 } } })?.fatigue, "medium");
  assert.equal(parseUpstream({ answers: { ...response.answers, fatigue_level: { type: "score", score: 2, confidence: .85 } } })?.fatigue, "unknown");
  assert.equal(parseUpstream({ fatigue_level: { value: "bad", confidence: .9 } }), null);
});

test("HTTP requires bearer token and supports a mocked end-to-end request", async () => {
  const server = createRelayServer({ env: { JEV_MODE: "mock", RELAY_TOKEN: "test-token" } });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address !== "string"); const url = `http://127.0.0.1:${address.port}`;
  const unauthorized = await fetch(`${url}/evaluate`, { method: "POST", body: JSON.stringify(base()) }); assert.equal(unauthorized.status, 401);
  const accepted = await fetch(`${url}/evaluate`, { method: "POST", headers: { authorization: "Bearer test-token", "content-type": "application/json" }, body: JSON.stringify(base()) }); assert.equal(accepted.status, 200); assert.equal((await accepted.json()).mode, "mock");
  await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
});

test("an invalid authenticated sample clears a prior notification confirmation", async () => {
  const server = createRelayServer({ env: { JEV_MODE: "mock", RELAY_TOKEN: "test-token" } });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address !== "string"); const url = `http://127.0.0.1:${address.port}/evaluate`;
  const post = (body: unknown) => fetch(url, { method: "POST", headers: { authorization: "Bearer test-token", "content-type": "application/json" }, body: JSON.stringify(body) });
  assert.equal((await post(base())).status, 200);
  assert.equal((await post({ ...base(), sequence: 2, elapsedSeconds: 301, speedMps: 99 })).status, 400);
  const afterInvalid = await post({ ...base(), sequence: 3, elapsedSeconds: 302 }); assert.equal((await afterInvalid.json()).notification, "none");
  const confirmed = await post({ ...base(), sequence: 4, elapsedSeconds: 303 }); assert.equal((await confirmed.json()).notification, "review_hydration");
  await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
});

test("jev mode sends the official request shape and rejects malformed responses", async () => {
  let requestBody: unknown;
  const relay = createRelay({ env: { JEV_MODE: "jev", TYPESAFE_API_KEY: "test" }, fetch: async (_url, init) => { requestBody = JSON.parse(String(init?.body)); return new Response("{}", { status: 200 }); } });
  assert.equal((await relay.evaluate(base())).code, 502);
  assert.deepEqual(requestBody, { model: "jev-latest", state: JSON.stringify(base()), questions: {
    fatigue_level: { type: "score", instructions: "Classify only observable effort trends. This is experimental and non-diagnostic.", criteria: ["low: stable observable effort trend", "medium: rising heart-rate drift or increasing cadence/speed variability", "high: pronounced drift or deterioration across the observed window"] },
    needs_hydration: { type: "noul", instructions: "Fuel and fluid intake are unknown. Suggest only whether the athlete should review their personal hydration plan; do not recommend a dose." },
    needs_carbs: { type: "noul", instructions: "Fuel and fluid intake are unknown. Suggest only whether the athlete should review their personal carbohydrate plan; do not recommend a dose or bonk probability." }
  } });
});

test("suppresses missing summary trends and fewer than 48 valid samples", async () => {
  const relay = createRelay({ env: { JEV_MODE: "mock" } });
  assert.equal((await relay.evaluate({ ...base(), summary: { ...base().summary, validCount: 47 } })).body.status, "insufficient_data");
  assert.equal((await relay.evaluate({ ...base(), sequence: 2, elapsedSeconds: 301, summary: { ...base().summary, hrDriftPercent: null } })).body.status, "insufficient_data");
});

test("invalid mode throws and Jev fetch observes the 10 second AbortSignal timeout", { timeout: 12_000 }, async () => {
  assert.throws(() => createRelay({ env: { JEV_MODE: "real" } }));
  let aborted = false;
  const relay = createRelay({ env: { JEV_MODE: "jev", TYPESAFE_API_KEY: "test" }, fetch: async (_url, init) => await new Promise<Response>((_resolve, reject) => init?.signal?.addEventListener("abort", () => { aborted = true; reject(new Error("aborted")); }, { once: true })) });
  assert.equal((await relay.evaluate(base())).code, 502);
  assert.equal(aborted, true);
});
