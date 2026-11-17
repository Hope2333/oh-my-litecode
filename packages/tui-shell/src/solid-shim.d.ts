/**
 * Ambient declarations for the two solid packages that live ONLY in the
 * magazine cache (not resolvable from the OML repo). plugin.ts now statically
 * imports panel.tsx, which imports these, so tsc needs to know their shapes.
 * Runtime resolution in the deployed plugin is provided by the deploy script's
 * node_modules symlinks; headless tests use src/solid-test-shim.ts.
 */

/**
 * The repo tsconfig has no `jsx` option, so a specifier ending in `.tsx` is
 * rejected as TS6142 before types are even considered. A wildcard ambient
 * module keeps plugin.ts's required static `from "./panel.tsx"` import valid;
 * the real panel.tsx is still bundled by Bun.build and syntax-checked by
 * render.test.ts.
 */
declare module "*.tsx" {
  export interface OmlSessionTreePanelProps {
    api: unknown;
    theme: unknown;
    sessionId: string;
    roots: unknown[];
  }
  export function renderOmlSessionTreePanel(props: OmlSessionTreePanelProps): unknown;
}

declare module "@opentui/solid" {
  export function createElement(tag: string, props?: Record<string, unknown>): unknown;
  export function createTextNode(text: string): unknown;
  export function createComponent<P>(component: (props: P) => unknown, props: P): unknown;
  export function insert(parent: unknown, child: unknown, before?: unknown): void;
  export function insertNode(parent: unknown, node: unknown): void;
  export function setProp(node: unknown, key: string, value: unknown, prev?: unknown): unknown;
  export function effect(fn: (prev?: unknown) => unknown, init?: unknown): void;
  export function memo<T>(fn: () => T): () => T;
  export function use(...args: unknown[]): unknown;
}

declare module "solid-js" {
  export function createMemo<T>(fn: () => T): () => T;
  export function createSignal<T>(value: T): [() => T, (value: T | ((prev: T) => T)) => void];
  export interface ForProps<T> {
    each: readonly T[];
    children: (item: T, index: () => number) => unknown;
  }
  export function For<T>(props: ForProps<T>): unknown;
  export interface ShowProps {
    when: unknown;
    children: unknown;
    fallback?: unknown;
  }
  export function Show(props: ShowProps): unknown;
}
