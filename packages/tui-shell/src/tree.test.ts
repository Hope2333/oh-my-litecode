import { describe, it, expect } from "bun:test";
import { buildSessionTree, flattenTree, countNodes, type SessionNode } from "./tree.ts";
import { toSessionNodes, pruneGhosts, type SessionSnapshot } from "./adapter.ts";

const S = (id: string, parentID?: string, extra: Partial<SessionNode> = {}): SessionNode => ({
  id,
  parentID,
  ...extra,
});

describe("buildSessionTree", () => {
  it("returns [] for empty input", () => {
    expect(buildSessionTree([])).toEqual([]);
  });

  it("skips invalid entries (missing/empty id)", () => {
    expect(buildSessionTree([S(""), { id: undefined as unknown as string }, S("ok")])).toHaveLength(1);
  });

  it("single root: depth 0, no ancestors, affiliation = own id", () => {
    const [r] = buildSessionTree([S("t1")]);
    expect(r!.depth).toBe(0);
    expect(r!.ancestors).toEqual([]);
    expect(r!.affiliation).toBe("t1");
    expect(r!.children).toHaveLength(0);
  });

  it("parent-child: child has parent ancestor + affiliation chain", () => {
    const [r] = buildSessionTree([S("t1"), S("t5", "t1")]);
    expect(r!.node.id).toBe("t1");
    expect(r!.children).toHaveLength(1);
    const child = r!.children[0]!;
    expect(child.node.id).toBe("t5");
    expect(child.depth).toBe(1);
    expect(child.ancestors).toEqual(["t1"]);
    expect(child.affiliation).toBe("t1←t5");
  });

  it("3-level chain builds full affiliation", () => {
    const [r] = buildSessionTree([S("t1"), S("t3", "t1"), S("t5", "t3")]);
    const leaf = r!.children[0]!.children[0]!;
    expect(leaf.depth).toBe(2);
    expect(leaf.ancestors).toEqual(["t1", "t3"]);
    expect(leaf.affiliation).toBe("t1←t3←t5");
  });

  it("uses titles in affiliation when useTitles=true", () => {
    const [r] = buildSessionTree(
      [S("t1", undefined, { title: "fix bug" }), S("t5", "t1", { title: "review" })],
      { useTitles: true },
    );
    expect(r!.children[0]!.affiliation).toBe("fix bug / review".replaceAll(" / ", "←"));
  });

  it("orphan parentID becomes a root (finite tree)", () => {
    const roots = buildSessionTree([S("t5", "missing-parent")]);
    expect(roots).toHaveLength(1);
    expect(roots[0]!.node.id).toBe("t5");
    expect(roots[0]!.depth).toBe(0);
  });

  it("cycle a→b→a is broken, no infinite loop", () => {
    const roots = buildSessionTree([S("a", "b"), S("b", "a")]);
    expect(countNodes(roots)).toBe(2);
    expect(roots.length).toBeGreaterThanOrEqual(1);
    // every node reachable exactly once
    expect(new Set(flattenTree(roots)).size).toBe(2);
  });

  it("self-parent (a→a) is treated as root", () => {
    const roots = buildSessionTree([S("a", "a")]);
    expect(roots).toHaveLength(1);
    expect(roots[0]!.node.id).toBe("a");
  });

  it("duplicate id: last wins", () => {
    const roots = buildSessionTree([S("t1", undefined, { agent: "first" }), S("t1", undefined, { agent: "last" })]);
    expect(roots).toHaveLength(1);
    expect(roots[0]!.node.agent).toBe("last");
  });

  it("maxDepth flattens deeper nodes (children not visited)", () => {
    const [r] = buildSessionTree([S("t1"), S("t3", "t1"), S("t5", "t3")], { maxDepth: 1 });
    // t5 still attached as child of t3 in the structure, but DFS stops at depth 1
    // so t5 keeps its parent link but is not traversed deeper (no children of its own here).
    expect(r!.children[0]!.children[0]!.node.id).toBe("t5");
    expect(r!.children[0]!.children[0]!.depth).toBe(0); // not visited → default depth
  });

  it("custom sort orders siblings", () => {
    const roots = buildSessionTree([S("b"), S("a")], {
      sort: (x, y) => y.node.id.localeCompare(x.node.id),
    });
    expect(roots.map((r) => r.node.id)).toEqual(["b", "a"]);
  });

  it("flattenTree and countNodes agree", () => {
    const roots = buildSessionTree([S("t1"), S("t5", "t1"), S("t3", "t1")]);
    expect(countNodes(roots)).toBe(flattenTree(roots).length);
    expect(flattenTree(roots).length).toBe(3);
  });
});

describe("toSessionNodes", () => {
  const store: Record<string, SessionSnapshot> = {
    t1: { id: "t1", parentID: undefined, title: "root" },
    t5: { id: "t5", parentID: "t1", title: "child" },
  };
  const get = (id: string): SessionSnapshot | undefined => store[id];

  it("maps snapshots to nodes with parentID", () => {
    const nodes = toSessionNodes(["t1", "t5"], get);
    expect(nodes).toHaveLength(2);
    expect(nodes[1]!.parentID).toBe("t1");
    expect(nodes[1]!.title).toBe("child");
  });

  it("dedupes ids and skips empty", () => {
    expect(toSessionNodes(["t1", "t1", "", "t5"], get)).toHaveLength(2);
  });

  it("uses custom label builder (U1 affiliation title)", () => {
    const nodes = toSessionNodes(["t5"], get, (s, id) => `omo t1←${id} · ${s.title}`);
    expect(nodes[0]!.title).toBe("omo t1←t5 · child");
  });

  it("falls back to id when snapshot missing", () => {
    const nodes = toSessionNodes(["ghost"], get);
    expect(nodes[0]!.title).toBe("ghost");
    expect(nodes[0]!.parentID).toBeUndefined();
  });

  it("survives a throwing getter", () => {
    const nodes = toSessionNodes(["x"], () => { throw new Error("boom"); });
    expect(nodes).toHaveLength(1);
    expect(nodes[0]!.title).toBe("x");
  });
});

describe("pruneGhosts", () => {
  it("drops unresolvable ids and children of missing parents", () => {
    const store: Record<string, SessionSnapshot> = {
      a: { id: "a" },
      b: { id: "b", parentID: "a" },
      c: { id: "c", parentID: "gone" },
    };
    const get = (id: string) => store[id];
    expect(pruneGhosts(["a", "b", "c", "z"], get)).toEqual(["a", "b"]);
  });

  it("keeps roots with no parent", () => {
    expect(pruneGhosts(["a"], (id) => ({ id }))).toEqual(["a"]);
  });
});
