import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";

const UPSTREAM_URL = "https://api.typesafe.ai/v1/systemone";
const MAX_BODY_BYTES = 8 * 1024;
const MIN_CALL_INTERVAL_MS = 30_000;
const NOTIFICATION_COOLDOWN_MS = 15 * 60_000;
const SESSION_TTL_MS = 60 * 60_000;
const MAX_SESSIONS = 128;
const MAX_REAL_CALLS = 120;

export type Mode = "mock" | "jev";
export type EvaluationRequest = {
  schemaVersion: 1; sessionId: string; sequence: number; elapsedSeconds: number;
  heartRate: number | null; speedMps: number | null; cadenceRpm: number | null; temperatureC: number | null;
  summary: { sampleCount: number; validCount: number; windowSeconds: number; hrDriftPercent: number | null; cadenceCvPercent: number | null; speedChangePercent: number | null };
};
export type EvaluationResponse = {
  schemaVersion: 1; sessionId: string; sequence: number; status: "experimental" | "insufficient_data";
  fatigueLevel: "low" | "medium" | "high" | "unknown"; hydrationCandidate: boolean; carbsCandidate: boolean;
  notification: "none" | "review_hydration" | "review_carbs"; experimental: true; mode: Mode;
};

type Session = { sequence: number; elapsedSeconds: number; touchedAt: number; hydrationStreak: number; carbsStreak: number };
type Decision = { fatigue: "low" | "medium" | "high" | "unknown"; hydration: boolean; carbs: boolean };
export type RelayOptions = { env?: Record<string, string | undefined>; fetch?: typeof fetch; now?: () => number };

function response(request: EvaluationRequest, mode: Mode, status: EvaluationResponse["status"], fatigueLevel: EvaluationResponse["fatigueLevel"] = "unknown", hydrationCandidate = false, carbsCandidate = false, notification: EvaluationResponse["notification"] = "none"): EvaluationResponse {
  return { schemaVersion: 1, sessionId: request.sessionId, sequence: request.sequence, status, fatigueLevel, hydrationCandidate, carbsCandidate, notification, experimental: true, mode };
}

function finite(value: unknown, min: number, max: number): value is number { return typeof value === "number" && Number.isFinite(value) && value >= min && value <= max; }
function nullableFinite(value: unknown, min: number, max: number): value is number | null { return value === null || finite(value, min, max); }
function integer(value: unknown, min: number, max: number): value is number { return Number.isInteger(value) && finite(value, min, max); }

export function validateRequest(value: unknown): EvaluationRequest | null {
  if (value === null || typeof value !== "object") return null;
  const v = value as Record<string, unknown>; const s = v.summary as Record<string, unknown> | null;
  if (v.schemaVersion !== 1 || typeof v.sessionId !== "string" || v.sessionId.length < 1 || v.sessionId.length > 128 || !integer(v.sequence, 0, 2_147_483_647) || !finite(v.elapsedSeconds, 0, 604_800) || !nullableFinite(v.heartRate, 20, 250) || !nullableFinite(v.speedMps, 0, 15) || !nullableFinite(v.cadenceRpm, 0, 300) || !nullableFinite(v.temperatureC, -50, 70) || s === null || typeof s !== "object") return null;
  if (!integer(s.sampleCount, 0, 120) || !integer(s.validCount, 0, 120) || s.validCount > s.sampleCount || !finite(s.windowSeconds, 0, 900) || !nullableFinite(s.hrDriftPercent, -100, 200) || !nullableFinite(s.cadenceCvPercent, 0, 200) || !nullableFinite(s.speedChangePercent, -100, 200)) return null;
  return { schemaVersion: 1, sessionId: v.sessionId, sequence: v.sequence, elapsedSeconds: v.elapsedSeconds, heartRate: v.heartRate, speedMps: v.speedMps, cadenceRpm: v.cadenceRpm, temperatureC: v.temperatureC, summary: { sampleCount: s.sampleCount, validCount: s.validCount, windowSeconds: s.windowSeconds, hrDriftPercent: s.hrDriftPercent, cadenceCvPercent: s.cadenceCvPercent, speedChangePercent: s.speedChangePercent } };
}

export function isSufficient(request: EvaluationRequest): boolean {
  const s = request.summary;
  return request.heartRate !== null && request.speedMps !== null && request.speedMps > 0 && request.cadenceRpm !== null && request.cadenceRpm > 0 && s.sampleCount >= 48 && s.validCount >= 48 && s.windowSeconds >= 240 && s.validCount / s.sampleCount > 0.8 && s.hrDriftPercent !== null && s.cadenceCvPercent !== null && s.speedChangePercent !== null;
}

