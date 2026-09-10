export function attemptsLeft(used, limit) {
  if (used > limit) return 0;
  return limit - used;
}
