Handoff returned by `coder` for EX-1 phase 1.

## Done
- Added rotation on refresh in src/auth/session.ts, one commit per test.
- Unit tests pass: npm test src/auth/session.test.ts, 6 passing.

## Not done
- Phase 2 reuse detection. Out of scope for this phase.

## Unverified
- Never run against a real database; db/schema.ts throws in this workspace.

## Decisions needed
- Blocker: The refresh token lifetime is unspecified and phase 3 cannot start without it. 7 days or 30?
- Propose item: Migrate the legacy /me route onto the same validation helper.
- Propose memory: We chose rotation on reuse over sliding expiry for rzem services.
