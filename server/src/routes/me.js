import { randomBytes } from "node:crypto";
import { join } from "node:path";
import * as yup from "yup";
import { hashPassword, verifyAndUpgrade } from "../auth/crypto.js";
import { RATE_LIMITS } from "../constants.js";

function ensureAuth(req, reply) {
  if (!req.auth?.user) {
    reply.code(401).send({ error: "Unauthorized" });
    return false;
  }
  return true;
}

function formatUser(user) {
  return {
    id: user.id,
    email: user.email,
    username: user.username,
    displayName: user.displayName,
    avatarUrl: user.avatarUrl,
    publicKey: user.publicKey,
    encryptedPrivateKey: user.encryptedPrivateKey ?? null,
    keySalt: user.keySalt ?? null,
    keyNonce: user.keyNonce ?? null,
    emailVerified: user.emailVerified,
    isAdmin: user.isAdmin,
    hasPassword: Boolean(user.hashedPassword),
    createdAt: user.createdAt,
    accounts: user.accounts?.map((a) => ({ provider: a.provider })),
  };
}

const updateSchema = yup.object({
  displayName: yup.string().max(50).optional(),
  username: yup
    .string()
    .min(3)
    .max(30)
    .matches(/^[a-zA-Z0-9_]+$/, "alphanumeric and underscores only")
    .optional(),
});

const passwordSchema = yup.object({
  currentPassword: yup.string().required(),
  newPassword: yup.string().min(8).max(100).required(),
  encryptedPrivateKey: yup.string().optional(),
  keySalt: yup.string().optional(),
  keyNonce: yup.string().optional(),
});

// Short-lived in-memory store for OAuth link tokens: token → { userId, exp }
const LINK_TOKEN_TTL_MS = 5 * 60 * 1000;
export const linkTokens = new Map();

function pruneExpiredLinkTokens() {
  const now = Date.now();
  for (const [token, entry] of linkTokens) {
    if (entry.exp < now) linkTokens.delete(token);
  }
}

