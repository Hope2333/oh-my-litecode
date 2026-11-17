import { describe, it, expect } from "bun:test";
import {
  createOmlTui,
  trackSession,
  buildViewModel,
  KV_PREFIX,
  SESSION_IDS_KEY,
  type OmlTuiApi,
} from "./plugin.ts";

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

describe("plugin wiring (pure, no TTY)", () => {
  it("trackSession accumulates ids into KV, deduped", () => {
    const api = fakeApi();
    trackSession(api, "t1");
    trackSession(api, "t5");
    trackSession(api, "t1");
    expect(JSON.parse(String(api.kv.get(SESSION_IDS_KEY, "[]")))).toEqual(["t1", "t5"]);
  });

  it("buildViewModel returns affiliation-labelled roots with oml prefix", async () => {
    const api = fakeApi({ t1: {}, t5: { parentID: "t1", title: "child" } });
    trackSession(api, "t1");
    trackSession(api, "t5");
    const view = buildViewModel(api);
    expect(view.ids).toEqual(["t1", "t5"]);
    expect(view.roots).toHaveLength(1);
    expect(view.roots[0]!.children[0]!.node.title).toContain("omo · ");
  });

  it("createOmlTui registers a sidebar slot + command", async () => {
    const api = fakeApi();
    const tui = createOmlTui((view) => ({ ids: view.ids }));
    await tui(api);
    const def = (api.slots as unknown as { _def: { order: number; slots: { sidebar_content: Function } } })._def;
    expect(def.order).toBeGreaterThan(0);
    expect(typeof def.slots.sidebar_content).toBe("function");
    const cmds = (api.command as unknown as { _cmds: Array<{ value: string }> })._cmds;
    expect(cmds.some((c) => c.value === "oml-open-session")).toBe(true);
  });

  it("sidebar_content tracks the current session and renders view", async () => {
    const api = fakeApi({ s1: {} });
    const rendered: unknown[] = [];
    const tui = createOmlTui((view) => {
      rendered.push(view);
      return { ids: view.ids };
    });
    await tui(api);
    const def = (api.slots as unknown as { _def: { slots: { sidebar_content: Function } } })._def;
    def.slots.sidebar_content({ theme: { current: {} } }, { session_id: "s1" });
    expect(rendered).toHaveLength(1);
    expect(JSON.parse(String(api.kv.get(SESSION_IDS_KEY, "[]")))).toContain("s1");
  });

  it("KV prefix is namespaced to avoid ghost collisions", () => {
    expect(KV_PREFIX.startsWith("oml_")).toBe(true);
    expect(SESSION_IDS_KEY.startsWith("oml_tui_shell.")).toBe(true);
  });
});

describe("Bun.Transpiler syntax validation", () => {
  it("plugin.ts / tree.ts / adapter.ts transpile without syntax errors", async () => {
    const files = ["plugin.ts", "tree.ts", "adapter.ts"];
    for (const f of files) {
      const mod = await import(`./${f}`);
      expect(mod).toBeDefined();
    }
  });
});
