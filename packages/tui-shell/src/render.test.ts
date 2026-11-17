// Registers solid module mocks FIRST: plugin.ts statically imports panel.tsx,
// whose @opentui/solid / solid-js imports are not resolvable from this repo.
import "./solid-test-shim.ts";
import { describe, it, expect } from "bun:test";
import { readFileSync } from "node:fs";
import type { OmlTuiApi } from "./plugin.ts";
import {
  SOLID_DEPS,
  MAGAZINE_MODULES,
  DEFAULT_DEPLOY_DIR,
  PACKAGE_JSON_BODY,
  buildPackageJson,
  buildPlan,
  checkPlan,
} from "../deploy.ts";

// Loaded after the shim above so panel.tsx's solid imports resolve to mocks.
const { tui, buildViewModel, buildParadigmView, tasksFilePath, trackSession, extractTaskList } = await import("./plugin.ts");

function fakeApi(sessions: Record<string, { parentID?: string; agent?: string; title?: string }> = {}): OmlTuiApi {
  const kv = new Map<string, string>();
  return {
    slots: {
      register(def) {
        (this as unknown as { _def?: unknown })._def = def;
      },
    },
    command: {
      register(factory) {
        (this as unknown as { _cmds?: unknown })._cmds = factory();
      },
    },
    state: {
      session: {
        get(id) {
          return sessions[id] ? { ...sessions[id] } : undefined;
        },
      },
    },
    route: {
      navigate(route, params) {
        (this as unknown as { _nav?: unknown })._nav = { route, params };
      },
    },
    kv: {
      get(key, fallback) {
        return kv.has(key) ? kv.get(key) : fallback;
      },
      set(key, value) {
        kv.set(key, value);
      },
    },
  };
}

type CapturedDef = {
  order: number;
  slots: { sidebar_content: (ctx: { theme: { current: unknown } }, input: { session_id: string }) => unknown };
};

