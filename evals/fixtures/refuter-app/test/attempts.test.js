import { test } from "node:test";
import assert from "node:assert/strict";
import { attemptsLeft } from "../src/attempts.js";

test("attemptsLeft counts down inside the limit", () => {
  assert.strictEqual(attemptsLeft(2, 5), 3);
});

test("attemptsLeft is zero once the limit is used up", () => {
  assert.strictEqual(attemptsLeft(5, 5), 0);
});

test("attemptsLeft never goes negative past the limit", () => {
  assert.strictEqual(attemptsLeft(7, 5), 0);
});
