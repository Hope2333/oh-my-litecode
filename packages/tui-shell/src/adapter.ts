/**
 * Adapter: map a host `api.state.session.get`-style snapshot into SessionNode[].
 * Pure (no host types imported) so it can be unit-tested with fakes.
 *
 * The V1 TUI API has no session.list; panels accumulate session ids from events,
 * then call session.get(sid) for each. This adapter is the boundary that turns
 * those snapshots into the flat list the tree model consumes.
 */

import type { SessionNode } from "./tree.ts";

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
