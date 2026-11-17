/**
 * OML-owned TUI shell — V1 (opencode 1.19.x) plugin entry skeleton.
 *
 * STATUS: EXPERIMENTAL. The pure session-tree logic (tree.ts / adapter.ts) is
 * fully tested. The rendering layer below is a structural skeleton validated
 * by Bun.Transpiler only — it is NOT render-verified (this host has no TTY and
 * OML has no solid-js / @opentui/solid devDeps). See README.md for what remains.
 *
 * V1 API contract (from forked bundle, opencode 1.19.x):
 *   tui = async (api) => {
 *     api.slots.register({ order, slots: { sidebar_content(ctx, input) {...} } })
 *     api.command?.register(() => [...])
 *   }
 *   - api.state.session.get(sid)  -> { parentID?, agent?, status?, title? }
 *   - api.state.session.messages(sid) / .todo(sid) / .status(sid)
 *   - api.route.navigate("session", { sessionID })
 *   - api.kv.get / set
 */

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
// STATIC import, same module instance as the host. A runtime dynamic import()
// creates a separate @opentui/solid instance with an empty renderer context and
// createElement() throws "No renderer found" (verified on a real TUI). The
// deploy script bundles this import into a single tui.js (solid deps external).
import { renderOmlSessionTreePanel } from "./panel.tsx";
import { buildSessionTree, flattenTree, type SessionNode, type TreeNode } from "./tree.ts";
import {
  annotateParadigms,
  pruneGhosts,
  tasksToNodes,
  toSessionNodes,
  type SessionGetter,
  type TaskLike,
} from "./adapter.ts";

export interface OmlTuiApi {
  slots: { register(def: SlotDefinition): void };
  command?: { register(factory: () => CommandDef[]): void };
  state: { session: SessionApi };
  route: { navigate(route: string, params: { sessionID: string }): void };
  kv: { get(key: string, fallback?: unknown): unknown; set(key: string, value: string): void };
  ui?: Record<string, unknown>;
}

export interface SessionApi {
  get(id: string): { parentID?: string; agent?: string; status?: string; title?: string } | undefined | null;
  messages?(id: string): unknown[];
  todo?(id: string): unknown[];
  status?(id: string): unknown;
}

export interface SlotDefinition {
  order: number;
  slots: {
    sidebar_content(ctx: { theme: { current: unknown } }, input: { session_id: string }): unknown;
  };
}

export interface CommandDef {
  title: string;
  value: string;
  description: string;
  slash?: { name: string };
  onSelect?: (dialog?: unknown) => void;
}

export const KV_PREFIX = "oml_tui_shell";
export const SESSION_IDS_KEY = `${KV_PREFIX}.session_ids`;

/** Accumulate session ids seen from tool/message events (persisted to KV). */
export function trackSession(api: OmlTuiApi, sid: string): void {
  if (!sid) return;
  let ids: string[] = [];
  try {
    ids = JSON.parse(String(api.kv.get(SESSION_IDS_KEY, "[]")));
  } catch {
    ids = [];
  }
  if (!Array.isArray(ids)) ids = [];
  if (!ids.includes(sid)) {
    ids.push(sid);
    try {
      api.kv.set(SESSION_IDS_KEY, JSON.stringify(ids.slice(-200)));
    } catch {
      /* best-effort */
    }
  }
}

/** Build the render-ready tree model from currently tracked sessions. */
export function buildViewModel(api: OmlTuiApi): { roots: TreeNode[]; ids: string[] } {
  const getter: SessionGetter = (id) => api.state.session.get(id) ?? undefined;
  let ids: string[] = [];
  try {
    ids = JSON.parse(String(api.kv.get(SESSION_IDS_KEY, "[]")));
  } catch {
    ids = [];
  }
  const live = pruneGhosts(Array.isArray(ids) ? ids : [], getter);
  const nodes: SessionNode[] = toSessionNodes(live, getter).map((n) => ({
    ...n,
    // U1-style affiliation label: chain is carried by the tree model; here we
    // prefix a marker so the title visibly signals OML ownership.
    title: `omo · ${n.title}`,
  }));
  const roots = buildSessionTree(nodes, { useTitles: true });
  return { roots, ids: flattenTree(roots) };
}

/** Path to the OML task ledger. OML_STATE_DIR overrides the default. */
export function tasksFilePath(): string {
  const base = process.env.OML_STATE_DIR || join(homedir(), ".local", "state", "oml");
  return join(base, "tasks.json");
}

/**
 * Extract the task list from a parsed tasks.json ledger.
 * The OML TaskStore writes `{ version, tasks: { t1: {...}, t2: {...} }, lastId }`
 * (tasks is an id-keyed object map). Also tolerate a bare array and `{ tasks: [...] }`
 * for older/hand-written ledgers. This is a pure function so it can be unit tested
 * without touching the filesystem.
 */
