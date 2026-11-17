import { describe, it, expect } from "bun:test";
import { buildSessionTree, flattenTree, countNodes, type SessionNode } from "./tree.ts";
import { tasksToNodes, annotateParadigms, type TaskLike } from "./adapter.ts";

const task = (id: string, parentId: string | null, extra: Partial<TaskLike> = {}): TaskLike => ({
  id,
  parentId,
  description: extra.description ?? `${id} desc`,
  kind: extra.kind ?? "task",
  status: extra.status ?? "pending",
  sessionId: extra.sessionId,
});

describe("classifyParadigm (via tree shape)", () => {
  it("kind=team → team regardless of children", async () => {
    const { classifyParadigm } = await import("./tree.ts");
    expect(classifyParadigm({ kind: "team", parentId: null }, false)).toBe("team");
    expect(classifyParadigm({ kind: "team", parentId: "root" }, true)).toBe("team");
  });

  it("leaf task → single", async () => {
    const { classifyParadigm } = await import("./tree.ts");
    expect(classifyParadigm({ kind: "task", parentId: null }, false)).toBe("single");
    expect(classifyParadigm({ kind: "task", parentId: "t1" }, false)).toBe("single");
  });

  it("task with children → nested", async () => {
    const { classifyParadigm } = await import("./tree.ts");
    expect(classifyParadigm({ kind: "task", parentId: "t1" }, true)).toBe("nested");
    expect(classifyParadigm({ kind: undefined, parentId: null }, true)).toBe("nested");
  });
});

describe("team fan-out", () => {
  it("team task + 2 members → team node with 2 member children", () => {
    const tasks: TaskLike[] = [
      { ...task("T", null, { kind: "team", description: "team: build it" }) },
      task("m1", "T", { description: "impl: do the work" }),
      task("m2", "T", { description: "review: check the work" }),
    ];
    const roots = buildSessionTree(tasksToNodes(tasks));
    annotateParadigms(roots);

    expect(roots).toHaveLength(1);
    const teamRoot = roots[0]!;
    expect(teamRoot.node.paradigm).toBe("team");
    expect(teamRoot.children).toHaveLength(2);
    expect(teamRoot.children.map((c) => c.node.id).sort()).toEqual(["m1", "m2"]);
    // members are leaves → single; roles parsed from "${role}: ${brief}"
    expect(teamRoot.children.every((c) => c.node.paradigm === "single")).toBe(true);
    const roles = teamRoot.children.map((c) => c.node.role).sort();
    expect(roles).toEqual(["impl", "review"]);
  });
});

describe("nested chain", () => {
  it("three-level parentId chain → ancestors nested, leaf single", () => {
    const tasks = [task("t1", null), task("t2", "t1"), task("t3", "t2")];
    const roots = buildSessionTree(tasksToNodes(tasks));
    annotateParadigms(roots);

    const r = roots[0]!;
    expect(r.node.id).toBe("t1");
    expect(r.node.paradigm).toBe("nested");
    const mid = r.children[0]!;
    expect(mid.node.id).toBe("t2");
    expect(mid.node.paradigm).toBe("nested");
    const leaf = mid.children[0]!;
    expect(leaf.node.id).toBe("t3");
    expect(leaf.node.paradigm).toBe("single");
  });
});

describe("hybrid: team with a nested sub-agent layer", () => {
  it("team → member that itself delegates (nested) → its leaf (single)", () => {
    const tasks: TaskLike[] = [
      { ...task("T", null, { kind: "team", description: "team: ship feature" }) },
      task("m1", "T", { description: "impl: part A" }),
      task("m2", "T", { description: "impl: part B" }),
      task("deep", "m2", { description: "deep: sub-delegate part B" }),
    ];
    const roots = buildSessionTree(tasksToNodes(tasks));
    annotateParadigms(roots);

    const teamRoot = roots[0]!;
    expect(teamRoot.node.paradigm).toBe("team");
    expect(teamRoot.children).toHaveLength(2);

    const m1 = teamRoot.children.find((c) => c.node.id === "m1")!;
    const m2 = teamRoot.children.find((c) => c.node.id === "m2")!;
    expect(m1.node.paradigm).toBe("single"); // leaf member
    expect(m2.node.paradigm).toBe("nested"); // member that delegated further
    expect(m2.children[0]!.node.id).toBe("deep");
    expect(m2.children[0]!.node.paradigm).toBe("single");
  });
});

describe("tasksToNodes field mapping", () => {
  it("maps real TaskRecord-shaped fields onto SessionNode", () => {
    const tasks: TaskLike[] = [
      {
        id: "t7",
        parentId: "t1",
        description: "fix the bug",
        kind: "task",
        status: "running",
        sessionId: "ses_abc",
      },
    ];
    const [n] = tasksToNodes(tasks);
    expect(n).toEqual({
      id: "t7",
      parentID: "t1",
      title: "fix the bug",
      taskId: "t7",
      kind: "task",
      status: "running",
      sessionId: "ses_abc",
      paradigm: undefined,
    } satisfies SessionNode);
  });

  it("team kind gets initial paradigm=team, null parentId → root", () => {
    const [n] = tasksToNodes([
      { id: "T", parentId: null, description: "team: x", kind: "team", status: "pending" },
    ]);
    expect(n!.paradigm).toBe("team");
    expect(n!.parentID).toBeUndefined();
    expect(n!.kind).toBe("team");
  });

  it("skips entries with empty id", () => {
    const out = tasksToNodes([
      { id: "", parentId: null, description: "bad" },
      task("ok", null),
    ]);
    expect(out).toHaveLength(1);
    expect(out[0]!.id).toBe("ok");
  });
});

describe("annotateParadigms structure invariance", () => {
  it("does not change flattenTree / countNodes / shape", () => {
    const tasks: TaskLike[] = [
      { ...task("T", null, { kind: "team", description: "team: x" }) },
      task("m1", "T", { description: "impl: a" }),
      task("m2", "T", { description: "review: b" }),
      task("t9", null),
      task("t10", "t9"),
    ];
    const before = buildSessionTree(tasksToNodes(tasks));
    const beforeFlat = flattenTree(before);
    const beforeCount = countNodes(before);

    annotateParadigms(before);

    const afterFlat = flattenTree(before);
    expect(afterFlat).toEqual(beforeFlat);
    expect(countNodes(before)).toBe(beforeCount);
    // every node got a paradigm assigned
    const all: SessionNode[] = [];
    const walk = (ns: ReturnType<typeof buildSessionTree>) => {
      for (const n of ns) {
        all.push(n.node);
        walk(n.children);
      }
    };
    walk(before);
    expect(all.length).toBe(beforeCount);
    expect(all.every((n) => n.paradigm !== undefined)).toBe(true);
  });
});
