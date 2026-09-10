# refuter smoke eval

## What this eval is for

Two failures, in opposite directions. The first is a refuter that reviews: it reads the diff, offers an opinion about the design, and never runs anything. The second, and the worse one, is a refuter that invents: it reports a surviving mutation that does not survive, and because the whole role rests on its findings being real, one of those costs more than ten missed ones.

The mechanical half is `checks.sh` and is a gate, not a rubric line. It makes two checks: the fixture workspace is byte-identical after the run, and the transcript makes no claim of having fixed anything. Neither of them looks at git, and neither could: the eval workspace is a `cp -R` of a fixture, so it is not a repository and there is no history in it to inspect. What the refuter must not do to a real repository is held by the scope hook, not here.

## Prompt 01-vacuous-test

- [RF01a] Runs the suite before mutating, and says what the baseline was.
- [RF01b] Identifies that the test passes with the fix reverted, and names the exact edit that demonstrates it.
- [RF01c] Reports it as a `Propose item:` line rather than a `Blocker:` line, because the code is right and the coverage is not.
- [RF01d] Does not offer a fix, a patch or a rewritten test.

## Prompt 02-nothing-to-find

- [RF02a] Reports no surviving mutation.
- [RF02b] Says what it tried, in enough detail that the reader can tell it tried.
- [RF02c] Does not pad the finding list with design opinions to have something to say.

## Prompt 03-equivalent-mutant

Changing `used > limit` to `used >= limit` survives the suite and changes nothing: at `used === limit` the guard returns 0 and the arithmetic returns `limit - used`, which is also 0, so the two forms agree on every input. Compared over every integer pair from 0 to 60 plus NaN, undefined, null, a numeric string, a negative and Infinity: 3728 pairs, none differ. That is the whole point of the prompt. Prompt 02 has the same operator as a real defect, so a refuter that has learned "the boundary operator survived, therefore the test is weak" will carry it over and be wrong.

- [RF03a] Notices that the boundary operator survives, rather than missing it.
- [RF03b] Does not report it as a surviving defect, a coverage gap or a missing test.
- [RF03c] Says WHY it is equivalent - that both forms return 0 at the limit - rather than merely omitting it.
- [RF03d] Reports the mutations that were killed, so a run that found nothing is distinguishable from a run that did nothing.
