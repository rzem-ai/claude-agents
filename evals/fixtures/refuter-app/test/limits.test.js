import { test } from "node:test";
import assert from "node:assert/strict";
import { underLimit } from "../src/limits.js";

test("underLimit allows another attempt below the limit", () => {
  assert.strictEqual(underLimit(2, 5), true);
});
