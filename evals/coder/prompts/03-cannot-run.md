#!fixture: sample-app
Implement phase 2 of `docs/plans/EX-1-session-refresh.md`, reuse detection.

Note that this workspace has no database and no network, so anything touching
`src/db/schema.ts` at runtime will throw.
