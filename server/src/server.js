import "dotenv/config";

import Fastify from "fastify";
import fastifyCookie from "@fastify/cookie";
import cors from "@fastify/cors";
import fastifyMultipart from "@fastify/multipart";
import fastifyRateLimit from "@fastify/rate-limit";
import fastifyStatic from "@fastify/static";
import fastifyWebsocket from "@fastify/websocket";
import grant from "fastify-grant";
import pino from "pino";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

import databasePlugin from "./plugins/database.js";
import sessionPlugin, { grantSessionStore } from "./plugins/session.js";
import websocketPlugin from "./plugins/websocket.js";
import { RATE_LIMITS } from "./constants.js";

import authRoutes from "./routes/auth.js";
import meRoutes from "./routes/me.js";
import usersRoutes from "./routes/users.js";
import conversationsRoutes from "./routes/conversations.js";
import messagesRoutes from "./routes/messages.js";
import reactionsRoutes from "./routes/reactions.js";
import keysRoutes from "./routes/keys.js";
import gifsRoutes from "./routes/gifs.js";
import tenorRoutes from "./routes/tenor.js";
import uploadRoutes from "./routes/upload.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Logger
const transport = pino.transport({
  targets:
    process.env.NODE_ENV === "production"
      ? [
          {
            target: "pino/file",
            options: {
              destination: join(
                process.env.DATA_DIR ?? process.cwd(),
                "logs",
                "app.log",
              ),
              mkdir: true,
            },
          },
        ]
      : [{ target: "pino-pretty", options: { singleLine: true } }],
});

const logger = pino(
  {
    level: process.env.LOG_LEVEL || "info",
    base: { app: "zipp" },
    messageKey: "msg",
    timestamp: pino.stdTimeFunctions.isoTime,
    redact: {
      paths: ["req.headers.cookie", "req.body.password"],
      censor: "[redacted]",
    },
    serializers: {
      req: pino.stdSerializers.req,
      res: pino.stdSerializers.res,
      err: pino.stdSerializers.err,
    },
  },
  transport,
);

const app = Fastify({
  loggerInstance: logger,
  disableRequestLogging: true,
  trustProxy: 1,
  genReqId: (req) =>
    req.headers["x-request-id"]?.toString() ||
    `req-${Math.random().toString(36).slice(2, 10)}`,
});

app.addHook("onRequest", (req, _reply, done) => {
  req.log.info({ req }, "incoming request");
  done();
});

app.addHook("onResponse", (req, reply, done) => {
  req.log.info(
    {
      req: { method: req.method, url: req.url },
      res: { statusCode: reply.statusCode },
    },
    "request completed",
  );
  done();
});

// CORS — Flutter apps connect from same domain or localhost in dev
await app.register(cors, {
  origin:
    process.env.FRONTEND_URL ||
    (process.env.NODE_ENV === "production" ? false : true),
  credentials: true,
  methods: ["GET", "POST", "PATCH", "PUT", "DELETE"],
});

await app.register(fastifyCookie);
await app.register(databasePlugin);
await app.register(sessionPlugin);

await app.register(fastifyRateLimit, {
  global: true,
  max: RATE_LIMITS.GLOBAL_MAX,
  timeWindow: RATE_LIMITS.GLOBAL_WINDOW,
  keyGenerator: (req) => req.ip,
  allowList: (req) => ["127.0.0.1", "::1"].includes(req.ip),
});

await app.register(fastifyMultipart, {
  limits: { fileSize: 2 * 1024 * 1024 * 1024 }, // 2 GB max (videos); per-type limits enforced in routes
});

// Serve uploaded files (avatars, attachments, thumbs)
await app.register(fastifyStatic, {
  root: join(process.env.DATA_DIR ?? process.cwd(), "uploads"),
  prefix: "/uploads/",
  decorateReply: true,
});

// WebSocket support
await app.register(fastifyWebsocket);
await app.register(websocketPlugin);

// Google OAuth
await app.register(
  grant({
    defaults: {
      origin: process.env.SERVER_URL,
      transport: "session",
      state: true,
    },
    session: { store: grantSessionStore() },
    google: {
      key: process.env.GOOGLE_CLIENT_ID,
      secret: process.env.GOOGLE_CLIENT_SECRET,
      scope: ["openid", "email", "profile"],
      pkce: true,
      callback: "/api/oauth/google",
    },
  }),
);

// Register routes — auth first so preHandler hook runs for all subsequent routes
const prisma = app.prisma;
authRoutes(app, prisma);
await meRoutes(app, prisma);
await usersRoutes(app, prisma);
await conversationsRoutes(app, prisma);
await messagesRoutes(app, prisma);
await reactionsRoutes(app, prisma);
await keysRoutes(app, prisma);
await gifsRoutes(app);
await tenorRoutes(app);
await uploadRoutes(app, prisma);

// Health check
app.get("/health", async () => ({
  status: "ok",
  ts: new Date().toISOString(),
}));

app.setNotFoundHandler((req, reply) => {
  return reply.code(404).send({ error: "Not found" });
});

app.setErrorHandler((err, req, reply) => {
  req.log.error({ err }, "unhandled error");
  reply
    .code(err.statusCode || 500)
    .send({ error: err.message || "Internal server error" });
});

const port = Number(process.env.PORT) || 4200;
app.listen({ port, host: "127.0.0.1" }, (err) => {
  if (err) {
    app.log.error(err);
    process.exit(1);
  }
  app.log.info(`Zipp server listening on port ${port}`);
});

export default app;
