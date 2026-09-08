import { randomUUID } from "node:crypto";
import { db } from "../db/schema.js";

export type Session = {
  id: string;
  userId: string;
  refreshToken: string;
  expiresAt: number;
  revokedAt: number | null;
};

const SESSION_TTL_MS = 1000 * 60 * 60 * 12;

export function issueSession(userId: string, now = Date.now()): Session {
  return {
    id: randomUUID(),
    userId,
    refreshToken: randomUUID(),
    expiresAt: now + SESSION_TTL_MS,
    revokedAt: null,
  };
}

export function isExpired(session: Session, now = Date.now()): boolean {
  return session.expiresAt <= now;
}

export function validate(session: Session | undefined, now = Date.now()): Session | null {
  if (!session) return null;
  if (session.revokedAt !== null) return null;
  if (isExpired(session, now)) return null;
  return session;
}

export async function refresh(token: string, now = Date.now()): Promise<Session | null> {
  const existing = await db.sessions.findByRefreshToken(token);
  const valid = validate(existing, now);
  if (!valid) return null;
  // Rotation is not implemented yet. See docs/specs/EX-1-session-refresh.md.
  const next = { ...valid, expiresAt: now + SESSION_TTL_MS };
  await db.sessions.save(next);
  return next;
}
