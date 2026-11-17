/**
 * OML TUI shell deployment (run with Bun):
 *
 *   bun packages/tui-shell/deploy.ts            # build + install into cache
 *   bun packages/tui-shell/deploy.ts --check     # validate inputs, write nothing
 *
 * Installs a self-contained plugin package at
 *   ~/.cache/opencode/packages/oml-tui-shell/
 * with `package.json` exporting ./tui -> tui.js and a SINGLE compiled tui.js
 * (plugin.ts + panel.tsx bundled together, solid deps left external so the
 * plugin shares the host's @opentui/solid renderer instance), plus node_modules
 * symlinks to the three solid deps in the magazine cache.
 * Idempotent: re-running rebuilds and refreshlinks the same artifacts.
 *
 * All builders here are pure (no fs writes) so they are headless-unit-testable;
 * only applyPlan()/the CLI guard touch the filesystem.
 */

import { existsSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/** The three deps the compiled panel needs; resolved from the magazine cache. */
export const SOLID_DEPS = ["solid-js", "@opentui/solid", "@opentui/core"] as const;

export const SOURCE_DIR = dirname(fileURLToPath(import.meta.url));
export const MAGAZINE_MODULES = join(
  homedir(), ".cache", "opencode", "packages", "opencode-subagent-magazine", "node_modules",
);
export const DEFAULT_DEPLOY_DIR = join(
  homedir(), ".cache", "opencode", "packages", "oml-tui-shell",
);

export const PACKAGE_JSON_BODY = '{"type":"module","exports":{"./tui":"./tui.js"}}\n';

export interface BuildSpec {
  from: string;
  outName: string;
}

export interface LinkSpec {
  /** Source path in the magazine cache node_modules. */
  target: string;
  /** Symlink path inside the deploy dir's node_modules. */
  path: string;
}

export interface DeployPlan {
  dir: string;
  sourceDir: string;
  magazineDir: string;
  packageJsonName: string;
  packageJson: string;
  builds: BuildSpec[];
  links: LinkSpec[];
}

/** The exact package.json shape required by the host loader. */
export function buildPackageJson(): { type: string; exports: Record<string, string> } {
  return { type: "module", exports: { "./tui": "./tui.js" } };
}

/** Build a complete, side-effect-free deployment plan. */
export function buildPlan(opts: {
  dir?: string;
  sourceDir?: string;
  magazineDir?: string;
} = {}): DeployPlan {
  const dir = opts.dir ?? process.env.OML_TUI_SHELL_DIR ?? DEFAULT_DEPLOY_DIR;
  const sourceDir = opts.sourceDir ?? SOURCE_DIR;
  const magazineDir = opts.magazineDir ?? MAGAZINE_MODULES;
  return {
    dir,
    sourceDir,
    magazineDir,
    packageJsonName: "package.json",
    packageJson: PACKAGE_JSON_BODY,
    // ONE entrypoint: plugin.ts statically imports panel.tsx, so both end up in
    // the same bundle and therefore share the host's @opentui/solid instance.
    builds: [
      { from: join(sourceDir, "src", "plugin.ts"), outName: "tui.js" },
    ],
    links: SOLID_DEPS.map((name) => {
      const segments = name.split("/");
      return {
        target: join(magazineDir, ...segments),
        path: join(dir, "node_modules", ...segments),
      };
    }),
  };
}

/** Validate a plan without writing anything. Returns human-readable problems. */
export function checkPlan(plan: DeployPlan): string[] {
  const problems: string[] = [];
  for (const b of plan.builds) {
    if (!existsSync(b.from)) problems.push(`missing source: ${b.from}`);
  }
  for (const l of plan.links) {
    if (!existsSync(l.target)) problems.push(`missing solid dep: ${l.target}`);
  }
  if (JSON.stringify(JSON.parse(plan.packageJson)) !== JSON.stringify(buildPackageJson())) {
    problems.push("package.json body does not match expected shape");
  }
  return problems;
}

/** Materialize a plan. Safe to call repeatedly. */
export async function applyPlan(plan: DeployPlan): Promise<void> {
  mkdirSync(join(plan.dir, "node_modules"), { recursive: true });
  writeFileSync(join(plan.dir, plan.packageJsonName), plan.packageJson, "utf8");
  // Drop the old two-bundle artifact if a previous deploy left one behind.
  rmSync(join(plan.dir, "panel.js"), { force: true });

  for (const b of plan.builds) {
    const out = await Bun.build({
      entrypoints: [b.from],
      outdir: plan.dir,
      naming: b.outName,
      format: "esm",
      target: "bun",
      packages: "bundle",
      external: [...SOLID_DEPS, "node:fs", "node:os", "node:path", "node:url"],
    });
    if (!out.success) {
      throw new Error(`build failed for ${b.from}: ${out.logs.map((l: unknown) => String(l)).join("\n")}`);
    }
  }

  for (const l of plan.links) {
    rmSync(l.path, { recursive: true, force: true });
    mkdirSync(dirname(l.path), { recursive: true });
    symlinkSync(l.target, l.path, "dir");
  }
}

if (import.meta.main) {
  const checkOnly = process.argv.includes("--check");
  const plan = buildPlan();
  const problems = checkPlan(plan);
  if (problems.length > 0) {
    for (const p of problems) console.error(`[deploy] ${p}`);
    process.exit(1);
  }
  if (checkOnly) {
    console.log(`[deploy] check OK -> ${plan.dir}`);
  } else {
    await applyPlan(plan);
    console.log(`[deploy] installed -> ${plan.dir}`);
  }
}
