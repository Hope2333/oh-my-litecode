/** 第 n 个斐波那契数（朴素递归）。 */
export function fib(n: number): number {
  if (n < 2) return n
  return fib(n - 1) + fib(n - 2)
}