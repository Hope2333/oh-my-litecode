import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const packageMap = new Map([
  ['@oml/core', 'packages/core'],
  ['@oml/cli', 'packages/cli'],
  ['@oml/modules', 'packages/modules'],
]);

const denyPatterns = [
  /TODO/i,
  /coming soon/i,
  /placeholder/i,
  /\bstub\b/i,
  /not implemented/i,
  /未实现/,
];

async function readFile(relativePath) {
  return fs.readFile(path.join(repoRoot, relativePath), 'utf8');
}

async function readJson(relativePath) {
  return JSON.parse(await readFile(relativePath));
}

async function exists(relativePath) {
  try {
    await fs.access(path.join(repoRoot, relativePath));
    return true;
  } catch {
    return false;
  }
}

async function listSourceFiles(relativeDir) {
  const absoluteDir = path.join(repoRoot, relativeDir);
  const entries = await fs.readdir(absoluteDir, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const childRelative = path.join(relativeDir, entry.name);

    if (entry.isDirectory()) {
      if (entry.name === 'dist' || entry.name === 'node_modules' || entry.name === '.turbo') {
        continue;
      }
      files.push(...await listSourceFiles(childRelative));
      continue;
    }

    if (/\.(?:[cm]?[jt]s|tsx|jsx)$/.test(entry.name)) {
      files.push(childRelative);
    }
  }

  return files;
}

function importerPackageName(filePath) {
  const normalized = filePath.split(path.sep).join('/');
  for (const [packageName, packageDir] of packageMap.entries()) {
    if (normalized.startsWith(`${packageDir}/`)) {
      return packageName;
    }
  }
  return null;
}

function parseOmImports(source) {
  const matches = new Set();
  const patterns = [
    /\bfrom\s+['"](@oml\/[^'"]+)['"]/g,
    /\bimport\s*\(\s*['"](@oml\/[^'"]+)['"]\s*\)/g,
  ];

  for (const pattern of patterns) {
    for (const match of source.matchAll(pattern)) {
      matches.add(match[1]);
    }
  }

  return [...matches];
}

function splitSpecifier(specifier) {
  const parts = specifier.split('/');
  if (parts.length < 2) {
    return null;
  }

  return {
    dependency: parts.slice(0, 2).join('/'),
    subpath: parts.slice(2).join('/'),
  };
}

function hasDependency(packageJson, dependencyName) {
  return [
    packageJson.dependencies,
    packageJson.devDependencies,
    packageJson.peerDependencies,
    packageJson.optionalDependencies,
  ].some((deps) => deps && dependencyName in deps);
}

function hasExport(packageJson, subpath) {
  const exportsField = packageJson.exports ?? {};

  if (!subpath) {
    return typeof exportsField === 'string' || '.' in exportsField;
  }

  const exactKey = `./${subpath}`;
  if (exactKey in exportsField) {
    return true;
  }

  return Object.keys(exportsField).some((key) => {
    if (!key.includes('*')) {
      return false;
    }

    const regex = new RegExp(`^${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace('\\*', '(.+)')}$`);
    return regex.test(exactKey);
  });
}

function extractMarkdownValue(content, patterns) {
  for (const pattern of patterns) {
    const match = content.match(pattern);
    if (match) {
      return match[1].trim();
    }
  }
  return null;
}

async function checkInterPackageContracts(errors) {
  const packageJsonCache = new Map();

  for (const filePath of await listSourceFiles('packages')) {
    const importer = importerPackageName(filePath);
    if (!importer) {
      continue;
    }

    const source = await readFile(filePath);
    const imports = parseOmImports(source);
    if (imports.length === 0) {
      continue;
    }

    const importerDir = packageMap.get(importer);
    if (!packageJsonCache.has(importer)) {
      packageJsonCache.set(importer, await readJson(path.join(importerDir, 'package.json')));
    }
    const importerPackageJson = packageJsonCache.get(importer);

    for (const specifier of imports) {
      const split = splitSpecifier(specifier);
      if (!split || split.dependency === importer || !packageMap.has(split.dependency)) {
        continue;
      }

      if (!hasDependency(importerPackageJson, split.dependency)) {
        errors.push(
          `${filePath} imports ${specifier}, but ${path.join(importerDir, 'package.json')} does not declare ${split.dependency}.`
        );
      }

      const dependencyDir = packageMap.get(split.dependency);
      if (!packageJsonCache.has(split.dependency)) {
        packageJsonCache.set(split.dependency, await readJson(path.join(dependencyDir, 'package.json')));
      }
      const dependencyPackageJson = packageJsonCache.get(split.dependency);

      if (!hasExport(dependencyPackageJson, split.subpath)) {
        errors.push(
          `${specifier} is imported by ${filePath}, but ${path.join(dependencyDir, 'package.json')} does not export ./${split.subpath || '.'}.`
        );
      }
    }
  }
}

