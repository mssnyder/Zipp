import * as yup from "yup";
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
    emailVerified: user.emailVerified,
    isAdmin: user.isAdmin,
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

export default async (app, prisma) => {
  // GET /api/me
  app.get("/api/me", async (req, reply) => {
    if (!ensureAuth(req, reply)) return;
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
      if (!ensureAuth(req, reply)) return;

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
    if (!ensureAuth(req, reply)) return;

    const data = await req.file();
    if (!data) return reply.code(400).send({ error: "No file uploaded" });

    const allowed = ["image/jpeg", "image/png", "image/webp", "image/gif"];
    if (!allowed.includes(data.mimetype)) {
      return reply.code(400).send({ error: "Invalid file type. Allowed: jpg, png, webp, gif" });
    }

    const { randomBytes } = await import("node:crypto");
    const { writeFile, mkdir } = await import("node:fs/promises");
    const { join } = await import("node:path");

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
};
