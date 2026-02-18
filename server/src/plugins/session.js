// Ported from apitaph — AES-256-GCM encrypted cookie sessions backed by PostgreSQL
import fp from "fastify-plugin";
import {
  randomBytes,
  createCipheriv,
  createDecipheriv,
  createHash,
} from "node:crypto";
import { UAParser } from "ua-parser-js";
import ms from "ms";
import { SESSION } from "../constants.js";

const getSessionLength = () => {
  try {
    const len = ms(process.env.SESSION_LENGTH || "30d");
    if (!len || len <= 0) throw new Error("Invalid session length");
    return len;
  } catch (err) {
    throw new Error(`Invalid SESSION_LENGTH: ${err.message}`);
  }
};

const SESSION_LENGTH_MS = getSessionLength();

if (!process.env.SESSION_SECRET && process.env.NODE_ENV === "production") {
  throw new Error("SESSION_SECRET is required in production");
}

const COOKIE_SECRET = createHash("sha256")
  .update(process.env.SESSION_SECRET || "dev-secret-change-in-production")
  .digest();

const cookieOptions = {
  path: "/",
  httpOnly: true,
  sameSite: "strict",
  secure: process.env.NODE_ENV === "production",
  maxAge: SESSION_LENGTH_MS,
};

export const encryptSid = (sid) => {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", COOKIE_SECRET, iv);
  const encrypted = Buffer.concat([cipher.update(sid, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, encrypted]).toString("base64url");
};

export const decryptSid = (token) => {
  const buf = Buffer.from(token, "base64url");
  const iv = buf.subarray(0, 12);
  const tag = buf.subarray(12, 28);
  const data = buf.subarray(28);
  const decipher = createDecipheriv("aes-256-gcm", COOKIE_SECRET, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString("utf8");
};

const persistSession = async (prisma, data, { req, sid }) => {
  if (!sid) return;

  const ua = req.headers["user-agent"] || "";
  const { device: d, os } = new UAParser(ua).getResult();
  const device =
    [
      ...Object.entries(d).map(([k, v]) => (v ? `${k}: ${v}` : null)),
      ...Object.entries(os).map(([k, v]) => (v ? `os.${k}: ${v}` : null)),
    ]
      .filter(Boolean)
      .join(" ") || "unknown";

  const expiresAt = new Date(Date.now() + SESSION_LENGTH_MS);
  const payload = {
    data,
    userId: data.userId || null,
    ip: req.ip,
    userAgent: ua,
    device,
    expiresAt,
  };

  await prisma.session.upsert({
    where: { id: sid },
    update: payload,
    create: { id: sid, ...payload },
  });
};

const deleteSession = async (prisma, sid) => {
  if (!sid) return;
  await prisma.session.delete({ where: { id: sid } }).catch(() => {});
};

const setSessionCookie = (reply, sid, extra = {}) => {
  reply.setCookie(SESSION.COOKIE_NAME, encryptSid(sid), { ...cookieOptions, ...extra });
};

const clearSessionCookie = (reply) => {
  reply.clearCookie(SESSION.COOKIE_NAME, { path: "/" });
};

const sessionPlugin = fp((app) => {
  const { prisma } = app;

  app.addHook("onRequest", async (req) => {
    const token = req.cookies[SESSION.COOKIE_NAME];
    req.session = {};

    if (token) {
      try {
        const sid = decryptSid(token);
        const record = await prisma.session.findUnique({ where: { id: sid } });
        if (record && record.expiresAt.getTime() > Date.now()) {
          req.session = record.data;
          req.sessionId = sid;
        } else {
          req._sidToDestroy = sid;
          req._forceClearCookie = true;
        }
      } catch {
        req._forceClearCookie = true;
      }
    }

    req.regenerateSession = () => {
      req._sidToDestroy = req.sessionId;
      req.sessionId = randomBytes(16).toString("hex");
    };

    req.destroySession = async () => {
      if (req.sessionId) req._sidToDestroy = req.sessionId;
      req.sessionId = null;
      req.session = {};
      req._forceClearCookie = true;
    };
  });

  const applyCookies = (req, reply) => {
    if (reply.raw.headersSent || reply.sent) return;

    if (req.sessionId || Object.keys(req.session).length > 0) {
      if (!req.sessionId) req.sessionId = randomBytes(16).toString("hex");

      if (req.method === "GET" && req.url.startsWith("/connect/")) {
        setSessionCookie(reply, req.sessionId, { sameSite: "lax" });
      } else {
        setSessionCookie(reply, req.sessionId);
      }
      req._forceClearCookie = false;
    } else if (req._forceClearCookie) {
      clearSessionCookie(reply);
    }
  };

  app.addHook("onSend", async (req, reply, payload) => {
    applyCookies(req, reply);
    await persistSession(prisma, req.session, { req, sid: req.sessionId });
    if (req._sidToDestroy) await deleteSession(prisma, req._sidToDestroy);
    return payload;
  });

  app.addHook("onError", async (req, reply) => {
    applyCookies(req, reply);
    if (req._sidToDestroy) await deleteSession(prisma, req._sidToDestroy);
  });
});

export const grantSessionStore = () => ({
  async get(req) { return req.session; },
  async set(req, sess) {
    if (sess && typeof sess === "object") Object.assign(req.session, sess);
  },
  async remove(req) { await req.destroySession(); },
});

export default sessionPlugin;
