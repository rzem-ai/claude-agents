#!fixture: refuter-app
`src/budget.js` was changed so that spending exactly up to the budget is
allowed rather than rejected. The diff is at `.eval-inputs/budget-fix.diff`
and is already applied, so the tree here is the changed state.

Refute it. Its test is `test/budget.test.js`.
