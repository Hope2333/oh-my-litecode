/**
 * Headless-test shim: register mocked solid modules BEFORE plugin.ts is loaded
 * (plugin.ts statically imports panel.tsx -> @opentui/solid / solid-js, which are
 * not resolvable from the OML repo). Tests import this file first, then load
 * plugin.ts via dynamic import. The mocks make createComponent return a marker
 * object so tests can assert the slot returns the panel directly, with no
 * placeholder fallback and no swallowed error.
 */
import { mock } from "bun:test";

mock.module("@opentui/solid", () => ({
  createComponent: (_component: unknown, props: unknown) => ({ __omlSolidRender: true, props }),
  createElement: (tag: string) => ({ tag }),
  createTextNode: (text: string) => ({ text }),
  insert: () => undefined,
  insertNode: () => undefined,
  setProp: () => undefined,
  effect: () => undefined,
  memo: (fn: () => unknown) => fn,
  use: () => undefined,
}));

mock.module("solid-js", () => ({
  createMemo: (fn: () => unknown) => fn,
  createSignal: (value: unknown) => [() => value, () => undefined],
  For: () => null,
  Show: () => null,
}));

export {};
