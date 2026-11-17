/**
 * Adapter: map a host `api.state.session.get`-style snapshot into SessionNode[].
 * Pure (no host types imported) so it can be unit-tested with fakes.
 *
 * The V1 TUI API has no session.list; panels accumulate session ids from events,
 * then call session.get(sid) for each. This adapter is the boundary that turns
 * those snapshots into the flat list the tree model consumes.
 */

import { classifyParadigm, type Paradigm, type SessionNode, type TreeNode } from "./tree.ts";

export interface SessionSnapshot {
  id?: string;
  parentID?: string;
  title?: string;
  agent?: string;
  status?: string;
}

export type SessionGetter = (id: string) => SessionSnapshot | undefined | null;

/**
 * @param ids accumulated session ids (from call_map / event stream)
 * @param get host session.get(sid)
 * @param labelFor optional custom label builder (e.g. U1's "omo t1←t5 · <title>")
 */
export function toSessionNodes(
  ids: string[],
  get: SessionGetter,
  labelFor?: (snap: SessionSnapshot, id: string) => string,
): SessionNode[] {
  const seen = new Set<string>();
  const out: SessionNode[] = [];
  for (const id of ids) {
    if (!id || seen.has(id)) continue;
    seen.add(id);
    let snap: SessionSnapshot | undefined | null;
    try {
      snap = get(id);
    } catch {
      snap = undefined;
    }
    const s = snap ?? {};
    out.push({
      id,
      parentID: s.parentID || undefined,
      title: labelFor ? labelFor(s, id) : s.title || s.agent || id,
      agent: s.agent,
      status: s.status,
    });
  }
  return out;
}

/**
 * Given a set of ids, keep only those that still resolve via get() and have a
 * valid parentID (or no parent). Drops sessions whose parent disappeared —
 * mirrors the magazine's clearedIds / ghost-session pruning intent.
 */
export function pruneGhosts(
  ids: string[],
  get: SessionGetter,
): string[] {
  const resolvable = ids.filter((id) => {
    try {
      return !!get(id);
    } catch {
      return false;
    }
  });
  const set = new Set(resolvable);
  return resolvable.filter((id) => {
    try {
      const p = get(id)?.parentID;
      return !p || set.has(p);
    } catch {
      return true;
    }
  });
}

/**
 * Structural slice of an OML `TaskRecord` (packages/core/src/tasks/store.ts:25).
 * Deliberately re-declared here instead of imported from core so tui-shell stays
 * a zero-dependency, headless-testable package. Members are intentionally NOT
 * carried — team fan-out is recovered from the parentId relation alone, so we
 * never double-expand a team into both member records and synthetic children.
 */
export interface TaskLike {
  id: string;
  parentId: string | null;
  description: string;
  kind?: string;
  status?: string;
  sessionId?: string;
}

/** Parse a leading "role: ..." label, e.g. team member briefs "${role}: ${brief}". */
function parseRole(description: string): string | undefined {
  const m = /^([^:]{1,64}):\s/.exec(description ?? "");
  return m ? m[1]!.trim() : undefined;
}

/** Initial paradigm from the raw task record, before tree-shape annotation runs. */
function initialParadigm(kind?: string): Paradigm | undefined {
  return kind === "team" ? "team" : undefined;
}

/**
 * Map a flat list of OML tasks into the SessionNode[] the tree model consumes:
 * task.id → id, task.parentId → parentID, task.description → title,
 * task.sessionId → sessionId, plus an initial paradigm/kind. The resulting
 * forest (via buildSessionTree) forms team-member children purely from the
 * parentId relation — members are not separately expanded.
 */
export function tasksToNodes(tasks: TaskLike[]): SessionNode[] {
  const out: SessionNode[] = [];
  for (const t of tasks) {
    if (!t || typeof t.id !== "string" || t.id.length === 0) continue;
    out.push({
      id: t.id,
      parentID: t.parentId || undefined,
      title: t.description || t.id,
      taskId: t.id,
      kind: t.kind,
      status: t.status,
      sessionId: t.sessionId,
      paradigm: initialParadigm(t.kind),
    });
  }
  return out;
}

/**
 * Annotate a built forest with derived delegation paradigms (in place).
 *
 * Walks the tree bottom-up-friendly DFS and, for each node, applies
 * classifyParadigm using the node's raw kind and whether it has children in
 * the tree. Team nodes additionally propagate their parsed role onto member
 * child nodes. Structural invariants (ids, parentID, children, depth,
 * ancestors, affiliation) are left untouched — only node.paradigm / node.role
 * are written, so flattenTree(roots) is identical before and after.
 */
export function annotateParadigms(roots: TreeNode[]): void {
  const visit = (n: TreeNode): void => {
    for (const c of n.children) visit(c);
    // classifyParadigm takes {kind, parentId}; parentId only feeds the
    // team branch, which is already keyed off kind, so null is safe here.
    n.node.paradigm = classifyParadigm(
      { kind: n.node.kind, parentId: n.node.parentID ?? null },
      n.children.length > 0,
    );
    n.paradigm = n.node.paradigm;
    if (n.node.paradigm === "team") {
      const parentRole = n.node.role ?? parseRole(n.node.title ?? "");
      for (const c of n.children) {
        c.node.role = c.node.role ?? parseRole(c.node.title ?? "") ?? parentRole;
      }
    }
  };
  for (const r of roots) visit(r);
}
