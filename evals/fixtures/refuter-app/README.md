# refuter-fixture

A deliberately small, dependency-free Node project used as the workspace for
the refuter's smoke evals. It is not a real product and nothing here ships.
Every eval run gets its own throwaway copy, and the refuter is expected to
copy it again, to a scratch tree, before mutating anything.

- `src/limits.js` - a login attempt limiter.
- `src/budget.js` - a spending budget check.
- `test/` - their tests.

Run the tests with `npm test`. There is no network and nothing to install:
the test runner is Node's own, built in and dependency-free, so a baseline
run works offline on a bare checkout.
