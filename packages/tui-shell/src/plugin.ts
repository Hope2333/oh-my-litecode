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

import { buildSessionTree, flattenTree, type SessionNode, type TreeNode } from "./tree.ts";
import { toSessionNodes, pruneGhosts, type SessionGetter } from "./adapter.ts";

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

/** Default entry — render is a placeholder descriptor pending a verified solid build. */
export const tui = createOmlTui((view) => ({
  __omlTreePlaceholder: true,
  ids: view.ids,
}));

export default { id: "oml-tui-shell", tui };
