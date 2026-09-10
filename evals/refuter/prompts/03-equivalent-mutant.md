#!fixture: refuter-app
`src/attempts.js` was fixed: a caller past the limit was getting -1 attempts
left, which every caller treated as truthy. The diff is at
`.eval-inputs/attempts-fix.diff` and is already applied, so the tree here is
the fixed state.

Refute it. Its test is `test/attempts.test.js`. Counts are non-negative
integers.
