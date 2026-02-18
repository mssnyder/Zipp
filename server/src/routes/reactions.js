import { RATE_LIMITS } from "../constants.js";

function ensureAuth(req, reply) {
  if (!req.auth?.user) { reply.code(401).send({ error: "Unauthorized" }); return false; }
  return true;
}

export default async (app, prisma) => {
  // POST /api/messages/:id/reactions — toggle (add or remove)
  app.route({
    method: "POST",
    url: "/api/messages/:id/reactions",
    config: { rateLimit: { max: RATE_LIMITS.REACTION_MAX, timeWindow: RATE_LIMITS.REACTION_WINDOW } },
    handler: async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      const { emoji } = req.body || {};
      if (!emoji || typeof emoji !== "string" || emoji.length > 10) {
        return reply.code(400).send({ error: "Invalid emoji" });
      }

      const message = await prisma.message.findUnique({
        where: { id: req.params.id },
        include: { conversation: { include: { participants: { select: { userId: true } } } } },
      });
      if (!message) return reply.code(404).send({ error: "Message not found" });

      const isMember = message.conversation.participants.some((p) => p.userId === req.auth.user.id);
      if (!isMember) return reply.code(403).send({ error: "Forbidden" });

      // Toggle: remove if exists, add if not
      const existing = await prisma.reaction.findUnique({
        where: { messageId_userId_emoji: { messageId: req.params.id, userId: req.auth.user.id, emoji } },
      });

      if (existing) {
        await prisma.reaction.delete({ where: { id: existing.id } });
      } else {
        await prisma.reaction.create({
          data: { messageId: req.params.id, userId: req.auth.user.id, emoji },
        });
      }

      // Fetch updated reactions
      const reactions = await prisma.reaction.findMany({
        where: { messageId: req.params.id },
        select: { id: true, userId: true, emoji: true, createdAt: true },
      });

      // Broadcast to all participants
      const participantIds = message.conversation.participants.map((p) => p.userId);
      app.broadcast(participantIds, "message:reaction", { messageId: req.params.id, reactions });

      return { reactions };
    },
  });

  // GET /api/messages/:id/reactions
  app.get("/api/messages/:id/reactions", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const reactions = await prisma.reaction.findMany({
      where: { messageId: req.params.id },
      select: { id: true, userId: true, emoji: true, createdAt: true },
    });
    return { reactions };
  });
};
