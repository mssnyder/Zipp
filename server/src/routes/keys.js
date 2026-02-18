// E2E encryption public key exchange
function ensureAuth(req, reply) {
  if (!req.auth?.user) { reply.code(401).send({ error: "Unauthorized" }); return false; }
  return true;
}

export default async (app, prisma) => {
  // GET /api/keys/:userId — fetch a user's public key
  app.get("/api/keys/:userId", async (req, reply) => {
    if (!ensureAuth(req, reply)) return;

    const user = await prisma.user.findUnique({
      where: { id: req.params.userId },
      select: { id: true, publicKey: true },
    });
    if (!user) return reply.code(404).send({ error: "User not found" });
    return { userId: user.id, publicKey: user.publicKey };
  });

  // PUT /api/keys — upload or rotate caller's public key
  app.put("/api/keys", async (req, reply) => {
    if (!ensureAuth(req, reply)) return;

    const { publicKey } = req.body || {};
    if (!publicKey || typeof publicKey !== "string") {
      return reply.code(400).send({ error: "Missing publicKey" });
    }

    await prisma.user.update({
      where: { id: req.auth.user.id },
      data: { publicKey },
    });
    return { ok: true };
  });
};