export function mockDecision(request: EvaluationRequest): Decision {
  const s = request.summary;
  const drift = s.hrDriftPercent ?? 0, cadence = s.cadenceCvPercent ?? 0, speedDrop = Math.max(0, -(s.speedChangePercent ?? 0));
  const hydrationConfidence = Math.min(0.99, 0.55 + drift * 0.045 + speedDrop * 0.0125);
  const carbsConfidence = Math.min(0.99, 0.45 + speedDrop * 0.055 + cadence * 0.025 + drift * 0.01);
  const fatigue = drift >= 10 || speedDrop >= 10 ? "high" : drift >= 5 || cadence >= 8 || speedDrop >= 5 ? "medium" : "low";
  return { fatigue, hydration: hydrationConfidence > 0.85, carbs: carbsConfidence > 0.85 };
}

export function parseUpstream(value: unknown): Decision | null {
  if (value === null || typeof value !== "object") return null; const answers = (value as Record<string, unknown>).answers;
  if (answers === null || typeof answers !== "object") return null; const a = answers as Record<string, unknown>;
  const fatigue = a.fatigue_level as Record<string, unknown>, hydration = a.needs_hydration as Record<string, unknown>, carbs = a.needs_carbs as Record<string, unknown>;
  if (!fatigue || !hydration || !carbs || fatigue.type !== "score" || !finite(fatigue.score, 0, 2) || !finite(fatigue.confidence, 0, 1) || hydration.type !== "noul" || !finite(hydration.noul, 0, 1) || carbs.type !== "noul" || !finite(carbs.noul, 0, 1)) return null;
  const levels = ["low", "medium", "high"] as const;
  return { fatigue: fatigue.confidence > 0.85 ? levels[Math.round(fatigue.score)] : "unknown", hydration: hydration.noul > 0.85, carbs: carbs.noul > 0.85 };
}

function prompt(request: EvaluationRequest): string {
  return JSON.stringify({ model: "jev-latest", state: JSON.stringify(request), questions: {
    fatigue_level: { type: "score", instructions: "Classify only observable effort trends. This is experimental and non-diagnostic.", criteria: ["low: stable observable effort trend", "medium: rising heart-rate drift or increasing cadence/speed variability", "high: pronounced drift or deterioration across the observed window"] },
    needs_hydration: { type: "noul", instructions: "Fuel and fluid intake are unknown. Suggest only whether the athlete should review their personal hydration plan; do not recommend a dose." },
    needs_carbs: { type: "noul", instructions: "Fuel and fluid intake are unknown. Suggest only whether the athlete should review their personal carbohydrate plan; do not recommend a dose or bonk probability." }
  } });
}

