import { RATE_LIMITS, PAGINATION } from "../constants.js";

function ensureAuth(req, reply) {
  if (!req.auth?.user) { reply.code(401).send({ error: "Unauthorized" }); return false; }
  return true;
}

function formatMessage(msg) {
  return {
    id: msg.id,
    conversationId: msg.conversationId,
    senderId: msg.senderId,
    ciphertext: msg.ciphertext,
    nonce: msg.nonce,
    type: msg.type,
    replyToId: msg.replyToId,
    replyTo: msg.replyTo
      ? { id: msg.replyTo.id, senderId: msg.replyTo.senderId, ciphertext: msg.replyTo.ciphertext, nonce: msg.replyTo.nonce, type: msg.replyTo.type }
      : null,
    reactions: msg.reactions || [],
    readAt: msg.readAt,
    createdAt: msg.createdAt,
  };
}

export default async (app, prisma) => {
  // GET /api/conversations/:id/messages
  app.get("/api/conversations/:id/messages", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    // Verify membership
    const membership = await prisma.conversationParticipant.findUnique({
      where: { conversationId_userId: { conversationId: req.params.id, userId: req.auth.user.id } },
    });
    if (!membership) return reply.code(403).send({ error: "Forbidden" });

    const { before, limit } = req.query;
    const take = Math.min(Number(limit) || PAGINATION.MESSAGES_PER_PAGE, 100);

    const messages = await prisma.message.findMany({
      where: {
        conversationId: req.params.id,
        ...(before ? { createdAt: { lt: new Date(before) } } : {}),
      },
      include: {
        replyTo: { select: { id: true, senderId: true, ciphertext: true, nonce: true, type: true } },
        reactions: { select: { id: true, userId: true, emoji: true, createdAt: true } },
      },
      orderBy: { createdAt: "desc" },
      take,
    });

    return { messages: messages.reverse().map(formatMessage) };
  });

  // POST /api/conversations/:id/messages
  app.route({
    method: "POST",
    url: "/api/conversations/:id/messages",
    config: { rateLimit: { max: RATE_LIMITS.MESSAGE_MAX, timeWindow: RATE_LIMITS.MESSAGE_WINDOW } },
    handler: async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      const membership = await prisma.conversationParticipant.findUnique({
        where: { conversationId_userId: { conversationId: req.params.id, userId: req.auth.user.id } },
      });
      if (!membership) return reply.code(403).send({ error: "Forbidden" });

      const { ciphertext, nonce, type = "TEXT", replyToId } = req.body || {};
      if (!ciphertext || !nonce) {
        return reply.code(400).send({ error: "Missing ciphertext or nonce" });
      }
      if (!["TEXT", "GIF", "IMAGE"].includes(type)) {
        return reply.code(400).send({ error: "Invalid message type" });
      }

      const message = await prisma.message.create({
        data: {
          conversationId: req.params.id,
          senderId: req.auth.user.id,
          ciphertext,
          nonce,
          type,
          replyToId: replyToId || null,
        },
        include: {
          replyTo: { select: { id: true, senderId: true, ciphertext: true, nonce: true, type: true } },
          reactions: true,
        },
      });

      // Update conversation updatedAt
      await prisma.conversation.update({
        where: { id: req.params.id },
        data: { updatedAt: new Date() },
      });

      // Broadcast to all participants via WebSocket
      const participants = await prisma.conversationParticipant.findMany({
        where: { conversationId: req.params.id },
        select: { userId: true },
      });
      const userIds = participants.map((p) => p.userId).filter((id) => id !== req.auth.user.id);
      app.broadcast(userIds, "message:new", {
        conversationId: req.params.id,
        message: formatMessage(message),
      });

      return reply.code(201).send({ message: formatMessage(message) });
    },
  });

  // PATCH /api/conversations/:id/messages/:msgId/read
  app.patch("/api/conversations/:id/messages/:msgId/read", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const membership = await prisma.conversationParticipant.findUnique({
      where: { conversationId_userId: { conversationId: req.params.id, userId: req.auth.user.id } },
    });
    if (!membership) return reply.code(403).send({ error: "Forbidden" });

    const msg = await prisma.message.findFirst({
      where: { id: req.params.msgId, conversationId: req.params.id },
    });
    if (!msg || msg.senderId === req.auth.user.id) return { ok: true };

    const updated = await prisma.message.update({
      where: { id: req.params.msgId },
      data: { readAt: new Date() },
    });

    app.broadcast([msg.senderId], "message:read", {
      conversationId: req.params.id,
      messageId: msg.id,
      readAt: updated.readAt,
    });

    return { ok: true };
  });
};
