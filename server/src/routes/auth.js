import { randomBytes } from "node:crypto";
import * as yup from "yup";
import { hashPassword, verifyAndUpgrade } from "../auth/crypto.js";
import { getGoogleProfile } from "../auth/google.js";
import { sendVerificationEmail } from "../auth/mailer.js";
import { RATE_LIMITS, VERIFY_TOKEN_TTL_MS } from "../constants.js";

// In-memory store for native desktop OAuth login tokens: token → { userId, expiresAt }
const NLT_TTL_MS = 5 * 60 * 1000;
const nativeLoginTokens = new Map();

function pruneExpiredNLTs() {
  const now = Date.now();
  for (const [token, entry] of nativeLoginTokens) {
    if (entry.expiresAt < now) nativeLoginTokens.delete(token);
  }
}
setInterval(pruneExpiredNLTs, 60_000);

async function generateUsername(firstName, lastName, email, prisma) {
  let base = `${firstName || ""}${lastName || ""}`.toLowerCase().replace(/[^a-z0-9_]/g, "");
  if (base.length < 3) base = email.split("@")[0].replace(/[^a-z0-9_]/g, "");
  if (base.length < 3) base = "user";
  base = base.substring(0, 20);
  let username = base;
  for (let attempt = 0; attempt < 5; attempt++) {
    const taken = await prisma.user.findFirst({
      where: { username: { equals: username, mode: "insensitive" } },
    });
    if (!taken) return username;
    const suffix = Math.floor(1000 + Math.random() * 9000);
    username = `${base}_${suffix}`;
  }
  return `user_${randomBytes(4).toString("hex")}`;
}

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
      if (!body) return reply;

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
      if (!body) return reply;

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

  // ── Native desktop Google sign-in (token-based bridge) ─────────────────

  // POST /api/auth/native-login-start — create a pending login token
  app.route({
    method: "POST",
    url: "/api/auth/native-login-start",
    config: { rateLimit: { max: 10, timeWindow: "5 minutes" } },
    handler: async (req, reply) => {
      pruneExpiredNLTs();
      const token = randomBytes(32).toString("hex");
      nativeLoginTokens.set(token, { userId: null, expiresAt: Date.now() + NLT_TTL_MS });
      return {
        token,
        url: `${process.env.SERVER_URL}/api/auth/native-start-google?t=${token}`,
      };
    },
  });

  // GET /api/auth/native-start-google — browser entry point, stores token in session then redirects to OAuth
  app.get("/api/auth/native-start-google", async (req, reply) => {
    const { t: token } = req.query;
    if (!token) return reply.code(400).send({ error: "Missing token" });

    const entry = nativeLoginTokens.get(token);
    if (!entry || entry.expiresAt < Date.now()) {
      nativeLoginTokens.delete(token);
      return reply.type("text/html").send(
        '<html><body style="display:flex;justify-content:center;align-items:center;height:100vh;font-family:system-ui"><div><h2>Link expired</h2><p>Please try again from the app.</p></div></body></html>'
      );
    }

    req.session.nlt = token;
    return reply.redirect("/connect/google");
  });

  // GET /api/auth/native-login-poll — native app polls this until OAuth completes
  app.route({
    method: "GET",
    url: "/api/auth/native-login-poll",
    config: { rateLimit: { max: 200, timeWindow: "5 minutes" } },
    handler: async (req, reply) => {
      const { token } = req.query;
      if (!token) return reply.code(400).send({ error: "Missing token" });

      const entry = nativeLoginTokens.get(token);
      if (!entry || entry.expiresAt < Date.now()) {
        nativeLoginTokens.delete(token);
        return reply.code(410).send({ error: "Token expired or not found" });
      }
      if (!entry.userId) {
        return reply.code(202).send({ status: "pending" });
      }

      // Success — create session for the native app
      nativeLoginTokens.delete(token);
      const user = await prisma.user.findUnique({
        where: { id: entry.userId },
        include: { accounts: true },
      });
      if (!user) return reply.code(404).send({ error: "User not found" });

      req.regenerateSession();
      req.session.userId = entry.userId;
      return { user: formatUser(user) };
    },
  });

  // Google OAuth callback
  app.get("/api/oauth/google", async (req, reply) => {
    // isLink is true for both the old grant.dynamic.link flow and the new linkUserId token flow
    const isLink = Boolean(req.session?.grant?.dynamic?.link) || Boolean(req.session?.linkUserId);
    try {
      const profile = await getGoogleProfile(req.session.grant.response);
      if (isLink) return handleGoogleLink(profile, req, reply);
      return handleGoogleLogin(profile, req, reply);
    } catch (err) {
      req.log.error({ err }, "google oauth failed");
      const path = isLink ? "/profile" : "/login";
      return reply.redirect(`${process.env.FRONTEND_URL}${path}?error=oauth_failed`);
    }
  });

  const NLT_SUCCESS_HTML = `<!DOCTYPE html><html><body style="display:flex;justify-content:center;align-items:center;height:100vh;font-family:system-ui;background:#1a1a2e;color:#e0e0e0"><div style="text-align:center"><h2 style="color:#6ee7b7">Login successful</h2><p>You can close this tab and return to the app.</p></div></body></html>`;

  async function handleGoogleLogin({ sub, email, firstName, lastName }, req, reply) {
    const nlt = req.session?.nlt;

    let account = await prisma.account.findUnique({
      where: { provider_providerAccountId: { provider: "google", providerAccountId: sub } },
      include: { user: true },
    });

    if (!account) {
      const existingUser = await prisma.user.findUnique({ where: { email } });
      if (existingUser) {
        if (nlt) nativeLoginTokens.delete(nlt);
        return reply.redirect(`${process.env.FRONTEND_URL}/login?error=email_exists`);
      }
      if (process.env.ALLOW_SIGNUPS !== "true") {
        if (nlt) nativeLoginTokens.delete(nlt);
        return reply.code(403).send({ error: "Signups are disabled" });
      }

      // Auto-create user from Google profile
      const username = await generateUsername(firstName, lastName, email, prisma);
      const newUser = await prisma.$transaction(async (tx) => {
        const u = await tx.user.create({
          data: {
            email,
            username,
            displayName: `${firstName || ""} ${lastName || ""}`.trim() || username,
            hashedPassword: null,
            emailVerified: true,
          },
        });
        await tx.account.create({
          data: { provider: "google", providerAccountId: sub, userId: u.id },
        });
        return u;
      });

      if (nlt) {
        const entry = nativeLoginTokens.get(nlt);
        if (entry && entry.expiresAt > Date.now()) {
          entry.userId = newUser.id;
        }
        return reply.type("text/html").send(NLT_SUCCESS_HTML);
      }

      req.regenerateSession();
      req.session.userId = newUser.id;
      return reply.redirect(process.env.FRONTEND_URL);
    }

    // Existing user — native login: store userId against token, show success page
    if (nlt) {
      const entry = nativeLoginTokens.get(nlt);
      if (entry && entry.expiresAt > Date.now()) {
        entry.userId = account.userId;
      }
      return reply.type("text/html").send(NLT_SUCCESS_HTML);
    }

    req.regenerateSession();
    req.session.userId = account.userId;
    return reply.redirect(process.env.FRONTEND_URL);
  }

  async function handleGoogleLink({ sub }, req, reply) {
    // Support both old grant.dynamic.link flow and new linkUserId token flow (from desktop)
    const userId = req.auth.user?.id ?? req.session.linkUserId;
    if (!userId) {
      return reply.redirect(`${process.env.FRONTEND_URL}/login?error=not_authenticated`);
    }
    delete req.session.linkUserId;

    const existing = await prisma.account.findUnique({
      where: { provider_providerAccountId: { provider: "google", providerAccountId: sub } },
    });
    if (existing && existing.userId !== userId) {
      return reply.redirect(`${process.env.FRONTEND_URL}/profile?error=account_linked`);
    }
    if (!existing) {
      await prisma.account.create({
        data: { provider: "google", providerAccountId: sub, userId },
      });
    }

    req.regenerateSession();
    return reply.redirect(`${process.env.FRONTEND_URL}/profile?linked=google`);
  }

};
