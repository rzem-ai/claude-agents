import type { FastifyInstance } from "fastify";
import { refresh, validate } from "../auth/session.js";
import { db } from "../db/schema.js";

export async function routes(app: FastifyInstance) {
  app.post("/sessions/refresh", async (request, reply) => {
    const token = (request.body as { refreshToken?: string })?.refreshToken;
    if (!token) return reply.code(400).send({ error: "refreshToken required" });
    const next = await refresh(token);
    if (!next) return reply.code(401).send({ error: "invalid refresh token" });
    return reply.send({ expiresAt: next.expiresAt, refreshToken: next.refreshToken });
  });

  app.get("/me", async (request, reply) => {
    const id = request.headers["x-session-id"];
    const session = await db.sessions.findById(String(id));
    const valid = validate(session);
    if (!valid) return reply.code(401).send({ error: "no session" });
    return reply.send({ userId: valid.userId });
  });
}
