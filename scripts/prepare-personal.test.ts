import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { loadPersonalSettings, preparePersonalProject } from "./prepare-personal.ts";

const repoRoot = path.resolve(import.meta.dirname, "..");

async function fixture(config: unknown, env = "TYPESAFE_API_KEY=do-not-copy\nRELAY_TOKEN=from-dotenv-token\n"): Promise<string> {
  const dir = await mkdtemp(path.join(os.tmpdir(), "fuel-guide-personal-"));
  await writeFile(path.join(dir, ".personal.json"), JSON.stringify(config));
  await writeFile(path.join(dir, ".env"), env);
  const ciq = path.join(dir, "ciq");
  for (const item of ["source", "resources", "manifest.xml", "monkey.jungle"]) {
    const source = path.join(repoRoot, "ciq", item);
    const target = path.join(ciq, item);
    const { cp } = await import("node:fs/promises");
    await cp(source, target, { recursive: true });
  }
  return dir;
}

test("enabled build escapes values and keeps source properties unchanged", async (t) => {
  const dir = await fixture({ relayUrl: "https://relay.example.test/api/", relayIntervalSeconds: 60 }, "RELAY_TOKEN=xml&<>'\"token\nTYPESAFE_API_KEY=do-not-copy\n");
  t.after(() => rm(dir, { recursive: true, force: true }));
  await preparePersonalProject(dir, {});
  const generated = await readFile(path.join(dir, "ciq/build/personal-project/resources/properties.xml"), "utf8");
  const original = await readFile(path.join(dir, "ciq/resources/properties.xml"), "utf8");
  assert.match(generated, /https:\/\/relay\.example\.test\/api/);
  assert.match(generated, /xml&amp;&lt;&gt;&apos;&quot;token/);
  assert.doesNotMatch(generated, /TYPESAFE_API_KEY|do-not-copy/);
  assert.match(original, /<property id="relayUrl" type="string"><\/property>/);
  assert.equal((await stat(path.join(dir, "ciq/build/personal-project"))).mode & 0o777, 0o700);
  assert.equal((await stat(path.join(dir, "ciq/build/personal-project/resources/properties.xml"))).mode & 0o777, 0o600);
});

test("offline build ignores relay token", async (t) => {
  const dir = await fixture({ relayUrl: "", relayIntervalSeconds: 30 }, "RELAY_TOKEN=\u0000invalid\n");
  t.after(() => rm(dir, { recursive: true, force: true }));
  await preparePersonalProject(dir, {});
  const generated = await readFile(path.join(dir, "ciq/build/personal-project/resources/properties.xml"), "utf8");
  assert.match(generated, /relayToken" type="string"><\/property>/);
});

test("process RELAY_TOKEN takes priority over .env", async (t) => {
  const dir = await fixture({ relayUrl: "https://relay.example.test", relayIntervalSeconds: 600 });
  t.after(() => rm(dir, { recursive: true, force: true }));
  const settings = await loadPersonalSettings(dir, { RELAY_TOKEN: "process-token" });
  assert.equal(settings.relayToken, "process-token");
});

for (const [name, config] of [
  ["rejects malformed config", "not-json"],
  ["rejects non-HTTPS URL", { relayUrl: "http://relay.example.test", relayIntervalSeconds: 60 }],
  ["rejects URL credentials", { relayUrl: "https://user@relay.example.test", relayIntervalSeconds: 60 }],
  ["rejects URL query", { relayUrl: "https://relay.example.test?", relayIntervalSeconds: 60 }],
  ["rejects URL fragment", { relayUrl: "https://relay.example.test#", relayIntervalSeconds: 60 }],
  ["rejects invalid interval", { relayUrl: "", relayIntervalSeconds: 29 }],
  ["rejects null config", null],
] as const) {
  test(name, async (t) => {
    const dir = await mkdtemp(path.join(os.tmpdir(), "fuel-guide-personal-"));
    t.after(() => rm(dir, { recursive: true, force: true }));
    await writeFile(path.join(dir, ".personal.json"), typeof config === "string" ? config : JSON.stringify(config));
    await assert.rejects(() => loadPersonalSettings(dir, {}), /personal\.json/);
  });
}

test("requires a token for an enabled relay without exposing its value", async (t) => {
  const dir = await fixture({ relayUrl: "https://relay.example.test", relayIntervalSeconds: 60 }, "TYPESAFE_API_KEY=do-not-copy\n");
  t.after(() => rm(dir, { recursive: true, force: true }));
  await assert.rejects(() => preparePersonalProject(dir, {}), /RELAY_TOKEN is required/);
});

test("rejects token characters invalid in XML before generating output", async (t) => {
  const dir = await fixture({ relayUrl: "https://relay.example.test", relayIntervalSeconds: 60 }, "RELAY_TOKEN=bad\uFFFEtoken\n");
  t.after(() => rm(dir, { recursive: true, force: true }));
  await assert.rejects(() => preparePersonalProject(dir, {}), /invalid in XML/);
  const original = await readFile(path.join(dir, "ciq/resources/properties.xml"), "utf8");
  assert.match(original, /<property id="relayToken" type="string"><\/property>/);
});
