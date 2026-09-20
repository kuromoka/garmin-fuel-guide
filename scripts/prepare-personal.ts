import { cp, chmod, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { parseEnv } from "node:util";
import path from "node:path";
import { fileURLToPath } from "node:url";

type PersonalConfig = {
  networkMode: "offline" | "jev";
  requestIntervalSeconds: number;
  maxCallsPerSession: number;
};

export type PersonalBuildSettings = PersonalConfig & { jevApiKey: string };
const usage = "Usage: node scripts/prepare-personal.ts [--project-dir <path>]";
class PersonalConfigError extends Error {}
const fail = (message: string): never => {
  throw new PersonalConfigError(message);
};
const xmlEscape = (value: string): string => value
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&apos;");
function validateMode(value: unknown): "offline" | "jev" {
  if (value !== "offline" && value !== "jev") fail(".personal.json networkMode must be either offline or jev.");
  return value as "offline" | "jev";
}
function validateInteger(value: unknown, property: "requestIntervalSeconds" | "maxCallsPerSession", minimum: number, maximum: number): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < minimum || value > maximum) fail(`.personal.json ${property} must be an integer from ${minimum} to ${maximum}.`);
  return value as number;
}
function validateApiKey(value: string | undefined): string {
  if (value === undefined || !/^[\x21-\x7E]+$/.test(value)) fail("TYPESAFE_API_KEY is required for networkMode jev and must use printable ASCII characters without spaces.");
  return value as string;
}
async function loadApiKey(projectDir: string, environment: NodeJS.ProcessEnv): Promise<string | undefined> {
  if (environment.TYPESAFE_API_KEY !== undefined) return environment.TYPESAFE_API_KEY;
  try {
    return parseEnv(await readFile(path.join(projectDir, ".env"), "utf8")).TYPESAFE_API_KEY;
  } catch (error: unknown) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw error;
  }
}
export async function loadPersonalSettings(projectDir: string, environment = process.env): Promise<PersonalBuildSettings> {
  let config = {} as PersonalConfig;
  try {
    config = JSON.parse(await readFile(path.join(projectDir, ".personal.json"), "utf8")) as PersonalConfig;
  } catch {
    fail("Missing or invalid .personal.json. Copy .personal.example.json to .personal.json and fill in the personal settings.");
  }
  if (typeof config !== "object" || config === null || Array.isArray(config) || Object.getPrototypeOf(config) !== Object.prototype) fail(".personal.json must contain an object.");
  if (Object.hasOwn(config, "relayUrl") || Object.hasOwn(config, "relayIntervalSeconds")) fail(".personal.json uses the retired relay configuration. Replace it with networkMode, requestIntervalSeconds, and maxCallsPerSession.");
  const networkMode = validateMode(config.networkMode);
  const requestIntervalSeconds = validateInteger(config.requestIntervalSeconds, "requestIntervalSeconds", 30, 600);
  const maxCallsPerSession = validateInteger(config.maxCallsPerSession, "maxCallsPerSession", 1, 120);
  const jevApiKey = networkMode === "jev" ? validateApiKey(await loadApiKey(projectDir, environment)) : "";
  return { networkMode, jevApiKey, requestIntervalSeconds, maxCallsPerSession };
}
function propertiesXml(settings: PersonalBuildSettings): string {
  return `<?xml version="1.0" encoding="UTF-8"?>\n<resources>\n    <properties>\n        <property id="networkMode" type="string">${settings.networkMode}</property>\n        <property id="jevApiKey" type="string">${xmlEscape(settings.jevApiKey)}</property>\n        <property id="requestIntervalSeconds" type="number">${settings.requestIntervalSeconds}</property>\n        <property id="maxCallsPerSession" type="number">${settings.maxCallsPerSession}</property>\n    </properties>\n</resources>\n`;
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
    cp(path.join(ciqDir, "resources-jpn"), path.join(outputDir, "resources-jpn"), { recursive: true }),
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
  return fail(usage);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  preparePersonalProject(parseArguments(process.argv.slice(2))).catch((error: unknown) => {
    console.error(error instanceof PersonalConfigError ? error.message : "Could not prepare personal build. Check local project files and try again.");
    process.exitCode = 1;
  });
}
