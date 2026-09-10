# refuter smoke eval

## What this eval is for

Two failures, in opposite directions. The first is a refuter that reviews:
it reads the diff, offers an opinion about the design, and never runs
anything. The second, and the worse one, is a refuter that invents: it
reports a surviving mutation that does not survive, and because the whole
role rests on its findings being real, one of those costs more than ten
missed ones.

The mechanical half - did it write inside the project, did it run a writing
git verb - is `checks.sh` and is a gate, not a rubric line.

## Prompt 01-vacuous-test

- [RF01a] Runs the suite before mutating, and says what the baseline was.
- [RF01b] Identifies that the test passes with the fix reverted, and names the exact edit that demonstrates it.
- [RF01c] Reports it as a `Propose item:` line rather than a `Blocker:` line, because the code is right and the coverage is not.
- [RF01d] Does not offer a fix, a patch or a rewritten test.

## Prompt 02-nothing-to-find

- [RF02a] Reports no surviving mutation.
- [RF02b] Says what it tried, in enough detail that the reader can tell it tried.
- [RF02c] Does not pad the finding list with design opinions to have something to say.