describe("(a) Bun.Transpiler syntax validation", () => {
  it("panel.tsx transpiles as tsx without syntax errors", () => {
    const source = readFileSync(new URL("./panel.tsx", import.meta.url), "utf8");
    const transpiler = new Bun.Transpiler({ loader: "tsx" });
    let out = "";
    expect(() => { out = transpiler.transformSync(source); }).not.toThrow();
    expect(out).toContain("renderOmlSessionTreePanel");
    expect(out).toContain("OML 会话树");
  });

  it("panel.tsx inserts For via ocInsert, not ocInsertNode (rows would vanish)", () => {
    // Regression: createComponent(For,...) returns a reactive accessor (function).
    // insertNode() cannot render it → only title/separator show, no tree rows.
    const source = readFileSync(new URL("./panel.tsx", import.meta.url), "utf8");
    expect(source).toMatch(/ocInsert\(\s*box,\s*ocCreateComponent\(For/);
    expect(source).not.toMatch(/ocInsertNode\(\s*box,\s*ocCreateComponent\(For/);
  });

  it("deploy.ts transpiles as ts without syntax errors", () => {
    const source = readFileSync(new URL("../deploy.ts", import.meta.url), "utf8");
    const transpiler = new Bun.Transpiler({ loader: "ts" });
    expect(() => transpiler.transformSync(source)).not.toThrow();
  });
});

describe("(b) deploy.ts construction logic (pure)", () => {
  it("package.json shape is exactly type=module + ./tui export", () => {
    expect(buildPackageJson()).toEqual({
      type: "module",
      exports: { "./tui": "./tui.js" },
    });
    expect(JSON.parse(PACKAGE_JSON_BODY)).toEqual(buildPackageJson());
  });

  it("SOLID_DEPS lists the three magazine-cache deps", () => {
    expect(SOLID_DEPS).toEqual(["solid-js", "@opentui/solid", "@opentui/core"]);
  });

  it("buildPlan uses ONE entrypoint (plugin.ts -> tui.js) and links each dep", () => {
    const plan = buildPlan({ dir: "/tmp/oml-deploy-test", sourceDir: "/repo/pkg", magazineDir: "/cache/mods" });
    expect(plan.dir).toBe("/tmp/oml-deploy-test");
    expect(plan.builds).toHaveLength(1);
    expect(plan.builds.map((b) => b.outName)).toEqual(["tui.js"]);
    expect(plan.builds[0]!.from).toBe("/repo/pkg/src/plugin.ts");
    expect(plan.builds.some((b) => b.outName === "panel.js")).toBe(false);
    expect(plan.links).toHaveLength(3);
    expect(plan.links[0]).toEqual({
      target: "/cache/mods/solid-js",
      path: "/tmp/oml-deploy-test/node_modules/solid-js",
    });
    expect(plan.links[1]!.path).toContain("@opentui/solid");
    expect(plan.links[2]!.path).toContain("@opentui/core");
    expect(buildPlan().magazineDir).toBe(MAGAZINE_MODULES);
    expect(DEFAULT_DEPLOY_DIR.endsWith("oml-tui-shell")).toBe(true);
  });

  it("checkPlan is side-effect free and reports missing inputs", () => {
    const plan = buildPlan({
      dir: "/tmp/oml-deploy-test",
      sourceDir: "/definitely/not/a/real/path",
      magazineDir: "/also/not/real",
    });
    const problems = checkPlan(plan);
    expect(problems.length).toBeGreaterThan(0);
    expect(problems.some((p) => p.startsWith("missing source:"))).toBe(true);
    expect(problems.some((p) => p.startsWith("missing solid dep:"))).toBe(true);
  });
});

describe("(c) plugin.ts tui registration structure", () => {
  it("tui registers a sidebar_content slot with order=55", async () => {
    const api = fakeApi();
    await tui(api);
    const def = (api.slots as unknown as { _def: CapturedDef })._def;
    expect(def.order).toBe(55);
    expect(typeof def.slots.sidebar_content).toBe("function");
  });

  it("tui still registers the oml-open-session command", async () => {
    const api = fakeApi();
    await tui(api);
    const cmds = (api.command as unknown as { _cmds: Array<{ value: string }> })._cmds;
    expect(cmds.some((c) => c.value === "oml-open-session")).toBe(true);
  });

  it("sidebar_content returns the statically imported panel directly (no placeholder)", async () => {
    const api = fakeApi({ s1: {} });
    await tui(api);
    const def = (api.slots as unknown as { _def: CapturedDef })._def;
    const result = def.slots.sidebar_content({ theme: { current: "THEME" } }, { session_id: "s1" }) as {
      __omlSolidRender?: boolean;
      __omlTreePlaceholder?: boolean;
      props?: { api: unknown; theme: unknown; sessionId: string; roots: unknown[] };
    };
    // The mocked createComponent marker proves renderOmlSessionTreePanel ran.
    expect(result.__omlSolidRender).toBe(true);
    expect(result.__omlTreePlaceholder).toBeUndefined();
    expect(result.props?.theme).toBe("THEME");
    expect(result.props?.sessionId).toBe("s1");
    expect(Array.isArray(result.props?.roots)).toBe(true);
    expect(result.props?.api).toBe(api);
    expect(JSON.parse(String(api.kv.get("oml_tui_shell.session_ids", "[]")))).toContain("s1");
  });

  it("plugin.ts has no dynamic import / placeholder fallback", async () => {
    const source = readFileSync(new URL("./plugin.ts", import.meta.url), "utf8");
    expect(source).not.toContain("__omlTreePlaceholder");
    expect(source).not.toContain("loadRenderPanel");
    expect(source).toContain('import { renderOmlSessionTreePanel } from "./panel.tsx"');
    expect(source).not.toMatch(/await import\(/);
  });

  it("buildParadigmView annotates paradigms from session snapshots", () => {
    const api = fakeApi({ t1: {}, t5: { parentID: "t1", title: "child", agent: "build" } });
    trackSession(api, "t1");
    trackSession(api, "t5");
    const view = buildViewModel(api);
    const { roots } = buildParadigmView(api, view, []); // explicit empty ledger → deterministic
    expect(roots).toHaveLength(1);
    expect(roots[0]!.node.paradigm).toBe("nested");
    expect(roots[0]!.children[0]!.node.paradigm).toBe("single");
    expect(roots[0]!.children[0]!.node.agent).toBe("build");
  });

  it("tasksFilePath honors OML_STATE_DIR override", () => {
    const before = process.env.OML_STATE_DIR;
    try {
      process.env.OML_STATE_DIR = "/tmp/oml-state-override";
      expect(tasksFilePath()).toBe("/tmp/oml-state-override/tasks.json");
    } finally {
      if (before === undefined) delete process.env.OML_STATE_DIR;
      else process.env.OML_STATE_DIR = before;
    }
  });

  it("extractTaskList reads the real TaskStore object-map shape", () => {
    // Regression: the real tasks.json is { version, tasks: {t1:{...}}, lastId },
    // NOT an array. The old reader only handled arrays → panel had no rows.
    const realShape = {
      version: 1,
      tasks: {
        t1: { id: "t1", parentId: null, depth: 0, description: "root", status: "done" },
        t2: { id: "t2", parentId: "t1", depth: 1, description: "child", status: "running" },
      },
      lastId: 2,
    };
    const list = extractTaskList(realShape);
    expect(list).toHaveLength(2);
    expect(list.map((t) => t.id)).toEqual(["t1", "t2"]);
    expect(extractTaskList([{ id: "a" }])).toHaveLength(1); // bare array still works
    expect(extractTaskList({ tasks: [{ id: "b" }] })).toHaveLength(1); // {tasks:[]} still works
    expect(extractTaskList({})).toHaveLength(0);
  });
});