export function extractTaskList(parsed: unknown): TaskLike[] {
  if (Array.isArray(parsed)) return parsed as TaskLike[];
  if (parsed && typeof parsed === "object") {
    const tasks = (parsed as { tasks?: unknown }).tasks;
    if (Array.isArray(tasks)) return tasks as TaskLike[];
    // Object map: { t1: {...}, t2: {...} } — the real TaskStore format.
    if (tasks && typeof tasks === "object") {
      return Object.values(tasks as Record<string, TaskLike>);
    }
  }
  return [];
}

/**
 * Synchronously read the optional tasks.json ledger into SessionNode[].
 * Read/parse failure degrades to an empty list — never throws into the host render path.
 */
export function readTaskNodes(): SessionNode[] {
  try {
    const raw = readFileSync(tasksFilePath(), "utf8");
    return tasksToNodes(extractTaskList(JSON.parse(raw)));
  } catch {
    return [];
  }
}

/**
 * Merge the two documented data sources into a paradigm-annotated forest:
 *  - api.state.session.get snapshots (via adapter.toSessionNodes, already in view)
 *  - optional tasks.json (via adapter.tasksToNodes + annotateParadigms)
 * Live session agent/status/title win over the ledger when ids line up; ledger
 * nodes keep their kind/taskId so team/nested paradigms are derived correctly.
 */
export function buildParadigmView(
  _api: OmlTuiApi,
  view: { roots: TreeNode[]; ids: string[] },
  taskNodes: SessionNode[] = readTaskNodes(),
): { roots: TreeNode[] } {
  const sessionNodes: SessionNode[] = toSessionNodes(view.ids, (id) => _api.state.session.get(id) ?? undefined);
  const byId = new Map(sessionNodes.map((n) => [n.id, n]));
  const bySid = new Map(
    sessionNodes.filter((n) => !!n.sessionId).map((n) => [n.sessionId as string, n]),
  );

  const merged: SessionNode[] = [];
  const seen = new Set<string>();
  for (const t of taskNodes) {
    const live = byId.get(t.id) ?? (t.sessionId ? bySid.get(t.sessionId) : undefined);
    merged.push({
      ...t,
      title: live?.title || t.title,
      agent: live?.agent || t.agent,
      status: live?.status || t.status,
    });
    seen.add(t.id);
  }
  for (const s of sessionNodes) {
    if (!seen.has(s.id)) merged.push(s);
  }

  const roots = buildSessionTree(merged, { useTitles: true });
  annotateParadigms(roots);
  return { roots };
}

/**
 * V1 TUI entry. `render` is injected so the pure wiring is testable; the real
 * build supplies a @opentui/solid component factory. Not provided here because
 * rendering cannot be verified without a TTY (see README).
 */
export function createOmlTui(
  render: (view: ReturnType<typeof buildViewModel>, api: OmlTuiApi, currentSessionId: string) => unknown,
  deps: { order?: number } = {},
): (api: OmlTuiApi) => Promise<void> {
  return async (api: OmlTuiApi): Promise<void> => {
    api.slots.register({
      order: deps.order ?? 55,
      slots: {
        sidebar_content(ctx, input) {
          trackSession(api, input.session_id);
          const view = buildViewModel(api);
          return render(view, api, input.session_id);
        },
      },
    });
    api.command?.register(() => [
      {
        title: "OML: Open Session",
        value: "oml-open-session",
        description: "Jump to a session in the OML tree",
        slash: { name: "oml-open-session" },
        onSelect: () => {
          const view = buildViewModel(api);
          if (view.ids[0]) api.route.navigate("session", { sessionID: view.ids[0] });
        },
      },
    ]);
  };
}

/**
 * Default entry — real @opentui/solid sidebar panel, statically imported above.
 * No placeholder fallback and no swallowed errors: a real failure must surface
 * in the host log instead of silently hiding the panel.
 */
export const tui = async (api: OmlTuiApi): Promise<void> => {
  api.slots.register({
    order: 55,
    slots: {
      sidebar_content(ctx, input) {
        trackSession(api, input.session_id);
        const view = buildViewModel(api);
        const paradigm = buildParadigmView(api, view);
        return renderOmlSessionTreePanel({
          api,
          theme: ctx.theme.current,
          sessionId: input.session_id,
          roots: paradigm.roots,
        });
      },
    },
  });

  // Preserved from the original shell: command registration.
  api.command?.register(() => [
    {
      title: "OML: Open Session",
      value: "oml-open-session",
      description: "Jump to a session in the OML tree",
      slash: { name: "oml-open-session" },
      onSelect: () => {
        const view = buildViewModel(api);
        if (view.ids[0]) api.route.navigate("session", { sessionID: view.ids[0] });
      },
    },
  ]);
};

export default { id: "oml-tui-shell", tui };