export function createRelay(options: RelayOptions = {}) {
  const env = options.env ?? process.env, now = options.now ?? Date.now, fetcher = options.fetch ?? fetch;
  if (env.JEV_MODE !== undefined && env.JEV_MODE !== "mock" && env.JEV_MODE !== "jev") throw new Error("JEV_MODE must be mock or jev");
  const mode: Mode = env.JEV_MODE === "jev" ? "jev" : "mock";
  if (mode === "jev" && !env.TYPESAFE_API_KEY) throw new Error("TYPESAFE_API_KEY is required in jev mode");
  const sessions = new Map<string, Session>(); let lastCallAt = -Infinity, realCalls = 0, notificationAt = -Infinity, inFlight: Promise<Decision> | null = null;
  function clean(at: number) { for (const [id, session] of sessions) if (at - session.touchedAt > SESSION_TTL_MS) sessions.delete(id); while (sessions.size > MAX_SESSIONS) sessions.delete(sessions.keys().next().value as string); }
  function invalidate(sessionId?: string) { if (sessionId) { const session = sessions.get(sessionId); if (session) { session.hydrationStreak = 0; session.carbsStreak = 0; } return; } for (const session of sessions.values()) { session.hydrationStreak = 0; session.carbsStreak = 0; } }
  async function upstream(request: EvaluationRequest): Promise<Decision> {
    if (!env.TYPESAFE_API_KEY) throw new Error("TYPESAFE_API_KEY is required in jev mode");
    if (inFlight) throw new Error("upstream busy");
    const abort = new AbortController(); const timeout = setTimeout(() => abort.abort(), 10_000);
    inFlight = (async () => { try { const r = await fetcher(UPSTREAM_URL, { method: "POST", headers: { authorization: `Bearer ${env.TYPESAFE_API_KEY}`, "content-type": "application/json" }, body: prompt(request), signal: abort.signal }); if (!r.ok) throw new Error("upstream rejected request"); const parsed = parseUpstream(await r.json()); if (!parsed) throw new Error("malformed upstream response"); return parsed; } finally { clearTimeout(timeout); } })();
    try { return await inFlight; } finally { inFlight = null; }
  }
  async function evaluate(request: EvaluationRequest): Promise<{ code: number; body: EvaluationResponse }> {
    const at = now(); clean(at); const old = sessions.get(request.sessionId);
    if (old && (request.sequence <= old.sequence || request.elapsedSeconds <= old.elapsedSeconds)) { invalidate(request.sessionId); return { code: 409, body: response(request, mode, "insufficient_data") }; }
    sessions.set(request.sessionId, { sequence: request.sequence, elapsedSeconds: request.elapsedSeconds, touchedAt: at, hydrationStreak: old?.hydrationStreak ?? 0, carbsStreak: old?.carbsStreak ?? 0 }); clean(at);
    const clearStreak = () => { const current = sessions.get(request.sessionId); if (current) { current.hydrationStreak = 0; current.carbsStreak = 0; } };
    if (!isSufficient(request)) { clearStreak(); return { code: 200, body: response(request, mode, "insufficient_data") }; }
    let decision: Decision;
    try {
      if (mode === "mock") decision = mockDecision(request);
      else { if (at - lastCallAt < MIN_CALL_INTERVAL_MS || realCalls >= MAX_REAL_CALLS) { clearStreak(); return { code: 429, body: response(request, mode, "insufficient_data") }; } lastCallAt = at; realCalls++; decision = await upstream(request); if (now() - at > 15_000) { clearStreak(); return { code: 504, body: response(request, mode, "insufficient_data") }; } }
    } catch { clearStreak(); return { code: 502, body: response(request, mode, "insufficient_data") }; }
    const current = sessions.get(request.sessionId); if (!current || current.sequence !== request.sequence) return { code: 409, body: response(request, mode, "insufficient_data") };
    current.hydrationStreak = decision.hydration ? current.hydrationStreak + 1 : 0; current.carbsStreak = decision.carbs ? current.carbsStreak + 1 : 0;
    let notification: EvaluationResponse["notification"] = "none";
    if (at - notificationAt >= NOTIFICATION_COOLDOWN_MS) { if (current.hydrationStreak >= 2) notification = "review_hydration"; else if (current.carbsStreak >= 2) notification = "review_carbs"; if (notification !== "none") notificationAt = at; }
    return { code: 200, body: response(request, mode, "experimental", decision.fatigue, decision.hydration, decision.carbs, notification) };
  }
  return { evaluate, invalidate, mode };
}

async function readJson(request: IncomingMessage): Promise<unknown> { const parts: Buffer[] = []; let length = 0; for await (const part of request) { const chunk = Buffer.from(part); length += chunk.length; if (length > MAX_BODY_BYTES) throw new Error("body too large"); parts.push(chunk); } return JSON.parse(Buffer.concat(parts).toString("utf8")); }
function send(res: ServerResponse, status: number, body: unknown) { res.writeHead(status, { "content-type": "application/json", "cache-control": "no-store" }); res.end(JSON.stringify(body)); }
export function createHandler(options: RelayOptions = {}) {
  const relay = createRelay(options); const token = (options.env ?? process.env).RELAY_TOKEN;
  return async (req: IncomingMessage, res: ServerResponse) => { if (req.method === "GET" && req.url === "/health") return send(res, 200, { ok: true, mode: relay.mode }); if (req.method !== "POST" || req.url !== "/evaluate") return send(res, 404, { error: "not found" }); if (!token || req.headers.authorization !== `Bearer ${token}`) return send(res, 401, { error: "unauthorized" }); try { const raw = await readJson(req); const parsed = validateRequest(raw); if (!parsed) { const record = raw !== null && typeof raw === "object" ? raw as Record<string, unknown> : undefined; const id: string | undefined = typeof record?.sessionId === "string" ? record.sessionId : undefined; relay.invalidate(id); return send(res, 400, { error: "invalid request" }); } const result = await relay.evaluate(parsed); return send(res, result.code, result.body); } catch { relay.invalidate(); return send(res, 400, { error: "invalid request" }); } };
}
export function createRelayServer(options: RelayOptions = {}): Server { return createServer(createHandler(options)); }
if (import.meta.main) { const server = createRelayServer(); server.listen(Number(process.env.PORT ?? 8787), process.env.HOST ?? "127.0.0.1"); }
