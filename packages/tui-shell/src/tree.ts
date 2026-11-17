/**
 * OML session-tree model — pure logic, zero external deps.
 *
 * Builds an affiliation-labelled tree from a flat list of sessions.
 * Mirrors the V1 TUI magazine's parentID semantics (bundle/tui.js:488-490,
 * isDirectChildSession in MAG/dist/v2.js:2285): a node is a child of another
 * iff node.parentID === parent.id. Orphans/cycles are degraded to roots so the
 * tree is always finite and renderable.
 */

export interface SessionNode {
  id: string;
  parentID?: string;
  /** Human label written by U1, e.g. "omo t1←t5 · fix bug". */
  title?: string;
  agent?: string;
  status?: string;
}

export interface TreeNode {
  node: SessionNode;
  /** Ancestor ids from root to parent (for jump targets). */
  ancestors: string[];
  /** Affiliation string, e.g. "t1←t5" (ids) or titles joined by " / ". */
  affiliation: string;
  depth: number;
  children: TreeNode[];
}

export interface TreeOptions {
  /** Use titles (falling back to id) in the affiliation string. Default false (ids). */
  useTitles?: boolean;
  /** Max depth; deeper nodes are flattened to their nearest kept ancestor. Default Infinity. */
  maxDepth?: number;
  /** Sort comparator applied to every sibling level (by stable id if omitted). */
  sort?: (a: TreeNode, b: TreeNode) => number;
}

const byId = (a: TreeNode, b: TreeNode): number =>
  a.node.id < b.node.id ? -1 : a.node.id > b.node.id ? 1 : 0;

/**
 * Build a forest from flat sessions. Handles:
 *  - orphan parentID (parent not in set) → treated as root
 *  - cycles (a→b→a) → broken: the node whose parent would close a cycle becomes a root
 *  - duplicate ids → last wins
 *  - missing ids → skipped
 */
export function buildSessionTree(sessions: SessionNode[], opts: TreeOptions = {}): TreeNode[] {
  const { useTitles = false, maxDepth = Infinity, sort = byId } = opts;
  const map = new Map<string, SessionNode>();
  for (const s of sessions) {
    if (s && typeof s.id === "string" && s.id.length > 0) map.set(s.id, { ...s });
  }

  // Detect cycles by walking parentID chains; a cycle member is forced to root.
  const cyclic = new Set<string>();
  for (const id of map.keys()) {
    const seen = new Set<string>();
    let cur: string | undefined = id;
    while (cur && !seen.has(cur)) {
      seen.add(cur);
      cur = map.get(cur)?.parentID;
      if (cur && !map.has(cur)) break; // orphan chain, not a cycle
    }
    if (cur && seen.has(cur)) {
      // Everything on the cycle: mark the whole loop so none of them point inward.
      let c: string | undefined = cur;
      do {
        cyclic.add(c!);
        c = map.get(c!)?.parentID;
      } while (c && c !== cur && !cyclic.has(c));
    }
  }

  const nodes = new Map<string, TreeNode>();
  for (const [id, node] of map) {
    nodes.set(id, { node, ancestors: [], affiliation: "", depth: 0, children: [] });
  }

  const roots: TreeNode[] = [];
  for (const [id, treeNode] of nodes) {
    const parentID = treeNode.node.parentID;
    const parent = parentID && !cyclic.has(id) && parentID !== id ? nodes.get(parentID) : undefined;
    if (parent && !cyclic.has(parentID!)) parent.children.push(treeNode);
    else roots.push(treeNode);
  }

  // Fill depth / ancestors / affiliation by DFS from roots.
  const label = (n: SessionNode): string => (useTitles ? n.title || n.agent || n.id : n.id);
  const visit = (n: TreeNode, ancestors: string[], depth: number): void => {
    n.depth = depth;
    n.ancestors = ancestors.slice();
    n.affiliation = [...ancestors, n.node.id].map((a) => label(map.get(a) ?? { id: a })).join("←");
    if (depth < maxDepth) {
      for (const c of n.children) visit(c, [...ancestors, n.node.id], depth + 1);
    }
  };
  for (const r of roots) visit(r, [], 0);

  const sortRec = (arr: TreeNode[]): TreeNode[] => {
    arr.sort(sort);
    for (const n of arr) sortRec(n.children);
    return arr;
  };
  return sortRec(roots);
}

/** Flatten a tree to session ids in DFS order (for jump-target lists / persistence). */
export function flattenTree(roots: TreeNode[]): string[] {
  const out: string[] = [];
  const walk = (n: TreeNode): void => {
    out.push(n.node.id);
    for (const c of n.children) walk(c);
  };
  for (const r of roots) walk(r);
  return out;
}

/** Count nodes in a forest. */
export function countNodes(roots: TreeNode[]): number {
  return flattenTree(roots).length;
}
