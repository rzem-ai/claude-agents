import { test } from "node:test";
import assert from "node:assert/strict";
import { withinBudget } from "../src/budget.js";

test("withinBudget allows spending exactly up to the budget", () => {
  assert.strictEqual(withinBudget(50, 50), true);
});

test("withinBudget rejects spending over the budget", () => {
  assert.strictEqual(withinBudget(51, 50), false);
});

test("withinBudget allows spending under the budget", () => {
  assert.strictEqual(withinBudget(10, 50), true);
});
