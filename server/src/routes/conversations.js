import { PAGINATION } from "../constants.js";

function ensureAuth(req, reply) {
  if (!req.auth?.user) { reply.code(401).send({ error: "Unauthorized" }); return false; }
  return true;
}

function formatConversation(conv, myUserId) {
  const other = conv.participants.find((p) => p.userId !== myUserId);
  const lastMsg = conv.messages[0];
  return {
    id: conv.id,
    updatedAt: conv.updatedAt,
    participant: other
      ? { id: other.user.id, username: other.user.username, displayName: other.user.displayName, avatarUrl: other.user.avatarUrl }
      : null,
    lastMessage: lastMsg
      ? { id: lastMsg.id, type: lastMsg.type, createdAt: lastMsg.createdAt, senderId: lastMsg.senderId }
      : null,
  };
}

export default async (app, prisma) => {
  // GET /api/conversations — list my conversations
  app.get("/api/conversations", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const conversations = await prisma.conversation.findMany({
      where: { participants: { some: { userId: req.auth.user.id } } },
      include: {
        participants: { include: { user: { select: { id: true, username: true, displayName: true, avatarUrl: true } } } },
        messages: { orderBy: { createdAt: "desc" }, take: 1 },
      },
      orderBy: { updatedAt: "desc" },
      take: PAGINATION.CONVERSATIONS_PER_PAGE,
    });

    return { conversations: conversations.map((c) => formatConversation(c, req.auth.user.id)) };
  });

  // POST /api/conversations — create or find existing DM
  app.post("/api/conversations", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const { userId } = req.body || {};
    if (!userId || typeof userId !== "string") {
      return reply.code(400).send({ error: "Missing userId" });
    }
    if (userId === req.auth.user.id) {
      return reply.code(400).send({ error: "Cannot start conversation with yourself" });
    }

    const target = await prisma.user.findUnique({ where: { id: userId } });
    if (!target) return reply.code(404).send({ error: "User not found" });

    // Find existing DM between these two users
    const existing = await prisma.conversation.findFirst({
      where: {
        AND: [
          { participants: { some: { userId: req.auth.user.id } } },
          { participants: { some: { userId } } },
        ],
      },
      include: {
        participants: { include: { user: { select: { id: true, username: true, displayName: true, avatarUrl: true } } } },
        messages: { orderBy: { createdAt: "desc" }, take: 1 },
      },
    });

    if (existing) {
      return { conversation: formatConversation(existing, req.auth.user.id) };
    }

    const conversation = await prisma.conversation.create({
      data: {
        participants: {
          create: [{ userId: req.auth.user.id }, { userId }],
        },
      },
      include: {
        participants: { include: { user: { select: { id: true, username: true, displayName: true, avatarUrl: true } } } },
        messages: { orderBy: { createdAt: "desc" }, take: 1 },
      },
    });

    return reply.code(201).send({ conversation: formatConversation(conversation, req.auth.user.id) });
  });
};
