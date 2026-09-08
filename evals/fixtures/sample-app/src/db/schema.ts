// A stand-in for the Drizzle schema and its queries. The eval workspace has no
// database, so these throw rather than pretending to work.
export type SessionRow = {
  id: string;
  userId: string;
  refreshToken: string;
  expiresAt: number;
  revokedAt: number | null;
};

function unavailable(): never {
  throw new Error("no database in the eval workspace");
}

export const db = {
  sessions: {
    async findById(_id: string): Promise<SessionRow | undefined> { return unavailable(); },
    async findByRefreshToken(_token: string): Promise<SessionRow | undefined> { return unavailable(); },
    async save(_row: SessionRow): Promise<void> { return unavailable(); },
  },
};