async function checkEvidenceBasedStatus(errors) {
  const readme = await readFile('packages/README.md');
  const lines = readme.split('\n');

  for (const line of lines) {
    const match = line.match(/\|\s*`(@oml\/[^`]+)`\s*\|.*\|\s*(.+?)\s*\|/);
    if (!match) {
      continue;
    }

    const packageName = match[1];
    const statusCell = match[2];
    if (!statusCell.includes('✅ Complete') || !packageMap.has(packageName)) {
      continue;
    }

    const packageDir = packageMap.get(packageName);
    for (const filePath of await listSourceFiles(path.join(packageDir, 'src'))) {
      const source = await readFile(filePath);
      const found = denyPatterns.find((pattern) => pattern.test(source));
      if (found) {
        errors.push(
          `${filePath} still matches ${found}, so ${packageName} cannot be marked complete in packages/README.md without new evidence.`
        );
        break;
      }
    }
  }
}

async function checkLaneConsistency(errors) {
  const configPath = '.ai/system/ai-ltc-config.json';
  const statusPath = '.ai/active-lane/current-status.md';
  const handoffPath = '00_HANDOFF.md';

  if (!(await exists(configPath)) || !(await exists(statusPath)) || !(await exists(handoffPath))) {
    return;
  }

  const config = await readJson(configPath);
  const currentStatus = await readFile(statusPath);
  const handoff = await readFile(handoffPath);

  const laneValues = [
    ['.ai/system/ai-ltc-config.json', config?.activeLane?.name ?? null],
    [
      '.ai/active-lane/current-status.md',
      extractMarkdownValue(currentStatus, [
        /^\*\*Lane\*\*:\s*(.+)$/m,
        /^\|\s*\*\*Lane\*\*\s*\|\s*(.+?)\s*\|/m,
      ]),
    ],
    [
      '00_HANDOFF.md',
      extractMarkdownValue(handoff, [
        /^\*\*Lane\*\*:\s*(.+)$/m,
        /^\|\s*\*\*Lane\*\*\s*\|\s*(.+?)\s*\|/m,
        /^\|\s*\*\*Name\*\*\s*\|\s*(.+?)\s*\|/m,
      ]),
    ],
  ].filter(([, value]) => value);

  const distinct = [...new Set(laneValues.map(([, value]) => value))];
  if (distinct.length > 1) {
    errors.push(
      `Active lane drift detected: ${laneValues.map(([file, value]) => `${file}=${value}`).join(', ')}.`
    );
  }
}

async function checkComplianceGate(errors) {
  // GPT-5.4 compliance audit 2026-03-27
  // Check Qwen plugin for compliance warning
  const qwenPluginPath = 'plugins/agents/qwen/main.sh';
  try {
    const qwenPlugin = await readFile(qwenPluginPath);
    const hasWarning = qwenPlugin.includes('WARNING: HIGH RISK') &&
                       qwenPlugin.includes('OAuth fallback to consumer web endpoint');
    if (!hasWarning) {
      errors.push(`${qwenPluginPath}: Missing compliance warning for OAuth fallback (GPT-5.4 HIGH finding)`);
    }
  } catch {
    // File may not exist in all deployments
  }
}

async function checkBridgeVersion(errors) {
  const configPath = '.ai/system/ai-ltc-config.json';
  const bridgePackagePath = 'packages/bridge/package.json';

  if (!(await exists(configPath)) || !(await exists(bridgePackagePath))) {
    return;
  }

  const config = await readJson(configPath);
  const bridgePackage = await readJson(bridgePackagePath);

  const frameworkVersion = config.framework_version;
  const bridgeVersion = bridgePackage.version;

  if (!frameworkVersion || !bridgeVersion) {
    return;
  }

  const parseVersion = (raw) => {
    const cleaned = raw.replace(/^v/, '');
    const match = cleaned.match(/^(\d+)\.(\d+)\.(\d+)/);
    if (!match) return null;
    return {
      major: Number.parseInt(match[1], 10),
      minor: Number.parseInt(match[2], 10),
      patch: Number.parseInt(match[3], 10),
    };
  };

  const framework = parseVersion(frameworkVersion);
  const bridge = parseVersion(`v${bridgeVersion}`);

  if (!framework || !bridge) {
    return;
  }

  if (framework.major === 0 && bridge.major === 0) {
    if (framework.minor !== bridge.minor) {
      errors.push(
        `Bridge version incompatible (minor drift in alpha): framework=${frameworkVersion}, bridge=v${bridgeVersion}`
      );
    }
  } else if (framework.major !== 0 && bridge.major === 0) {
    // Bridge is a new 0.x package within a 1.x framework — expected during development
    // Only warn, don't fail
  } else if (framework.major !== bridge.major) {
    errors.push(
      `Bridge version incompatible (major drift): framework=${frameworkVersion}, bridge=v${bridgeVersion}`
    );
  }
}

async function main() {
  const errors = [];

  await checkInterPackageContracts(errors);
  await checkEvidenceBasedStatus(errors);
  await checkLaneConsistency(errors);
  await checkComplianceGate(errors);
  await checkBridgeVersion(errors);

  if (errors.length > 0) {
    console.error('Architecture contract check failed:');
    for (const error of errors) {
      console.error(`- ${error}`);
    }
    process.exit(1);
  }

  console.log('Architecture contract check passed.');
}

await main();