export default async (app, prisma) => {
  // GET /api/me
  app.get("/api/me", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;
    const user = await prisma.user.findUnique({
      where: { id: req.auth.user.id },
      include: { accounts: true },
    });
    return { user: formatUser(user) };
  });

  // PATCH /api/me
  app.route({
    method: "PATCH",
    url: "/api/me",
    config: { rateLimit: { max: RATE_LIMITS.PROFILE_UPDATE_MAX, timeWindow: RATE_LIMITS.PROFILE_UPDATE_WINDOW } },
    handler: async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      const body = await updateSchema
        .validate(req.body, { abortEarly: false })
        .catch((err) => { reply.code(400).send({ error: err.errors.join(", ") }); return null; });
      if (!body) return;

      if (body.username) {
        const taken = await prisma.user.findFirst({
          where: {
            username: { equals: body.username, mode: "insensitive" },
            NOT: { id: req.auth.user.id },
          },
        });
        if (taken) return reply.code(400).send({ error: "Username already taken" });
      }

      const user = await prisma.user.update({
        where: { id: req.auth.user.id },
        data: body,
        include: { accounts: true },
      });
      return { user: formatUser(user) };
    },
  });

  // POST /api/me/avatar (multipart upload)
  app.post("/api/me/avatar", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const data = await req.file();
    if (!data) return reply.code(400).send({ error: "No file uploaded" });

    const allowed = ["image/jpeg", "image/png", "image/webp", "image/gif"];
    if (!allowed.includes(data.mimetype)) {
      return reply.code(400).send({ error: "Invalid file type. Allowed: jpg, png, webp, gif" });
    }

    const { writeFile, mkdir } = await import("node:fs/promises");

    const ext = data.mimetype.split("/")[1];
    const filename = `${req.auth.user.id}-${randomBytes(6).toString("hex")}.${ext}`;
    const uploadDir = join(process.env.DATA_DIR ?? process.cwd(), "uploads", "avatars");
    await mkdir(uploadDir, { recursive: true });
    const buf = await data.toBuffer();
    await writeFile(join(uploadDir, filename), buf);

    const avatarUrl = `/uploads/avatars/${filename}`;
    const user = await prisma.user.update({
      where: { id: req.auth.user.id },
      data: { avatarUrl },
      include: { accounts: true },
    });
    return { user: formatUser(user) };
  });

  // POST /api/me/password — change password (requires current password)
  app.route({
    method: "POST",
    url: "/api/me/password",
    config: { rateLimit: { max: 3, timeWindow: "10 minutes" } },
    handler: async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      const user = await prisma.user.findUnique({
        where: { id: req.auth.user.id },
        include: { accounts: true },
      });
      if (!user.hashedPassword) {
        return reply.code(400).send({ error: "Account has no password. Use social login to sign in." });
      }

      const body = await passwordSchema
        .validate(req.body, { abortEarly: false })
        .catch((err) => { reply.code(400).send({ error: err.errors.join(", ") }); return null; });
      if (!body) return;

      const result = await verifyAndUpgrade(user.hashedPassword, body.currentPassword);
      if (!result.ok) return reply.code(400).send({ error: "Current password is incorrect" });

      const data = { hashedPassword: await hashPassword(body.newPassword) };
      // Re-encrypt E2E key backup with new password (all three must be present)
      if (body.encryptedPrivateKey && body.keySalt && body.keyNonce) {
        data.encryptedPrivateKey = body.encryptedPrivateKey;
        data.keySalt = body.keySalt;
        data.keyNonce = body.keyNonce;
      }
      await prisma.user.update({
        where: { id: req.auth.user.id },
        data,
      });
      return { ok: true };
    },
  });

  // DELETE /api/me/accounts/:provider — unlink a social account
  app.route({
    method: "DELETE",
    url: "/api/me/accounts/:provider",
    config: { rateLimit: { max: 5, timeWindow: "5 minutes" } },
    handler: async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      const { provider } = req.params;
      const user = await prisma.user.findUnique({
        where: { id: req.auth.user.id },
        include: { accounts: true },
      });

      if (!user.hashedPassword && user.accounts.length <= 1) {
        return reply.code(400).send({ error: "Cannot remove your only login method. Set a password first." });
      }

      const account = user.accounts.find((a) => a.provider === provider);
      if (!account) return reply.code(404).send({ error: "Linked account not found" });

      await prisma.account.delete({ where: { id: account.id } });
      return { ok: true };
    },
  });

  // GET /api/me/link-token — generate a one-time token for OAuth linking from desktop
  app.route({
    method: "GET",
    url: "/api/me/link-token",
    config: { rateLimit: { max: 5, timeWindow: "5 minutes" } },
    handler: async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      pruneExpiredLinkTokens();
      const token = randomBytes(32).toString("hex");
      linkTokens.set(token, { userId: req.auth.user.id, exp: Date.now() + LINK_TOKEN_TTL_MS });

      const url = `${process.env.SERVER_URL}/api/me/start-link/google?t=${token}`;
      return { token, url };
    },
  });

  // GET /api/me/start-link/:provider?t=TOKEN — browser entry point for link token flow
  app.get("/api/me/start-link/:provider", async (req, reply) => {
    const { provider } = req.params;
    const { t: token } = req.query;

    if (!token) return reply.code(400).send({ error: "Missing link token" });

    const entry = linkTokens.get(token);
    if (!entry || entry.exp < Date.now()) {
      linkTokens.delete(token);
      return reply.redirect(`${process.env.FRONTEND_URL}/profile?error=link_token_expired`);
    }

    linkTokens.delete(token); // consume immediately — single use
    req.session.linkUserId = entry.userId;

    if (provider !== "google") {
      return reply.code(400).send({ error: "Unsupported provider" });
    }

    return reply.redirect("/connect/google");
  });

  // POST /api/me/set-password — set initial password for social-only accounts
  app.route({
    method: "POST",
    url: "/api/me/set-password",
    config: { rateLimit: { max: 3, timeWindow: "10 minutes" } },
    handler: async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      const user = await prisma.user.findUnique({ where: { id: req.auth.user.id } });
      if (user.hashedPassword) {
        return reply.code(400).send({ error: "Password already set. Use change password instead." });
      }

      const { password } = req.body || {};
      if (!password || typeof password !== "string" || password.length < 8) {
        return reply.code(400).send({ error: "Password must be at least 8 characters" });
      }

      await prisma.user.update({
        where: { id: req.auth.user.id },
        data: { hashedPassword: await hashPassword(password) },
      });
      return { ok: true };
    },
  });
};
