---
description: Remove agent worktrees whose work has been adopted - clean, merged into the default branch, and under .claude/worktrees/ - and report every one kept and why
---

Prune the agent worktrees in this project. The harness cuts a linked worktree under `.claude/worktrees/` for every properly-typed `coder` spawn and removes it again only if it is *unchanged* - deliberate, because a changed worktree holds commits that may exist nowhere else. A coder that did its job therefore always leaves one behind, nothing in the pipeline removes it after the work merges, and they accumulate: one project collected eleven of them, 8.5 GB with dependencies installed, before the human deleted them by hand. This command is the removal step, and it is safe by construction - it removes a worktree only when git can show the work has been adopted, and it never uses `--force`.

## What "adopted" means

A worktree is removable when all three hold, each answered by git rather than by anything an agent said:

1. Its path is under `.claude/worktrees/` in this repository. Any other linked worktree is somebody's deliberate checkout; leave it alone and do not even mention it beyond the report.
2. `git -C <path> status --porcelain` is empty. A dirty worktree holds uncommitted work that exists nowhere else. Skip it, whatever else is true.
3. Its HEAD is an ancestor of the default branch: `git merge-base --is-ancestor <worktree-HEAD> <default>` exits 0. The default branch is what `origin/HEAD` points at, or `main` when there is no remote. A worktree whose commits are not in the default branch is unadopted work - possibly waiting on a review round - and is kept.

## Procedure

1. `git worktree list --porcelain` from the repository root. The first entry is the main checkout; never touch it.
2. For each remaining entry, apply the three tests above. Collect the verdicts before removing anything.
3. For each removable worktree: `git worktree unlock <path>` if the porcelain output marked it locked (the harness locks what it cuts), then `git worktree remove <path>`. No `--force`, ever - if the remove refuses after the checks passed, that refusal is information; report it and move on.
4. For each worktree just removed that had a branch checked out: `git branch -d <branch>` - lowercase `-d`, which refuses an unmerged branch, and a refusal there is kept, not forced.
5. `git worktree prune` once at the end, to drop metadata for any worktree whose directory is already gone.
6. Sweep the scratch directories. The harness gives every session a scratchpad under `/private/tmp/claude-<uid>/<encoded-cwd>/`, where `<encoded-cwd>` is the session's working directory with every `/` and `.` replaced by `-` (verified against live dirs: `echo <path> | tr '/.' '--'` reproduces the name exactly). A session that ran inside a worktree therefore leaves a directory whose name contains `--claude-worktrees-`, and nothing removes it when the worktree goes - macOS's nightly `tmp_cleaner` only deletes files untouched on atime, mtime *and* ctime for 3 days, so anything that scans the tree keeps them alive. For each entry under `/private/tmp/claude-$(id -u)/` whose name contains `--claude-worktrees-`: encode this repository's root the same way, and skip the entry unless its name starts with that prefix - another project's scratch is not this command's to judge. Then reconstruct nothing: encode the path of every worktree that *currently exists* in this repository, and delete the entry only if its name matches none of them. A matching entry belongs to a live worktree, possibly a live session; an unmatched one is scratch for a worktree that no longer exists, which no session can be using. `rm -rf` is fine there - it is per-session temp space, never work.
7. Report in four lists: worktrees removed (path, branch, HEAD), worktrees kept (path and which test it failed - dirty, unmerged, or not an agent worktree), scratch directories deleted, and refusals git raised despite the checks. An empty removed list on a project with no leftover worktrees is the good outcome, not a failure.

Never run this in the middle of a review round: a fix worktree that has not merged yet fails test 3 and is kept, so the command is safe then too, but the report will name it and the noise helps nobody. The natural moment is right after adopting a coder's work, which is when the lead's merge step points here.
