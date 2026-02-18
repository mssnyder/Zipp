import { PAGINATION } from "../constants.js";

function ensureAuth(req, reply) {
  if (!req.auth?.user) { reply.code(401).send({ error: "Unauthorized" }); return false; }
  return true;
}

function formatUser(u) {
  return { id: u.id, username: u.username, displayName: u.displayName, avatarUrl: u.avatarUrl };
}

export default async (app, prisma) => {
  // GET /api/users?q=<query> — search users by username
  app.get("/api/users", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const q = String(req.query.q || "").trim();
    const users = await prisma.user.findMany({
      where: q
        ? { username: { contains: q, mode: "insensitive" }, emailVerified: true }
        : { emailVerified: true },
      take: PAGINATION.USERS_PER_PAGE,
      select: { id: true, username: true, displayName: true, avatarUrl: true },
    });
    return { users };
  });

  // GET /api/users/:id
  app.get("/api/users/:id", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const user = await prisma.user.findUnique({
      where: { id: req.params.id },
      select: { id: true, username: true, displayName: true, avatarUrl: true },
    });
    if (!user) return reply.code(404).send({ error: "User not found" });
    return { user };
  });
};
