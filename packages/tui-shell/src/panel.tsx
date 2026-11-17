/**
 * OML paradigm-aware session-tree sidebar panel — real Solid component.
 *
 * Written in direct-function-call style (mirrors the compiled output of the
 * A fork bundle `packages/tui-plugins/subagent-magazine/bundle/tui.js`), so it
 * transpiles with plain Bun.Transpiler and needs NO extra solid JSX plugin.
 *
 * NOT imported statically by plugin.ts: solid-js / @opentui/solid only exist in
 * the magazine cache, so the OML repo cannot resolve them. plugin.ts loads this
 * module lazily at deploy time (see deploy.ts / loadRenderPanel).
 */

import {
  createComponent as ocCreateComponent,
  createElement as ocCreateElement,
  insert as ocInsert,
  insertNode as ocInsertNode,
  setProp as ocSetProp,
} from "@opentui/solid";
import { createMemo, For } from "solid-js";
import type { Paradigm, TreeNode } from "./tree.ts";

/** Minimal surface the panel needs from the host api (structurally matches OmlTuiApi). */
export interface PanelApi {
  route: { navigate(route: string, params: { sessionID: string }): void };
}

export interface OmlSessionTreePanelProps {
  api: PanelApi;
  theme: unknown;
  sessionId: string;
  /** Paradigm tree view built by plugin.buildParadigmView. */
  roots: TreeNode[];
}

/** One flattened, render-ready line of the paradigm tree. */
export interface FlatRow {
  id: string;
  sessionID: string;
  depth: number;
  paradigm: Paradigm | undefined;
  affiliation: string;
  title: string;
  agent: string;
  status: string;
  role?: string;
}

/** DFS-flatten a paradigm-annotated forest into display rows (indent = depth). */
export function flattenRows(roots: TreeNode[]): FlatRow[] {
  const out: FlatRow[] = [];
  const walk = (n: TreeNode): void => {
    const node = n.node;
    out.push({
      id: node.id,
      sessionID: node.sessionId || node.id,
      depth: n.depth,
      paradigm: n.paradigm ?? node.paradigm,
      affiliation: n.affiliation,
      title: node.title || node.id,
      agent: node.agent || "",
      status: node.status || "",
      role: node.role,
    });
    for (const c of n.children) walk(c);
  };
  for (const r of roots) walk(r);
  return out;
}

/** Distinguishable per-paradigm markers (as required by the B-route spec). */
export const PARADIGM_MARK: Record<Paradigm, string> = {
  single: "[单]",
  nested: "[嵌]",
  team: "[队]",
};

const PARADIGM_FG: Record<Paradigm, string> = {
  single: "#9CAF8B",
  nested: "#8B9DAF",
  team: "#C5B88D",
};

function rowLabel(row: FlatRow): string {
  const mark = row.paradigm ? PARADIGM_MARK[row.paradigm] : "[?]";
  const indent = "  ".repeat(row.depth); // nested → visible indentation
  const role = row.role ? ` ${row.role}` : ""; // team member role
  const agent = row.agent ? ` @${row.agent}` : "";
  const status = row.status ? ` ·${row.status}` : "";
  return `${indent}${mark} ${row.affiliation} · ${row.title}${role}${agent}${status}`;
}

/**
 * The panel component. Sidebar title + one clickable line per flattened node.
 * Clicking a line reuses api.route.navigate("session", { sessionID }).
 */
export function OmlSessionTreePanel(props: OmlSessionTreePanelProps): unknown {
  const rows = createMemo<FlatRow[]>(() => flattenRows(props.roots));

  return (() => {
    const box = ocCreateElement("box");
    ocSetProp(box, "flexDirection", "column");
    ocSetProp(box, "paddingLeft", 1);

    // Title row
    const title = ocCreateElement("text");
    ocInsert(title, "OML 会话树 · 范式视图");
    ocInsertNode(box, title);

    // Separator
    const sep = ocCreateElement("text");
    ocInsert(sep, "──────────────────────────────");
    ocSetProp(sep, "fg", "#6B6B63");
    ocInsertNode(box, sep);

    // One line per session. `createComponent(For, ...)` returns a reactive
    // accessor (function), NOT a static node — it must go through `insert`
    // (which installs a render effect), not `insertNode`. Mirrors the A fork's
    // `_$insert(_el$7, _$createComponent(For, {...}))`. Using insertNode here
    // silently drops all rows (only the static title/separator render).
    ocInsert(
      box,
      ocCreateComponent(For, {
        get each() {
          return rows();
        },
        children: (row: FlatRow) => (() => {
          const line = ocCreateElement("text");
          ocSetProp(line, "onMouseUp", () => {
            try {
              props.api.route.navigate("session", { sessionID: row.sessionID });
            } catch {
              /* best-effort navigation */
            }
          });
          ocInsert(line, rowLabel(row));
          ocSetProp(line, "style", {
            fg: row.paradigm ? PARADIGM_FG[row.paradigm] : "#C5C5BB",
          });
          return line;
        }),
      }),
    );

    return box;
  })();
}

/** Wrapper used by plugin.ts: wraps the component in createComponent. */
export function renderOmlSessionTreePanel(props: OmlSessionTreePanelProps): unknown {
  return ocCreateComponent(OmlSessionTreePanel, props);
}
