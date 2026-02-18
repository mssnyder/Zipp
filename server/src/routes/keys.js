// E2E encryption public key exchange
function ensureAuth(req, reply) {
  if (!req.auth?.user) { reply.code(401).send({ error: "Unauthorized" }); return false; }
  return true;
}

export default async (app, prisma) => {
  // GET /api/keys/:userId — fetch a user's public key
  // Returns encrypted private key fields ONLY when requesting your own key
  app.get("/api/keys/:userId", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const isOwn = req.params.userId === req.auth.user.id;
    const user = await prisma.user.findUnique({
      where: { id: req.params.userId },
      select: {
        id: true,
        publicKey: true,
        ...(isOwn ? { encryptedPrivateKey: true, keySalt: true, keyNonce: true } : {}),
      },
    });
    if (!user) return reply.code(404).send({ error: "User not found" });

    const result = { userId: user.id, publicKey: user.publicKey };
    if (isOwn) {
      result.encryptedPrivateKey = user.encryptedPrivateKey ?? null;
      result.keySalt = user.keySalt ?? null;
      result.keyNonce = user.keyNonce ?? null;
    }
    return result;
  });

  // PUT /api/keys — upload or rotate caller's public key + optional encrypted private key backup
  app.put("/api/keys", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const { publicKey, encryptedPrivateKey, keySalt, keyNonce } = req.body || {};
    if (!publicKey || typeof publicKey !== "string") {
      return reply.code(400).send({ error: "Missing publicKey" });
    }

    const data = { publicKey };

    // All three encrypted key fields must be present together or none
    if (encryptedPrivateKey || keySalt || keyNonce) {
      if (typeof encryptedPrivateKey !== "string" || typeof keySalt !== "string" || typeof keyNonce !== "string") {
        return reply.code(400).send({ error: "encryptedPrivateKey, keySalt, and keyNonce must all be provided together as strings" });
      }
      data.encryptedPrivateKey = encryptedPrivateKey;
      data.keySalt = keySalt;
      data.keyNonce = keyNonce;
    }

    await prisma.user.update({
      where: { id: req.auth.user.id },
      data,
    });
    return { ok: true };
  });
};
