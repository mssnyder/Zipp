import { RATE_LIMITS, PAGINATION } from "../constants.js";

function ensureAuth(req, reply) {
  if (!req.auth?.user) {
    reply.code(401).send({ error: "Unauthorized" });
    return false;
  }
  return true;
}

function formatMessage(msg) {
  return {
    id: msg.id,
    conversationId: msg.conversationId,
    senderId: msg.senderId,
    recipientCiphertext: msg.recipientCiphertext,
    senderCiphertext: msg.senderCiphertext,
    nonce: msg.nonce,
    type: msg.type,
    replyToId: msg.replyToId,
    replyTo: msg.replyTo
      ? {
          id: msg.replyTo.id,
          senderId: msg.replyTo.senderId,
          recipientCiphertext: msg.replyTo.recipientCiphertext,
          senderCiphertext: msg.replyTo.senderCiphertext,
          nonce: msg.replyTo.nonce,
          type: msg.replyTo.type,
        }
      : null,
    reactions: (msg.reactions || []).map((r) => ({
      id: r.id,
      userId: r.userId,
      emoji: r.emoji,
      createdAt: r.createdAt,
      displayName: r.user?.displayName ?? null,
    })),
    readAt: msg.readAt,
    editedAt: msg.editedAt ?? null,
    createdAt: msg.createdAt,
  };
}

export default async (app, prisma) => {
  // GET /api/conversations/:id/messages
  app.get("/api/conversations/:id/messages", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    // Verify membership
    const membership = await prisma.conversationParticipant.findUnique({
      where: {
        conversationId_userId: {
          conversationId: req.params.id,
          userId: req.auth.user.id,
        },
      },
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
        replyTo: {
          select: {
            id: true,
            senderId: true,
            recipientCiphertext: true,
            senderCiphertext: true,
            nonce: true,
            type: true,
          },
        },
        reactions: {
          select: { id: true, userId: true, emoji: true, createdAt: true, user: { select: { displayName: true } } },
        },
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
    config: {
      rateLimit: {
        max: RATE_LIMITS.MESSAGE_MAX,
        timeWindow: RATE_LIMITS.MESSAGE_WINDOW,
      },
    },
    handler: async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      const membership = await prisma.conversationParticipant.findUnique({
        where: {
          conversationId_userId: {
            conversationId: req.params.id,
            userId: req.auth.user.id,
          },
        },
      });
      if (!membership) return reply.code(403).send({ error: "Forbidden" });

      const {
        nonce,
        type = "TEXT",
        replyToId,
        recipientCiphertext,
        senderCiphertext,
      } = req.body || {};
      if (!nonce || !recipientCiphertext || !senderCiphertext) {
        return reply.code(400).send({
          error:
            "Missing required fields: nonce, recipientCiphertext, or senderCiphertext",
        });
      }
      if (!["TEXT", "GIF", "IMAGE", "VIDEO", "FILE"].includes(type)) {
        return reply.code(400).send({ error: "Invalid message type" });
      }

      const message = await prisma.message.create({
        data: {
          conversationId: req.params.id,
          senderId: req.auth.user.id,
          recipientCiphertext,
          senderCiphertext,
          nonce,
          type,
          replyToId: replyToId || null,
        },
        include: {
          replyTo: {
            select: {
              id: true,
              senderId: true,
              recipientCiphertext: true,
              senderCiphertext: true,
              nonce: true,
              type: true,
            },
          },
          reactions: {
            select: { id: true, userId: true, emoji: true, createdAt: true, user: { select: { displayName: true } } },
          },
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
      const userIds = participants.map((p) => p.userId);
      app.broadcast(userIds, "message:new", {
        conversationId: req.params.id,
        message: formatMessage(message),
      });

      return reply.code(201).send({ message: formatMessage(message) });
    },
  });

  // PATCH /api/conversations/:id/messages/:msgId/read
  app.patch(
    "/api/conversations/:id/messages/:msgId/read",
    async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      const membership = await prisma.conversationParticipant.findUnique({
        where: {
          conversationId_userId: {
            conversationId: req.params.id,
            userId: req.auth.user.id,
          },
        },
      });
      if (!membership) return reply.code(403).send({ error: "Forbidden" });

      const msg = await prisma.message.findFirst({
        where: { id: req.params.msgId, conversationId: req.params.id },
      });
      if (!msg || msg.senderId === req.auth.user.id) return { ok: true };

      const now = new Date();

      // Mark all unread messages from this sender up to (and including) the specified one
      await prisma.message.updateMany({
        where: {
          conversationId: req.params.id,
          senderId: msg.senderId,
          readAt: null,
          createdAt: { lte: msg.createdAt },
        },
        data: { readAt: now },
      });

      app.broadcast([msg.senderId], "message:read", {
        conversationId: req.params.id,
        messageId: msg.id,
        readAt: now,
      });

      return { ok: true };
    },
  );

  // PATCH /api/conversations/:id/messages/:msgId — edit message
  app.patch(
    "/api/conversations/:id/messages/:msgId",
    async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      const msg = await prisma.message.findFirst({
        where: { id: req.params.msgId, conversationId: req.params.id },
      });
      if (!msg) return reply.code(404).send({ error: "Message not found" });
      if (msg.senderId !== req.auth.user.id) {
        return reply.code(403).send({ error: "Can only edit your own messages" });
      }

      const { recipientCiphertext, senderCiphertext, nonce } = req.body || {};
      if (!recipientCiphertext || !senderCiphertext || !nonce) {
        return reply.code(400).send({
          error: "Missing required fields: recipientCiphertext, senderCiphertext, nonce",
        });
      }

      const updated = await prisma.message.update({
        where: { id: req.params.msgId },
        data: {
          recipientCiphertext,
          senderCiphertext,
          nonce,
          editedAt: new Date(),
        },
        include: {
          replyTo: {
            select: {
              id: true, senderId: true,
              recipientCiphertext: true, senderCiphertext: true,
              nonce: true, type: true,
            },
          },
          reactions: {
            select: { id: true, userId: true, emoji: true, createdAt: true, user: { select: { displayName: true } } },
          },
        },
      });

      const participants = await prisma.conversationParticipant.findMany({
        where: { conversationId: req.params.id },
        select: { userId: true },
      });
      app.broadcast(
        participants.map((p) => p.userId),
        "message:edit",
        { conversationId: req.params.id, message: formatMessage(updated) },
      );

      return { message: formatMessage(updated) };
    },
  );

  // DELETE /api/conversations/:id/messages/:msgId — delete for both
  app.delete(
    "/api/conversations/:id/messages/:msgId",
    async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      const msg = await prisma.message.findFirst({
        where: { id: req.params.msgId, conversationId: req.params.id },
      });
      if (!msg) return reply.code(404).send({ error: "Message not found" });
      if (msg.senderId !== req.auth.user.id) {
        return reply.code(403).send({ error: "Can only delete your own messages" });
      }

      const participants = await prisma.conversationParticipant.findMany({
        where: { conversationId: req.params.id },
        select: { userId: true },
      });

      await prisma.message.delete({ where: { id: req.params.msgId } });

      app.broadcast(
        participants.map((p) => p.userId),
        "message:delete",
        { conversationId: req.params.id, messageId: req.params.msgId },
      );

      return { ok: true };
    },
  );
};
