import { randomBytes } from "node:crypto";
import * as yup from "yup";
import { hashPassword, verifyAndUpgrade } from "../auth/crypto.js";
import { getGoogleProfile } from "../auth/google.js";
import { sendVerificationEmail } from "../auth/mailer.js";
import { RATE_LIMITS, VERIFY_TOKEN_TTL_MS } from "../constants.js";

const registerSchema = yup.object({
  email: yup.string().email().required(),
  username: yup
    .string()
    .min(3)
    .max(30)
    .matches(/^[a-zA-Z0-9_]+$/, "alphanumeric and underscores only")
    .required(),
  password: yup.string().min(8).max(100).required(),
  displayName: yup.string().max(50).optional(),
});

const loginSchema = yup.object({
  email: yup.string().email().required(),
  password: yup.string().required(),
});

const oauthCompleteSchema = yup.object({
  username: yup
    .string()
    .min(3)
    .max(30)
    .matches(/^[a-zA-Z0-9_]+$/, "alphanumeric and underscores only")
    .required(),
  displayName: yup.string().max(50).optional(),
});

function formatUser(user) {
  return {
    id: user.id,
    email: user.email,
    username: user.username,
    displayName: user.displayName,
    avatarUrl: user.avatarUrl,
    emailVerified: user.emailVerified,
    isAdmin: user.isAdmin,
    createdAt: user.createdAt,
  };
}

