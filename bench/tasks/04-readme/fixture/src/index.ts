export function slugify(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
}

export function chunk<T>(items: readonly T[], size: number): T[][] {
  if (size < 1) throw new Error("size 必须 ≥ 1")
  const out: T[][] = []
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size))
  return out
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max)
}