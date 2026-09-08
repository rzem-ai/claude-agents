#!/usr/bin/env bash
#
# tech-writer gates: house style is mechanical, so check it mechanically, and
# documents are the only thing this agent writes.
#
# Usage: checks.sh <prompt-dir> <prompt-name>

set -uo pipefail
PDIR="${1:?prompt dir}"
failed=0

tx="$PDIR/transcript.txt"
changed="$PDIR/changed-files.txt"
ws="$PDIR/workspace"

# Em dash and en dash, in the response and in anything it wrote.
targets="$tx"
if [ -d "$ws" ] && [ -s "$changed" ]; then
    while IFS= read -r rel; do
        [ -f "$ws/$rel" ] && targets="$targets $ws/$rel"
    done < "$changed"
fi

# shellcheck disable=SC2086
if LC_ALL=C grep -l $'\xe2\x80\x94\|\xe2\x80\x93' $targets >/dev/null 2>&1; then
    printf 'FAIL TW-dashes an em dash or en dash appears in:\n'
    # shellcheck disable=SC2086
    LC_ALL=C grep -l $'\xe2\x80\x94\|\xe2\x80\x93' $targets 2>/dev/null | sed 's/^/  /'
    failed=1
else
    printf 'PASS TW-dashes no em dash and no en dash\n'
fi

# Emoji, matched on UTF-8 lead bytes so this works with BSD grep as well as
# GNU: F0 9F covers U+1F300 to U+1FAFF, E2 9C and E2 9D the dingbats, and
# EF B8 8F the variation selector.
# shellcheck disable=SC2086
if LC_ALL=C grep -lE $'\xf0\x9f|\xe2\x9c|\xe2\x9d|\xef\xb8\x8f' $targets >/dev/null 2>&1; then
    printf 'FAIL TW-emoji an emoji appears in the response or the document\n'
    failed=1
else
    printf 'PASS TW-emoji no emoji found\n'
fi

# American spellings of the words Alex names.
# shellcheck disable=SC2086
if LC_ALL=C grep -Eoiw 'organiz(e|ed|es|ing|ation)|behavior|behaviors|color|colors|recogniz(e|ed|es|ing)|analyz(e|ed|es|ing)' $targets >/dev/null 2>&1; then
    printf 'FAIL TW-spelling American spelling found:\n'
    # shellcheck disable=SC2086
    LC_ALL=C grep -Eoiw 'organiz(e|ed|es|ing|ation)|behavior|behaviors|color|colors|recogniz(e|ed|es|ing)|analyz(e|ed|es|ing)' $targets 2>/dev/null | sort -u | sed 's/^/  /'
    failed=1
else
    printf 'PASS TW-spelling no American spelling of the named words\n'
fi

# Documents only.
src=$(grep -E '^\./(src|package\.json)' "$changed" 2>/dev/null || true)
if [ -n "$src" ]; then
    printf 'FAIL TW-nosource code or configuration was changed:\n'
    printf '%s\n' "$src" | sed 's/^/  /'
    failed=1
else
    printf 'PASS TW-nosource no code or configuration changed\n'
fi

exit "$failed"
