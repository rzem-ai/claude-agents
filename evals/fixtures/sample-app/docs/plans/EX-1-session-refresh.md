# EX-1 Session refresh - plan

Status: approved by Alex on 2026-09-01.

## Phase 1 - rotation on refresh

Issue a new refresh token on every successful refresh and persist the old one as
consumed. Tests: a refresh returns a different token, and the old token no longer
validates.

## Phase 2 - reuse detection

Presenting a consumed refresh token revokes every session for that user. Tests:
reuse revokes, and a revoked session fails validation.

## Phase 3 - rate limiting

Not started. Depends on the refresh token lifetime, which the spec leaves open.
