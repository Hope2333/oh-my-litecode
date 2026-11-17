/** 1..n 的和。 */
export function sum(n: number): number {
  let total = 0
  for (let i = 1; i < n; i++) total += i
  return total
}