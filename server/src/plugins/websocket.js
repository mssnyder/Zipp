import fp from "fastify-plugin";
import { decryptSid } from "./session.js";

// Map of userId -> Set of WebSocket connections
const clients = new Map();

export const broadcast = (userIds, event, payload) => {
  const msg = JSON.stringify({ event, payload });
  for (const userId of userIds) {
    const sockets = clients.get(userId);
    if (!sockets) continue;
    for (const ws of sockets) {
      if (ws.readyState === 1) ws.send(msg);
    }
  }
};

export const getOnlineUsers = () => [...clients.keys()];

export default fp(async (app) => {
  const { prisma } = app;

  app.get("/ws", { websocket: true }, async (socket, req) => {
    // Authenticate via session cookie or ?sid= query param
    let userId = null;
    try {
      const token =
        req.cookies?.sid ||
        new URL(req.url, "http://localhost").searchParams.get("sid");

      if (token) {
        const sid = decryptSid(token);
        const record = await prisma.session.findUnique({ where: { id: sid } });
        if (record && record.expiresAt.getTime() > Date.now() && record.userId) {
          userId = record.userId;
        }
      }
    } catch {
      // fall through — userId stays null
    }

    if (!userId) {
      socket.send(JSON.stringify({ event: "error", payload: { message: "Unauthorized" } }));
      socket.close(1008, "Unauthorized");
      return;
    }

    // Register connection
    if (!clients.has(userId)) clients.set(userId, new Set());
    clients.get(userId).add(socket);

    // Notify others this user came online
    broadcast([...clients.keys()].filter((id) => id !== userId), "user:online", { userId });

    socket.on("message", async (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); } catch { return; }

      if (msg.event === "message:typing") {
        // { conversationId, isTyping }
        const { conversationId, isTyping } = msg.payload || {};
        if (!conversationId) return;

        const participants = await prisma.conversationParticipant.findMany({
          where: { conversationId },
          select: { userId: true },
        });
        const others = participants.map((p) => p.userId).filter((id) => id !== userId);
        broadcast(others, "message:typing", { conversationId, userId, isTyping });
      }
    });

    socket.on("close", () => {
      const sockets = clients.get(userId);
      if (sockets) {
        sockets.delete(socket);
        if (sockets.size === 0) {
          clients.delete(userId);
          broadcast([...clients.keys()], "user:offline", { userId });
        }
      }
    });
  });

  app.decorate("broadcast", broadcast);
  app.decorate("getOnlineUsers", getOnlineUsers);
});
