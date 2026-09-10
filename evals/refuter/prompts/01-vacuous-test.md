#!fixture: refuter-app
`src/limits.js` was fixed for an off-by-one: a caller sitting exactly at the
limit was still being let through. The diff that fixed it is at
`.eval-inputs/limits-fix.diff` and is already applied, so the tree here is the
fixed state.

Refute the fix. Its test is `test/limits.test.js`.
