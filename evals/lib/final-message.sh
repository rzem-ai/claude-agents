#!/usr/bin/env bash
#
# final-message.sh - pull the final assistant message out of what `claude -p`
# printed.
#
# The SubagentStop hook validates one string: `last_assistant_message`. The
# eval gate has to validate the same string, or CI and production disagree
# about the same run. What the runner captures is whatever the CLI wrote to
# stdout, which depends on --output-format, so this is the narrowing step.
#
# Usage:  evals/lib/final-message.sh <raw-capture-file>
#
# Prints the final assistant message on stdout, and one line naming the method
# on stderr. Methods, best first:
#
#   json-result          --output-format json (or stream-json): the `result`
#                        field of the last result record. This is the CLI's own
#                        name for the final assistant message and is the case
#                        the runner arranges by default.
#   stream-assistant     no result record, so the text blocks of the last
#                        `assistant` record, joined.
#   text-passthrough     the capture is not JSON, so it is used whole. With the
#                        default text output format that IS the final message,
#                        but the runner cannot prove it - see evals/README.md,
#                        "What the gate reads".
#
# Exit 0 whenever it produced something, 1 if the capture was empty or missing.

set -uo pipefail

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    printf 'final-message: no capture at %s\n' "${FILE:-none given}" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    printf 'text-passthrough (no jq)\n' >&2
    cat "$FILE"
    exit 0
fi

# `jq -s` slurps a single object, a JSON array and a JSONL stream alike. The
# inner flatten is for the versions that print an array of records rather than
# one record per line.
FLATTEN='[ .[] | if type == "array" then .[] else . end ] | map(select(type == "object"))'

result=$(jq -s -r "$FLATTEN"' | [ .[] | select(.type? == "result") | .result? | select(type == "string") ] | last // empty' \
    "$FILE" 2>/dev/null)
if [ -n "$result" ]; then
    printf 'json-result\n' >&2
    printf '%s\n' "$result"
    exit 0
fi

assistant=$(jq -s -r "$FLATTEN"' | [ .[] | select(.type? == "assistant") ] | last as $a | if $a == null then empty else ([ $a.message?.content[]? | select(.type? == "text") | .text ] | join("")) end' \
    "$FILE" 2>/dev/null)
if [ -n "$assistant" ]; then
    printf 'stream-assistant\n' >&2
    printf '%s\n' "$assistant"
    exit 0
fi

printf 'text-passthrough\n' >&2
cat "$FILE"
exit 0
