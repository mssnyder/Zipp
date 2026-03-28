import { PAGINATION } from "../constants.js";

function ensureAuth(req, reply) {
  if (!req.auth?.user) { reply.code(401).send({ error: "Unauthorized" }); return false; }
  return true;
}

const USER_SELECT = { id: true, username: true, displayName: true, avatarUrl: true };

function formatConversation(conv, myUserId) {
  const activeParticipants = (conv.participants || []).filter((p) => !p.leftAt);
  const lastMsg = conv.messages?.[0] ?? null;

  if (conv.isGroup) {
    return {
      id: conv.id,
      isGroup: true,
      name: conv.name,
      updatedAt: conv.updatedAt,
      participants: activeParticipants.map((p) => ({
        id: p.user.id,
        username: p.user.username,
        displayName: p.user.displayName,
        avatarUrl: p.user.avatarUrl,
        role: p.role,
      })),
      lastMessage: lastMsg ? formatLastMessage(lastMsg, myUserId) : null,
    };
  }

  // DM: return single "other" participant for backward compat
  const other = activeParticipants.find((p) => p.userId !== myUserId);
  return {
    id: conv.id,
    isGroup: false,
    updatedAt: conv.updatedAt,
    participant: other
      ? { id: other.user.id, username: other.user.username, displayName: other.user.displayName, avatarUrl: other.user.avatarUrl }
      : null,
    lastMessage: lastMsg ? formatLastMessage(lastMsg, myUserId) : null,
  };
}

function formatLastMessage(msg, myUserId) {
  const base = {
    id: msg.id,
    type: msg.type,
    createdAt: msg.createdAt,
    senderId: msg.senderId,
  };

  if (msg.epochId) {
    // Group message — include single ciphertext + epoch key for requesting user
    const myKey = msg.epoch?.keys?.find((k) => k.userId === myUserId) ?? null;
    return {
      ...base,
      ciphertext: msg.ciphertext,
      nonce: msg.nonce,
      epochId: msg.epochId,
      epochKey: myKey ? { encryptedKey: myKey.encryptedKey, keyNonce: myKey.keyNonce, wrappedById: myKey.wrappedById } : null,
    };
  }

  // DM message
  return {
    ...base,
    recipientCiphertext: msg.recipientCiphertext,
    senderCiphertext: msg.senderCiphertext,
    nonce: msg.nonce,
  };
}