export default (app, prisma) => {
  // Attach req.auth on every request
  app.addHook("preHandler", async (req) => {
    req.auth = { user: null };
    const { userId } = req.session;
    if (!userId) return;
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { accounts: true },
    });
    if (user) req.auth = { user };
  });

  // POST /api/auth/register
  app.route({
    method: "POST",
    url: "/api/auth/register",
    config: { rateLimit: { max: RATE_LIMITS.REGISTER_MAX, timeWindow: RATE_LIMITS.REGISTER_WINDOW } },
    handler: async (req, reply) => {
      if (process.env.ALLOW_SIGNUPS !== "true") {
        return reply.code(403).send({ error: "Signups are disabled" });
      }

      const body = await registerSchema
        .validate(req.body, { abortEarly: false })
        .catch((err) => {
          reply.code(400).send({ error: err.errors.join(", ") });
          return null;
        });
      if (!body) return;

      const { email, username, password, displayName } = body;

      const existing = await prisma.user.findFirst({
        where: { OR: [{ email }, { username: { equals: username, mode: "insensitive" } }] },
      });
      if (existing) {
        return reply.code(400).send({
          error: existing.email === email ? "Email already in use" : "Username already taken",
        });
      }

      const verifyToken = randomBytes(32).toString("hex");
      const verifyTokenExp = new Date(Date.now() + VERIFY_TOKEN_TTL_MS);

      const user = await prisma.user.create({
        data: {
          email,
          username,
          displayName: displayName || username,
          hashedPassword: await hashPassword(password),
          emailVerified: false,
          verifyToken,
          verifyTokenExp,
        },
      });

      // Send verification email (non-blocking — don't fail registration if email fails)
      sendVerificationEmail(email, verifyToken).catch((err) =>
        req.log.error({ err }, "failed to send verification email")
      );

      return reply.code(201).send({
        message: "Account created. Please check your email to verify your address.",
        user: formatUser(user),
      });
    },
  });

  // GET /api/auth/verify-email?token=...
  app.get("/api/auth/verify-email", async (req, reply) => {
    const { token } = req.query;
    if (!token) return reply.code(400).send({ error: "Missing token" });

    const user = await prisma.user.findUnique({ where: { verifyToken: token } });
    if (!user || !user.verifyTokenExp || user.verifyTokenExp < new Date()) {
      return reply.redirect(
        `${process.env.FRONTEND_URL}/login?error=invalid_or_expired_token`
      );
    }

    await prisma.user.update({
      where: { id: user.id },
      data: { emailVerified: true, verifyToken: null, verifyTokenExp: null },
    });

    req.regenerateSession();
    req.session.userId = user.id;
    return reply.redirect(process.env.FRONTEND_URL);
  });

  // POST /api/auth/resend-verification
  app.route({
    method: "POST",
    url: "/api/auth/resend-verification",
    config: { rateLimit: { max: RATE_LIMITS.VERIFY_RESEND_MAX, timeWindow: RATE_LIMITS.VERIFY_RESEND_WINDOW } },
    handler: async (req, reply) => {
      const { email } = req.body || {};
      if (!email) return reply.code(400).send({ error: "Missing email" });

      const user = await prisma.user.findUnique({ where: { email } });
      // Always return 200 to avoid email enumeration
      if (!user || user.emailVerified) {
        return { message: "If that email is registered and unverified, a new link has been sent." };
      }

      const verifyToken = randomBytes(32).toString("hex");
      const verifyTokenExp = new Date(Date.now() + VERIFY_TOKEN_TTL_MS);
      await prisma.user.update({
        where: { id: user.id },
        data: { verifyToken, verifyTokenExp },
      });

      sendVerificationEmail(email, verifyToken).catch((err) =>
        req.log.error({ err }, "failed to resend verification email")
      );

      return { message: "If that email is registered and unverified, a new link has been sent." };
    },
  });

  // POST /api/auth/login
  app.route({
    method: "POST",
    url: "/api/auth/login",
    config: { rateLimit: { max: RATE_LIMITS.LOGIN_MAX, timeWindow: RATE_LIMITS.LOGIN_WINDOW } },
    handler: async (req, reply) => {
      const body = await loginSchema
        .validate(req.body, { abortEarly: false })
        .catch((err) => {
          reply.code(400).send({ error: err.errors.join(", ") });
          return null;
        });
      if (!body) return;

      const { email, password } = body;
      const user = await prisma.user.findUnique({
        where: { email },
        include: { accounts: true },
      });

      if (!user || !user.hashedPassword) {
        return reply.code(400).send({ error: "Invalid email or password" });
      }

      const result = await verifyAndUpgrade(user.hashedPassword, password);
      if (!result.ok) {
        return reply.code(400).send({ error: "Invalid email or password" });
      }

      if (!user.emailVerified) {
        return reply.code(403).send({ error: "Please verify your email before logging in." });
      }

      if (result.newHash) {
        await prisma.user.update({ where: { id: user.id }, data: { hashedPassword: result.newHash } });
      }

      req.regenerateSession();
      req.session.userId = user.id;
      return { user: formatUser(user) };
    },
  });

  // POST /api/auth/logout
  app.post("/api/auth/logout", async (req) => {
    await req.destroySession();
    return { ok: true };
  });

  // Google OAuth callback
  app.get("/api/oauth/google", async (req, reply) => {
    const isLink = Boolean(req.session?.grant?.dynamic?.link);
    try {
      const profile = await getGoogleProfile(req.session.grant.response);
      if (isLink) return handleGoogleLink(profile, req, reply);
      return handleGoogleLogin(profile, req, reply);
    } catch (err) {
      req.log.error({ err }, "google oauth failed");
      const path = isLink ? "/settings" : "/login";
      return reply.redirect(`${process.env.FRONTEND_URL}${path}?error=oauth_failed`);
    }
  });

  async function handleGoogleLogin({ sub, email, firstName, lastName }, req, reply) {
    const account = await prisma.account.findUnique({
      where: { provider_providerAccountId: { provider: "google", providerAccountId: sub } },
      include: { user: true },
    });

    if (!account) {
      const existingUser = await prisma.user.findUnique({ where: { email } });
      if (existingUser) {
        return reply.redirect(`${process.env.FRONTEND_URL}/login?error=email_exists`);
      }
      if (process.env.ALLOW_SIGNUPS !== "true") {
        return reply.code(403).send({ error: "Signups are disabled" });
      }

      req.session.oauthPending = { provider: "google", providerAccountId: sub, email, firstName, lastName };
      return reply.redirect(`${process.env.FRONTEND_URL}/complete-profile`);
    }

    await prisma.user.update({
      where: { id: account.userId },
      data: { displayName: `${firstName} ${lastName}`.trim() || account.user.displayName },
    });

    req.regenerateSession();
    req.session.userId = account.userId;
    return reply.redirect(process.env.FRONTEND_URL);
  }

  async function handleGoogleLink({ sub, firstName, lastName }, req, reply) {
    if (!req.auth.user) {
      return reply.redirect(`${process.env.FRONTEND_URL}/login?error=not_authenticated`);
    }

    const existing = await prisma.account.findUnique({
      where: { provider_providerAccountId: { provider: "google", providerAccountId: sub } },
    });
    if (existing && existing.userId !== req.auth.user.id) {
      return reply.redirect(`${process.env.FRONTEND_URL}/settings?error=account_linked`);
    }
    if (!existing) {
      await prisma.account.create({
        data: { provider: "google", providerAccountId: sub, userId: req.auth.user.id },
      });
    }

    req.regenerateSession();
    return reply.redirect(`${process.env.FRONTEND_URL}/settings`);
  }

  // POST /api/auth/complete-profile (after Google OAuth for new users)
  app.route({
    method: "POST",
    url: "/api/auth/complete-profile",
    config: { rateLimit: { max: RATE_LIMITS.OAUTH_COMPLETE_MAX, timeWindow: RATE_LIMITS.OAUTH_COMPLETE_WINDOW } },
    handler: async (req, reply) => {
      const pending = req.session.oauthPending;
      if (!pending) return reply.code(400).send({ error: "No pending OAuth session" });

      const body = await oauthCompleteSchema
        .validate(req.body, { abortEarly: false })
        .catch((err) => {
          reply.code(400).send({ error: err.errors.join(", ") });
          return null;
        });
      if (!body) return;

      const { username, displayName } = body;
      const { provider, providerAccountId, email, firstName, lastName } = pending;

      const taken = await prisma.user.findFirst({
        where: { username: { equals: username, mode: "insensitive" } },
      });
      if (taken) return reply.code(400).send({ error: "Username already taken" });

      const user = await prisma.$transaction(async (tx) => {
        const u = await tx.user.create({
          data: {
            email,
            username,
            displayName: displayName || `${firstName} ${lastName}`.trim() || username,
            emailVerified: true, // Google emails are verified
          },
        });
        await tx.account.create({
          data: { provider, providerAccountId, userId: u.id },
        });
        return u;
      });

      delete req.session.oauthPending;
      req.regenerateSession();
      req.session.userId = user.id;
      return { user: formatUser(user) };
    },
  });
};
