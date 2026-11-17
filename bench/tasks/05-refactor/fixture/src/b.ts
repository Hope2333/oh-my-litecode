import { normalize } from "./a.ts"

/** 与 a.ts 里的 normalize 逐字重复——这是本任务要消除的重复。 */
export function tidy(input: string): string {
  return input
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ")
    .replace(/[^\w\s-]/g, "")
}

export function keyOf(input: string): string {
  return `${normalize(input)}:${tidy(input)}`
}