export default async (app, prisma) => {
  // GET /api/conversations — list my conversations
  app.get("/api/conversations", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const conversations = await prisma.conversation.findMany({
      where: { participants: { some: { userId: req.auth.user.id, leftAt: null } } },
      include: {
        participants: {
          where: { leftAt: null },
          include: { user: { select: USER_SELECT } },
        },
        messages: {
          where: { deletedAt: null },
          orderBy: { createdAt: "desc" },
          take: 1,
          include: {
            epoch: { include: { keys: { where: { userId: req.auth.user.id }, select: { userId: true, encryptedKey: true, keyNonce: true, wrappedById: true } } } },
          },
        },
      },
      orderBy: { updatedAt: "desc" },
      take: PAGINATION.CONVERSATIONS_PER_PAGE,
    });

    return { conversations: conversations.map((c) => formatConversation(c, req.auth.user.id)) };
  });

  // POST /api/conversations — create DM or group
  app.post("/api/conversations", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const { userId, participantIds, isGroup, name } = req.body || {};

    // Group creation
    if (isGroup) {
      if (!Array.isArray(participantIds) || participantIds.length < 1) {
        return reply.code(400).send({ error: "Group requires at least one other participant" });
      }

      const allIds = [req.auth.user.id, ...participantIds.filter((id) => id !== req.auth.user.id)];

      // Verify all users exist
      const users = await prisma.user.findMany({
        where: { id: { in: allIds } },
        select: { id: true },
      });
      if (users.length !== allIds.length) {
        return reply.code(400).send({ error: "One or more users not found" });
      }

      const conversation = await prisma.conversation.create({
        data: {
          isGroup: true,
          name: name || null,
          participants: {
            create: allIds.map((uid) => ({
              userId: uid,
              role: uid === req.auth.user.id ? "ADMIN" : "MEMBER",
            })),
          },
        },
        include: {
          participants: {
            where: { leftAt: null },
            include: { user: { select: USER_SELECT } },
          },
          messages: { orderBy: { createdAt: "desc" }, take: 1 },
        },
      });

      // Notify other participants
      const otherIds = allIds.filter((id) => id !== req.auth.user.id);
      app.broadcast(otherIds, "conversation:new", {
        conversation: formatConversation(conversation, req.auth.user.id),
      });

      return reply.code(201).send({ conversation: formatConversation(conversation, req.auth.user.id) });
    }

    // DM creation (existing flow)
    if (!userId || typeof userId !== "string") {
      return reply.code(400).send({ error: "Missing userId" });
    }
    if (userId === req.auth.user.id) {
      return reply.code(400).send({ error: "Cannot start conversation with yourself" });
    }

    const target = await prisma.user.findUnique({ where: { id: userId } });
    if (!target) return reply.code(404).send({ error: "User not found" });

    // Find existing DM (not group) between these two users
    const existing = await prisma.conversation.findFirst({
      where: {
        isGroup: false,
        AND: [
          { participants: { some: { userId: req.auth.user.id, leftAt: null } } },
          { participants: { some: { userId, leftAt: null } } },
        ],
      },
      include: {
        participants: {
          where: { leftAt: null },
          include: { user: { select: USER_SELECT } },
        },
        messages: { orderBy: { createdAt: "desc" }, take: 1 },
      },
    });

    if (existing) {
      return { conversation: formatConversation(existing, req.auth.user.id) };
    }

    const conversation = await prisma.conversation.create({
      data: {
        isGroup: false,
        participants: {
          create: [{ userId: req.auth.user.id }, { userId }],
        },
      },
      include: {
        participants: {
          where: { leftAt: null },
          include: { user: { select: USER_SELECT } },
        },
        messages: { orderBy: { createdAt: "desc" }, take: 1 },
      },
    });

    return reply.code(201).send({ conversation: formatConversation(conversation, req.auth.user.id) });
  });

  // GET /api/conversations/:id — full conversation details
  app.get("/api/conversations/:id", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const membership = await prisma.conversationParticipant.findUnique({
      where: {
        conversationId_userId: {
          conversationId: req.params.id,
          userId: req.auth.user.id,
        },
      },
    });
    if (!membership || membership.leftAt) return reply.code(403).send({ error: "Forbidden" });

    const conversation = await prisma.conversation.findUnique({
      where: { id: req.params.id },
      include: {
        participants: {
          where: { leftAt: null },
          include: { user: { select: USER_SELECT } },
        },
      },
    });

    if (!conversation) return reply.code(404).send({ error: "Conversation not found" });

    return {
      ...formatConversation(conversation, req.auth.user.id),
      myRole: membership.role,
    };
  });

  // PATCH /api/conversations/:id — rename group (admin-only)
  app.patch("/api/conversations/:id", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const membership = await prisma.conversationParticipant.findUnique({
      where: {
        conversationId_userId: {
          conversationId: req.params.id,
          userId: req.auth.user.id,
        },
      },
    });
    if (!membership || membership.leftAt || membership.role !== "ADMIN") {
      return reply.code(403).send({ error: "Only admins can rename groups" });
    }

    const conv = await prisma.conversation.findUnique({
      where: { id: req.params.id },
      select: { isGroup: true },
    });
    if (!conv?.isGroup) return reply.code(400).send({ error: "Can only rename group conversations" });

    const { name } = req.body || {};
    if (!name || typeof name !== "string") {
      return reply.code(400).send({ error: "Missing name" });
    }

    await prisma.conversation.update({
      where: { id: req.params.id },
      data: { name },
    });

    // Broadcast to all active participants
    const participants = await prisma.conversationParticipant.findMany({
      where: { conversationId: req.params.id, leftAt: null },
      select: { userId: true },
    });
    app.broadcast(
      participants.map((p) => p.userId),
      "conversation:renamed",
      { conversationId: req.params.id, name },
    );

    return { ok: true, name };
  });
};
