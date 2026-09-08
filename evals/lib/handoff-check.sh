#!/usr/bin/env bash
#
# handoff-check.sh - the one check every eval shares.
#
# Three hooks parse the four-heading handoff, so a body that drifts off the
# format breaks the board rather than just reading badly. This is the machine
# reading of `claude-agents/skills/handoff/SKILL.md`, applied to the final
# message of an eval run.
#
# Usage:  evals/lib/handoff-check.sh <transcript-file>
#
# Prints one line per check - PASS, FAIL or WARN, then the check id, then what
# it looked at. Exits 0 if every check passed, 1 if any FAILed. WARN never
# fails the run.
#
# Checks:
#   H1  all four headings present, each exactly once
#   H2  the four headings in order, and the handoff is one contiguous block
#   H3  no other level-2 heading anywhere in the message
#   H4  every line in the block is a top-level "- " item, no nesting, no blanks,
#       no fences, no tables
#   H5  no section is empty; an empty section is exactly "- None"
#   H6  every Decisions needed line is Blocker:, Propose item: or Propose memory:
#   H7  nothing follows the last item of Decisions needed
#   H8  the token "Blocker:" appears nowhere except on a typed line
#   H9  (warn) no item much over 200 characters

set -euo pipefail

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    printf 'FAIL H0 no transcript to check (%s)\n' "${FILE:-none given}"
    exit 1
fi

awk '
function pass(id, msg) { printf "PASS %s %s\n", id, msg }
function fail(id, msg) { printf "FAIL %s %s\n", id, msg; failed = 1; bad[id] = 1 }
function warn(id, msg) { printf "WARN %s %s\n", id, msg }
function finish() { if (failed) exit 1; exit 0 }

BEGIN {
    failed = 0
    h[1] = "## Done"
    h[2] = "## Not done"
    h[3] = "## Unverified"
    h[4] = "## Decisions needed"
}

{ line[NR] = $0 }

END {
    total = NR

    # Locate every level-2 heading and the start of the handoff block.
    start = 0
    other_h2 = 0
    other_h2_line = ""
    for (i = 1; i <= total; i++) {
        if (line[i] ~ /^## /) {
            known = 0
            for (k = 1; k <= 4; k++) if (line[i] == h[k]) known = 1
            if (!known) {
                other_h2++
                if (other_h2_line == "") other_h2_line = "line " i ": " line[i]
            }
            if (line[i] == h[1]) start = i
        }
    }

    # H1 - presence and uniqueness.
    missing = ""
    dupe = ""
    for (k = 1; k <= 4; k++) {
        n = 0
        for (i = 1; i <= total; i++) if (line[i] == h[k]) n++
        if (n == 0) missing = missing (missing == "" ? "" : ", ") h[k]
        if (n > 1) dupe = dupe (dupe == "" ? "" : ", ") h[k]
    }
    if (missing != "") fail("H1", "missing heading(s): " missing)
    else if (dupe != "") fail("H1", "repeated heading(s): " dupe)
    else pass("H1", "all four headings present exactly once")

    # H3 - no other level-2 heading anywhere in the message.
    if (other_h2 > 0) fail("H3", other_h2 " other level-2 heading(s), first at " other_h2_line)
    else pass("H3", "no other level-2 heading")

    if (missing != "") finish()

    # H2 - order, and one contiguous block.
    pos[1] = start
    seq_ok = 1
    cur = 1
    for (i = start + 1; i <= total; i++) {
        for (k = 2; k <= 4; k++) {
            if (line[i] == h[k]) {
                if (k != cur + 1) seq_ok = 0
                cur = k
                pos[k] = i
            }
        }
    }
    if (cur != 4) seq_ok = 0
    if (seq_ok) pass("H2", "headings in order, block starts at line " start)
    else { fail("H2", "headings out of order or not one contiguous block"); finish() }

    # H4 to H6 - the body of each section. Blank lines separating a section from
    # the next heading are normal markdown; blank lines between items are not.
    for (k = 1; k <= 4; k++) {
        from = pos[k] + 1
        to = (k < 4) ? pos[k + 1] - 1 : total
        while (to >= from && line[to] ~ /^[[:space:]]*$/) to--

        items = 0
        none = 0
        for (i = from; i <= to; i++) {
            s = line[i]
            if (s ~ /^[[:space:]]*$/) {
                fail("H4", "blank line between items in " h[k] " at line " i)
                continue
            }
            if (s !~ /^- /) {
                fail("H4", "not a top-level item in " h[k] " at line " i ": " substr(s, 1, 60))
                continue
            }
            items++
            if (s == "- None") none++
            if (length(s) > 240) warn("H9", "item over 240 characters in " h[k] " at line " i)
            if (k == 4) {
                if (s != "- None" && s !~ /^- (Blocker|Propose item|Propose memory): /) {
                    fail("H6", "untyped Decisions needed line at " i ": " substr(s, 1, 60))
                }
            }
        }
        if (items == 0) fail("H5", h[k] " is empty; an empty section is exactly \"- None\"")
        else if (none > 0 && items > 1) fail("H5", h[k] " mixes \"- None\" with real items")
    }
    if (!("H4" in bad)) pass("H4", "every line is one top-level item")
    if (!("H5" in bad)) pass("H5", "every section has content, and empty means \"- None\"")
    if (!("H6" in bad)) pass("H6", "every Decisions needed line is typed or None")

    # H7 - nothing follows the last item.
    last = total
    while (last > 0 && line[last] ~ /^[[:space:]]*$/) last--
    if (last > pos[4] && line[last] ~ /^- /) pass("H7", "the handoff is the last thing in the message")
    else fail("H7", "content follows the last Decisions needed item, at line " last)

    # H8 - the Blocker token only ever on a typed line.
    stray = 0
    stray_line = ""
    for (i = 1; i <= total; i++) {
        if (line[i] ~ /Blocker:/ && line[i] !~ /^- Blocker: /) {
            stray++
            if (stray_line == "") stray_line = "line " i ": " substr(line[i], 1, 60)
        }
    }
    if (stray > 0) fail("H8", "the Blocker token appears off a typed line, " stray_line)
    else pass("H8", "the Blocker token appears only on typed lines")

    finish()
}
' "$FILE"
