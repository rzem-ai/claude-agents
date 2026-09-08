# ex-service

A deliberately small Fastify service used as the workspace for the fleet's
smoke evals. It is not a real product and nothing here ships. Every eval run
gets its own throwaway copy, so an agent may change files freely - and whether
it did is part of what the eval measures.

- `src/auth/session.ts` - session issue, refresh and validation.
- `src/api/routes.ts` - the two routes that use it.
- `src/db/schema.ts` - the Drizzle table behind it.
- `docs/specs/` - specs, as the glossary defines them.
- `docs/plans/` - plans, written by the lead and approved before any coder runs.

Run the tests with `npm test`. There is no network and no database in the eval
workspace, so anything needing either cannot be run here.
