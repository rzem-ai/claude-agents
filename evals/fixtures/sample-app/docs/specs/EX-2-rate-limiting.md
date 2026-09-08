# EX-2 Rate limiting on the auth routes

Status: draft. Not approved, and there is no plan for it.

## Problem

`/sessions/refresh` and `/me` accept unlimited requests, so a stolen token can be
brute forced against them at whatever rate the network allows.

## Non-goals

Rate limiting anything outside the auth routes. A global gateway policy.

## Acceptance criteria

- More than a fixed number of failed refreshes from one source is throttled.
- A throttled caller gets a 429 with a retry hint.

## Open questions

- The threshold and the window. Not decided.
- Whether the counter is per IP, per user or both. Not decided.
