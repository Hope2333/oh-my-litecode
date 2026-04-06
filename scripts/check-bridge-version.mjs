import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..');

const CONFIG_PATH = '.ai/system/ai-ltc-config.json';
const BRIDGE_PACKAGE_JSON = 'packages/bridge/package.json';

function parseVersion(raw) {
  const cleaned = raw.replace(/^v/, '');
  const match = cleaned.match(/^(\d+)\.(\d+)\.(\d+)/);
  if (!match) {
    return null;
  }
  return {
    major: Number.parseInt(match[1], 10),
    minor: Number.parseInt(match[2], 10),
    patch: Number.parseInt(match[3], 10),
    raw,
  };
}

async function check() {
  const configPath = path.join(repoRoot, CONFIG_PATH);
  const packagePath = path.join(repoRoot, BRIDGE_PACKAGE_JSON);

  let config;
  try {
    const raw = await fs.readFile(configPath, 'utf-8');
    config = JSON.parse(raw);
  } catch {
    console.error('Bridge version check: INCOMPATIBLE');
    console.error('  Reason: Cannot read .ai/system/ai-ltc-config.json');
    process.exit(1);
  }

  let packageJson;
  try {
    const raw = await fs.readFile(packagePath, 'utf-8');
    packageJson = JSON.parse(raw);
  } catch {
    console.error('Bridge version check: INCOMPATIBLE');
    console.error('  Reason: Cannot read packages/bridge/package.json');
    process.exit(1);
  }

  const frameworkVersion = config.framework_version;
  const bridgeVersion = packageJson.version;

  if (!frameworkVersion) {
    console.error('Bridge version check: INCOMPATIBLE');
    console.error('  Reason: framework_version not found in ai-ltc-config.json');
    process.exit(1);
  }

  const framework = parseVersion(frameworkVersion);
  const bridge = parseVersion(`v${bridgeVersion}`);

  if (!framework || !bridge) {
    console.error('Bridge version check: INCOMPATIBLE');
    console.error('  Reason: Cannot parse version strings');
    console.error(`    framework_version: ${frameworkVersion}`);
    console.error(`    bridge version: ${bridgeVersion}`);
    process.exit(1);
  }

  // Allow 0.x bridge during 1.x framework development
  const compatible = (framework.major !== 0 && bridge.major === 0)
    || (framework.major === 0 && bridge.major === 0 && framework.minor === bridge.minor)
    || (framework.major !== 0 && bridge.major !== 0 && framework.major === bridge.major && framework.minor === bridge.minor);

  if (compatible) {
    console.log('Bridge version check: COMPATIBLE');
    console.log(`  Framework: ${frameworkVersion}`);
    console.log(`  Bridge:    v${bridgeVersion}`);
    console.log(`  Drift:     ${framework.patch === bridge.patch ? 'none' : 'patch'}`);
    process.exit(0);
  } else {
    console.error('Bridge version check: INCOMPATIBLE');
    console.error(`  Framework: ${frameworkVersion} (v${framework.major}.${framework.minor}.x)`);
    console.error(`  Bridge:    v${bridgeVersion} (v${bridge.major}.${bridge.minor}.x)`);
    console.error(`  Drift:     ${framework.major !== bridge.major ? 'major' : 'minor'}`);
    process.exit(1);
  }
}

await check();
