import { describe, expect, it } from "vitest";
import { isExpired, issueSession, validate } from "./session.js";

describe("session", () => {
  it("issues a session that is not yet expired", () => {
    const s = issueSession("user-1", 1000);
    expect(isExpired(s, 1000)).toBe(false);
  });

  it("rejects a revoked session", () => {
    const s = { ...issueSession("user-1", 1000), revokedAt: 1500 };
    expect(validate(s, 2000)).toBeNull();
  });
});
