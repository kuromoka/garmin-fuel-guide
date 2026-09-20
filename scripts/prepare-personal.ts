import { cp, chmod, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { parseEnv } from "node:util";
import path from "node:path";
import { fileURLToPath } from "node:url";

type PersonalConfig = {
  relayUrl: string;
  relayIntervalSeconds: number;
};

export type PersonalBuildSettings = {
  relayUrl: string;
  relayToken: string;
  relayIntervalSeconds: number;
};

const usage = "Usage: node scripts/prepare-personal.ts [--project-dir <path>]";

class PersonalConfigError extends Error {}

function fail(message: string): never {
  throw new PersonalConfigError(message);
}

function xmlEscape(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function validateRelayUrl(value: unknown): string {
  if (typeof value !== "string") fail(".personal.json relayUrl must be a string.");
  if (value === "") return "";
  if (value.includes("?") || value.includes("#")) {
    fail(".personal.json relayUrl must be an HTTPS URL without credentials, query, or fragment.");
  }
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    fail(".personal.json relayUrl must be an absolute HTTPS URL.");
  }
  if (url.protocol !== "https:" || !url.hostname || url.username || url.password || url.search || url.hash) {
    fail(".personal.json relayUrl must be an HTTPS URL without credentials, query, or fragment.");
  }
  return url.toString().replace(/\/+$/, "");
}

function validateInterval(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 30 || value > 600) {
    fail(".personal.json relayIntervalSeconds must be an integer from 30 to 600.");
  }
  return value;
}

function validateToken(value: string | undefined): string {
  if (value === undefined || value.length === 0 || /[\u0000-\u001F\u007F\uD800-\uDFFF\uFFFE\uFFFF]/.test(value)) {
    fail("RELAY_TOKEN is required for a non-empty relayUrl and must not contain characters invalid in XML.");
  }
  return value;
}

async function loadEnvToken(projectDir: string, environment: NodeJS.ProcessEnv): Promise<string | undefined> {
  if (environment.RELAY_TOKEN !== undefined) return environment.RELAY_TOKEN;
  try {
    const env = parseEnv(await readFile(path.join(projectDir, ".env"), "utf8"));
    return env.RELAY_TOKEN;
  } catch (error: unknown) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw error;
  }
}

export async function loadPersonalSettings(projectDir: string, environment = process.env): Promise<PersonalBuildSettings> {
  const configPath = path.join(projectDir, ".personal.json");
  let config: PersonalConfig;
  try {
    config = JSON.parse(await readFile(configPath, "utf8")) as PersonalConfig;
  } catch {
    fail("Missing or invalid .personal.json. Copy .personal.example.json to .personal.json and fill in the relay settings.");
  }
  if (typeof config !== "object" || config === null || Array.isArray(config) || Object.getPrototypeOf(config) !== Object.prototype) {
    fail(".personal.json must contain an object.");
  }
  const relayUrl = validateRelayUrl(config.relayUrl);
  const relayIntervalSeconds = validateInterval(config.relayIntervalSeconds);
  const relayToken = relayUrl === "" ? "" : validateToken(await loadEnvToken(projectDir, environment));
  return { relayUrl, relayToken, relayIntervalSeconds };
}

function propertiesXml(settings: PersonalBuildSettings): string {
  return `<?xml version="1.0" encoding="UTF-8"?>\n<resources>\n    <properties>\n        <property id="relayUrl" type="string">${xmlEscape(settings.relayUrl)}</property>\n        <property id="relayToken" type="string">${xmlEscape(settings.relayToken)}</property>\n        <property id="relayIntervalSeconds" type="number">${settings.relayIntervalSeconds}</property>\n    </properties>\n</resources>\n`;
}

export async function preparePersonalProject(projectDir: string, environment = process.env): Promise<string> {
  const settings = await loadPersonalSettings(projectDir, environment);
  const ciqDir = path.join(projectDir, "ciq");
  const outputDir = path.join(ciqDir, "build", "personal-project");
  await rm(outputDir, { recursive: true, force: true });
  await mkdir(outputDir, { recursive: true, mode: 0o700 });
  await chmod(outputDir, 0o700);
  await Promise.all([
    cp(path.join(ciqDir, "source"), path.join(outputDir, "source"), { recursive: true }),
    cp(path.join(ciqDir, "resources"), path.join(outputDir, "resources"), { recursive: true }),
    cp(path.join(ciqDir, "manifest.xml"), path.join(outputDir, "manifest.xml")),
    cp(path.join(ciqDir, "monkey.jungle"), path.join(outputDir, "monkey.jungle")),
  ]);
  const generatedProperties = path.join(outputDir, "resources", "properties.xml");
  await writeFile(generatedProperties, propertiesXml(settings), { mode: 0o600 });
  await chmod(generatedProperties, 0o600);
  return outputDir;
}

function parseArguments(args: string[]): string {
  if (args.length === 0) return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  if (args.length === 2 && args[0] === "--project-dir") return path.resolve(args[1]);
  fail(usage);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  preparePersonalProject(parseArguments(process.argv.slice(2))).catch((error: unknown) => {
    console.error(error instanceof PersonalConfigError ? error.message : "Could not prepare personal build. Check local project files and try again.");
    process.exitCode = 1;
  });
}
