export function withinBudget(spent, budget) {
  if (spent > budget) return false;
  return true;
}
