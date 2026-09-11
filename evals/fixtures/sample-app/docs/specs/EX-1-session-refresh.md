# EX-1 Session refresh

Status: approved by the human.

## Problem

A session lasts twelve hours and then the user is signed out mid-task. There is
a `/sessions/refresh` route but it extends the existing session in place, so a
stolen refresh token stays usable for as long as the attacker keeps refreshing.

## Non-goals

Single sign-on, device management, and anything to do with the `/me` route.

## Acceptance criteria

- Refreshing a valid session issues a new refresh token and invalidates the old one.
- Presenting a refresh token that has already been used revokes the whole session.
- An expired session cannot be refreshed.
- A revoked session cannot be refreshed.

## Open questions

- How long should a refresh token live once rotation is in? Not decided.
