import { RATE_LIMITS, PAGINATION } from "../constants.js";

function ensureAuth(req, reply) {
  if (!req.auth?.user) {
    reply.code(401).send({ error: "Unauthorized" });
    return false;
  }
  return true;
}

const EPOCH_KEY_SELECT = {
  userId: true,
  encryptedKey: true,
  keyNonce: true,
  wrappedById: true,
};

function formatMessage(msg, requestingUserId) {
  const base = {
    id: msg.id,
    conversationId: msg.conversationId,
    senderId: msg.senderId,
    nonce: msg.nonce,
    type: msg.type,
    replyToId: msg.replyToId,
    replyTo: msg.replyTo
      ? formatReplyPreview(msg.replyTo, requestingUserId)
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
    deletedAt: msg.deletedAt ?? null,
    createdAt: msg.createdAt,
  };

  if (msg.epochId) {
    // Group message
    const myKey = msg.epoch?.keys?.find((k) => k.userId === requestingUserId) ?? null;
    return {
      ...base,
      ciphertext: msg.ciphertext,
      epochId: msg.epochId,
      epochKey: myKey ? { encryptedKey: myKey.encryptedKey, keyNonce: myKey.keyNonce, wrappedById: myKey.wrappedById } : null,
    };
  }

  // DM message
  return {
    ...base,
    recipientCiphertext: msg.recipientCiphertext,
    senderCiphertext: msg.senderCiphertext,
  };
}

function formatReplyPreview(reply, requestingUserId) {
  const base = {
    id: reply.id,
    senderId: reply.senderId,
    nonce: reply.nonce,
    type: reply.type,
  };

  if (reply.epochId) {
    const myKey = reply.epoch?.keys?.find((k) => k.userId === requestingUserId) ?? null;
    return {
      ...base,
      ciphertext: reply.ciphertext,
      epochId: reply.epochId,
      epochKey: myKey ? { encryptedKey: myKey.encryptedKey, keyNonce: myKey.keyNonce, wrappedById: myKey.wrappedById } : null,
    };
  }

  return {
    ...base,
    recipientCiphertext: reply.recipientCiphertext,
    senderCiphertext: reply.senderCiphertext,
  };
}

const REPLY_INCLUDE = {
  select: {
    id: true,
    senderId: true,
    recipientCiphertext: true,
    senderCiphertext: true,
    ciphertext: true,
    nonce: true,
    type: true,
    epochId: true,
    epoch: { include: { keys: { select: EPOCH_KEY_SELECT } } },
  },
};

function messageInclude(userId) {
  return {
    replyTo: REPLY_INCLUDE,
    reactions: {
      select: { id: true, userId: true, emoji: true, createdAt: true, user: { select: { displayName: true } } },
    },
    epoch: { include: { keys: { where: { userId }, select: EPOCH_KEY_SELECT } } },
  };
}

async function verifyMembership(prisma, conversationId, userId) {
  const membership = await prisma.conversationParticipant.findUnique({
    where: {
      conversationId_userId: { conversationId, userId },
    },
  });
  if (!membership || membership.leftAt) return null;
  return membership;
}

export default async (app, prisma) => {
  // GET /api/conversations/:id/messages
  app.get("/api/conversations/:id/messages", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const membership = await verifyMembership(prisma, req.params.id, req.auth.user.id);
    if (!membership) return reply.code(403).send({ error: "Forbidden" });

    const { before, limit } = req.query;
    const take = Math.min(Number(limit) || PAGINATION.MESSAGES_PER_PAGE, 100);

    const messages = await prisma.message.findMany({
      where: {
        conversationId: req.params.id,
        ...(before ? { createdAt: { lt: new Date(before) } } : {}),
      },
      include: messageInclude(req.auth.user.id),
      orderBy: { createdAt: "desc" },
      take,
    });

    return { messages: messages.reverse().map((m) => formatMessage(m, req.auth.user.id)) };
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

      const membership = await verifyMembership(prisma, req.params.id, req.auth.user.id);
      if (!membership) return reply.code(403).send({ error: "Forbidden" });

      const {
        nonce,
        type = "TEXT",
        replyToId,
        // DM fields
        recipientCiphertext,
        senderCiphertext,
        // Group fields
        ciphertext,
        epochId,
        epoch: epochInit,
      } = req.body || {};

      if (!nonce) {
        return reply.code(400).send({ error: "Missing required field: nonce" });
      }
      if (!["TEXT", "GIF", "IMAGE", "VIDEO", "FILE"].includes(type)) {
        return reply.code(400).send({ error: "Invalid message type" });
      }

      let messageData;

      if (epochId) {
        // Group message path
        if (!ciphertext) {
          return reply.code(400).send({ error: "Missing required field: ciphertext" });
        }

        // Validate epoch belongs to this conversation
        const epoch = await prisma.conversationEpoch.findUnique({
          where: { id: epochId },
          select: { id: true, conversationId: true },
        });
        if (!epoch || epoch.conversationId !== req.params.id) {
          return reply.code(400).send({ error: "Invalid epoch for this conversation" });
        }

        // Lazy epoch initialization
        if (epochInit?.keys && Array.isArray(epochInit.keys)) {
          const existingKeys = await prisma.epochKey.count({ where: { epochId } });
          if (existingKeys === 0) {
            await prisma.epochKey.createMany({
              data: epochInit.keys.map((k) => ({
                epochId,
                userId: k.userId,
                encryptedKey: k.encryptedKey,
                keyNonce: k.keyNonce,
                wrappedById: req.auth.user.id,
              })),
              skipDuplicates: true,
            });
          }
        }

        messageData = {
          conversationId: req.params.id,
          senderId: req.auth.user.id,
          ciphertext,
          nonce,
          epochId,
          type,
          replyToId: replyToId || null,
        };
      } else {
        // DM message path
        if (!recipientCiphertext || !senderCiphertext) {
          return reply.code(400).send({
            error: "Missing required fields: recipientCiphertext, senderCiphertext",
          });
        }

        messageData = {
          conversationId: req.params.id,
          senderId: req.auth.user.id,
          recipientCiphertext,
          senderCiphertext,
          nonce,
          type,
          replyToId: replyToId || null,
        };
      }

      const message = await prisma.message.create({
        data: messageData,
        include: messageInclude(req.auth.user.id),
      });

      // Update conversation updatedAt
      await prisma.conversation.update({
        where: { id: req.params.id },
        data: { updatedAt: new Date() },
      });

      // Broadcast to other participants
      const participants = await prisma.conversationParticipant.findMany({
        where: { conversationId: req.params.id, leftAt: null },
        select: { userId: true },
      });

      // For group messages, each recipient needs their own epoch key in the payload
      // Re-fetch with all keys for broadcast
      let broadcastMsg;
      if (epochId) {
        const fullMsg = await prisma.message.findUnique({
          where: { id: message.id },
          include: {
            replyTo: REPLY_INCLUDE,
            reactions: {
              select: { id: true, userId: true, emoji: true, createdAt: true, user: { select: { displayName: true } } },
            },
            epoch: { include: { keys: { select: EPOCH_KEY_SELECT } } },
          },
        });
        broadcastMsg = fullMsg || message;
      } else {
        broadcastMsg = message;
      }

      const userIds = participants
        .map((p) => p.userId)
        .filter((id) => id !== req.auth.user.id);
      for (const uid of userIds) {
        app.broadcast([uid], "message:new", {
          conversationId: req.params.id,
          message: formatMessage(broadcastMsg, uid),
        });
      }

      return reply.code(201).send({ message: formatMessage(message, req.auth.user.id) });
    },
  });

  // PATCH /api/conversations/:id/messages/:msgId/read
  app.patch(
    "/api/conversations/:id/messages/:msgId/read",
    async (req, reply) => {
      if (!ensureAuth(req, reply)) return reply;

      const membership = await verifyMembership(prisma, req.params.id, req.auth.user.id);
      if (!membership) return reply.code(403).send({ error: "Forbidden" });

      const msg = await prisma.message.findFirst({
        where: { id: req.params.msgId, conversationId: req.params.id },
      });
      if (!msg || msg.senderId === req.auth.user.id) return { ok: true };

      const now = new Date();

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

      const { recipientCiphertext, senderCiphertext, ciphertext, nonce } = req.body || {};

      let updateData;
      if (msg.epochId) {
        // Group message edit
        if (!ciphertext || !nonce) {
          return reply.code(400).send({ error: "Missing required fields: ciphertext, nonce" });
        }
        updateData = { ciphertext, nonce, editedAt: new Date() };
      } else {
        // DM edit
        if (!recipientCiphertext || !senderCiphertext || !nonce) {
          return reply.code(400).send({
            error: "Missing required fields: recipientCiphertext, senderCiphertext, nonce",
          });
        }
        updateData = { recipientCiphertext, senderCiphertext, nonce, editedAt: new Date() };
      }

      const updated = await prisma.message.update({
        where: { id: req.params.msgId },
        data: updateData,
        include: messageInclude(req.auth.user.id),
      });

      const participants = await prisma.conversationParticipant.findMany({
        where: { conversationId: req.params.id, leftAt: null },
        select: { userId: true },
      });

      // Broadcast with per-user epoch keys for group messages
      if (msg.epochId) {
        const fullMsg = await prisma.message.findUnique({
          where: { id: updated.id },
          include: {
            replyTo: REPLY_INCLUDE,
            reactions: {
              select: { id: true, userId: true, emoji: true, createdAt: true, user: { select: { displayName: true } } },
            },
            epoch: { include: { keys: { select: EPOCH_KEY_SELECT } } },
          },
        });
        for (const p of participants) {
          app.broadcast([p.userId], "message:edit", {
            conversationId: req.params.id,
            message: formatMessage(fullMsg || updated, p.userId),
          });
        }
      } else {
        app.broadcast(
          participants.map((p) => p.userId),
          "message:edit",
          { conversationId: req.params.id, message: formatMessage(updated, req.auth.user.id) },
        );
      }

      return { message: formatMessage(updated, req.auth.user.id) };
    },
  );

  // DELETE /api/conversations/:id/messages/:msgId
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
        where: { conversationId: req.params.id, leftAt: null },
        select: { userId: true },
      });

      const replyCount = await prisma.message.count({
        where: { replyToId: req.params.msgId },
      });

      if (replyCount > 0) {
        await prisma.message.update({
          where: { id: req.params.msgId },
          data: {
            recipientCiphertext: null,
            senderCiphertext: null,
            ciphertext: null,
            nonce: null,
            deletedAt: new Date(),
          },
        });
        await prisma.reaction.deleteMany({ where: { messageId: req.params.msgId } });
      } else {
        await prisma.message.delete({ where: { id: req.params.msgId } });
      }

      app.broadcast(
        participants.map((p) => p.userId),
        "message:delete",
        {
          conversationId: req.params.id,
          messageId: req.params.msgId,
          softDelete: replyCount > 0,
        },
      );

      return { ok: true };
    },
  );

  // ── Member management ──────────────────────────────────────────────────────

  // POST /api/conversations/:id/members — invite members (admin-only)
  app.post("/api/conversations/:id/members", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const membership = await verifyMembership(prisma, req.params.id, req.auth.user.id);
    if (!membership || membership.role !== "ADMIN") {
      return reply.code(403).send({ error: "Only admins can invite members" });
    }

    const conv = await prisma.conversation.findUnique({
      where: { id: req.params.id },
      select: { isGroup: true },
    });
    if (!conv?.isGroup) return reply.code(400).send({ error: "Can only invite to group conversations" });

    const { userIds, shareHistory, newEpoch, epochKeys } = req.body || {};

    if (!Array.isArray(userIds) || userIds.length === 0) {
      return reply.code(400).send({ error: "Missing userIds" });
    }
    if (!newEpoch?.keys || !Array.isArray(newEpoch.keys)) {
      return reply.code(400).send({ error: "Missing newEpoch.keys" });
    }

    // Verify users exist
    const users = await prisma.user.findMany({
      where: { id: { in: userIds } },
      select: { id: true },
    });
    if (users.length !== userIds.length) {
      return reply.code(400).send({ error: "One or more users not found" });
    }

    // Check for existing active participants
    const existing = await prisma.conversationParticipant.findMany({
      where: { conversationId: req.params.id, userId: { in: userIds }, leftAt: null },
      select: { userId: true },
    });
    const existingIds = new Set(existing.map((p) => p.userId));
    const newUserIds = userIds.filter((id) => !existingIds.has(id));

    if (newUserIds.length === 0) {
      return reply.code(400).send({ error: "All users are already participants" });
    }

    // Add new participants (upsert for re-joining)
    for (const uid of newUserIds) {
      await prisma.conversationParticipant.upsert({
        where: { conversationId_userId: { conversationId: req.params.id, userId: uid } },
        update: { leftAt: null, role: "MEMBER" },
        create: { conversationId: req.params.id, userId: uid, role: "MEMBER" },
      });
    }

    // Create new epoch (membership changed)
    const lastEpoch = await prisma.conversationEpoch.findFirst({
      where: { conversationId: req.params.id },
      orderBy: { epochNumber: "desc" },
      select: { epochNumber: true },
    });
    const newEpochNumber = (lastEpoch?.epochNumber ?? -1) + 1;

    const createdEpoch = await prisma.conversationEpoch.create({
      data: {
        conversationId: req.params.id,
        epochNumber: newEpochNumber,
        createdById: req.auth.user.id,
        keys: {
          create: newEpoch.keys.map((k) => ({
            userId: k.userId,
            encryptedKey: k.encryptedKey,
            keyNonce: k.keyNonce,
            wrappedById: req.auth.user.id,
          })),
        },
      },
    });

    // Share historical epoch keys with new members if requested
    if (shareHistory && Array.isArray(epochKeys) && epochKeys.length > 0) {
      await prisma.epochKey.createMany({
        data: epochKeys.map((k) => ({
          epochId: k.epochId,
          userId: k.userId,
          encryptedKey: k.encryptedKey,
          keyNonce: k.keyNonce,
          wrappedById: req.auth.user.id,
        })),
        skipDuplicates: true,
      });
    }

    // Get updated conversation
    const updated = await prisma.conversation.findUnique({
      where: { id: req.params.id },
      include: {
        participants: {
          where: { leftAt: null },
          include: { user: { select: { id: true, username: true, displayName: true, avatarUrl: true } } },
        },
      },
    });

    const allParticipantIds = updated.participants.map((p) => p.userId);

    // Broadcast member-added to existing members
    app.broadcast(allParticipantIds, "conversation:member-added", {
      conversationId: req.params.id,
      participants: updated.participants.map((p) => ({
        id: p.user.id,
        username: p.user.username,
        displayName: p.user.displayName,
        avatarUrl: p.user.avatarUrl,
        role: p.role,
      })),
    });

    // Broadcast epoch:created
    app.broadcast(allParticipantIds, "epoch:created", {
      conversationId: req.params.id,
      epochId: createdEpoch.id,
      epochNumber: newEpochNumber,
    });

    // Notify new members with the full conversation
    for (const uid of newUserIds) {
      app.broadcast([uid], "conversation:new", {
        conversation: {
          id: updated.id,
          isGroup: updated.isGroup,
          name: updated.name,
          updatedAt: updated.updatedAt,
          participants: updated.participants.map((p) => ({
            id: p.user.id,
            username: p.user.username,
            displayName: p.user.displayName,
            avatarUrl: p.user.avatarUrl,
            role: p.role,
          })),
          lastMessage: null,
        },
      });
    }

    return { ok: true };
  });

  // DELETE /api/conversations/:id/members/:userId — remove member (admin-only)
  app.delete("/api/conversations/:id/members/:userId", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const currentUserId = req.auth.user.id;
    const targetUserId = req.params.userId;

    if (currentUserId === targetUserId) {
      return reply.code(400).send({ error: "Use the leave endpoint to remove yourself" });
    }

    const membership = await verifyMembership(prisma, req.params.id, currentUserId);
    if (!membership || membership.role !== "ADMIN") {
      return reply.code(403).send({ error: "Only admins can remove members" });
    }

    const target = await verifyMembership(prisma, req.params.id, targetUserId);
    if (!target) return reply.code(404).send({ error: "User is not an active participant" });

    if (target.role === "ADMIN") {
      return reply.code(400).send({ error: "Cannot remove an admin. Demote them first." });
    }

    // Mark as left
    await prisma.conversationParticipant.update({
      where: { conversationId_userId: { conversationId: req.params.id, userId: targetUserId } },
      data: { leftAt: new Date() },
    });

    // Delete removed user's epoch keys
    await prisma.epochKey.deleteMany({
      where: {
        userId: targetUserId,
        epoch: { conversationId: req.params.id },
      },
    });

    // Create new epoch (lazy init)
    const lastEpoch = await prisma.conversationEpoch.findFirst({
      where: { conversationId: req.params.id },
      orderBy: { epochNumber: "desc" },
      select: { epochNumber: true },
    });
    const newEpochNumber = (lastEpoch?.epochNumber ?? -1) + 1;

    const createdEpoch = await prisma.conversationEpoch.create({
      data: {
        conversationId: req.params.id,
        epochNumber: newEpochNumber,
        createdById: currentUserId,
      },
    });

    const remaining = await prisma.conversationParticipant.findMany({
      where: { conversationId: req.params.id, leftAt: null },
      select: { userId: true },
    });

    app.broadcast(
      remaining.map((p) => p.userId),
      "conversation:member-removed",
      { conversationId: req.params.id, userId: targetUserId },
    );
    app.broadcast(
      remaining.map((p) => p.userId),
      "epoch:created",
      { conversationId: req.params.id, epochId: createdEpoch.id, epochNumber: newEpochNumber },
    );
    app.broadcast([targetUserId], "conversation:member-removed", {
      conversationId: req.params.id,
      userId: targetUserId,
    });

    return { ok: true };
  });

  // PATCH /api/conversations/:id/members/:userId/role — change role (admin-only)
  app.patch("/api/conversations/:id/members/:userId/role", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const currentUserId = req.auth.user.id;
    const targetUserId = req.params.userId;

    const membership = await verifyMembership(prisma, req.params.id, currentUserId);
    if (!membership || membership.role !== "ADMIN") {
      return reply.code(403).send({ error: "Only admins can change roles" });
    }

    const { role } = req.body || {};
    if (!["ADMIN", "MEMBER"].includes(role)) {
      return reply.code(400).send({ error: "Role must be ADMIN or MEMBER" });
    }

    const target = await verifyMembership(prisma, req.params.id, targetUserId);
    if (!target) return reply.code(404).send({ error: "User is not an active participant" });

    // If demoting self, verify another admin exists
    if (currentUserId === targetUserId && role === "MEMBER") {
      const otherAdmin = await prisma.conversationParticipant.findFirst({
        where: {
          conversationId: req.params.id,
          leftAt: null,
          role: "ADMIN",
          userId: { not: currentUserId },
        },
      });
      if (!otherAdmin) {
        return reply.code(400).send({ error: "Cannot demote yourself — you are the only admin" });
      }
    }

    await prisma.conversationParticipant.update({
      where: { conversationId_userId: { conversationId: req.params.id, userId: targetUserId } },
      data: { role },
    });

    const participants = await prisma.conversationParticipant.findMany({
      where: { conversationId: req.params.id, leftAt: null },
      select: { userId: true },
    });
    app.broadcast(
      participants.map((p) => p.userId),
      "conversation:role-changed",
      { conversationId: req.params.id, userId: targetUserId, role },
    );

    return { ok: true, userId: targetUserId, role };
  });

  // POST /api/conversations/:id/leave — leave group
  app.post("/api/conversations/:id/leave", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const userId = req.auth.user.id;
    const membership = await verifyMembership(prisma, req.params.id, userId);
    if (!membership) return reply.code(403).send({ error: "Not a participant" });

    const conv = await prisma.conversation.findUnique({
      where: { id: req.params.id },
      select: { isGroup: true },
    });
    if (!conv?.isGroup) return reply.code(400).send({ error: "Can only leave group conversations" });

    // If admin, check another admin exists
    if (membership.role === "ADMIN") {
      const otherAdmin = await prisma.conversationParticipant.findFirst({
        where: {
          conversationId: req.params.id,
          leftAt: null,
          role: "ADMIN",
          userId: { not: userId },
        },
      });
      if (!otherAdmin) {
        return reply.code(400).send({ error: "You are the only admin. Transfer admin role before leaving." });
      }
    }

    await prisma.conversationParticipant.update({
      where: { conversationId_userId: { conversationId: req.params.id, userId } },
      data: { leftAt: new Date() },
    });

    // Delete leaver's epoch keys
    await prisma.epochKey.deleteMany({
      where: {
        userId,
        epoch: { conversationId: req.params.id },
      },
    });

    // Check if anyone remains
    const remaining = await prisma.conversationParticipant.findMany({
      where: { conversationId: req.params.id, leftAt: null },
      select: { userId: true },
    });

    if (remaining.length === 0) {
      await prisma.conversation.delete({ where: { id: req.params.id } });
    } else {
      // Create new epoch (lazy init)
      const lastEpoch = await prisma.conversationEpoch.findFirst({
        where: { conversationId: req.params.id },
        orderBy: { epochNumber: "desc" },
        select: { epochNumber: true },
      });
      const newEpochNumber = (lastEpoch?.epochNumber ?? -1) + 1;

      const createdEpoch = await prisma.conversationEpoch.create({
        data: {
          conversationId: req.params.id,
          epochNumber: newEpochNumber,
          createdById: userId,
        },
      });

      app.broadcast(
        remaining.map((p) => p.userId),
        "conversation:member-left",
        { conversationId: req.params.id, userId },
      );
      app.broadcast(
        remaining.map((p) => p.userId),
        "epoch:created",
        { conversationId: req.params.id, epochId: createdEpoch.id, epochNumber: newEpochNumber },
      );
    }

    return { ok: true };
  });

  // ── Epoch endpoints ────────────────────────────────────────────────────────

  // GET /api/conversations/:id/epoch — get current epoch + caller's key
  app.get("/api/conversations/:id/epoch", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const membership = await verifyMembership(prisma, req.params.id, req.auth.user.id);
    if (!membership) return reply.code(403).send({ error: "Forbidden" });

    const epoch = await prisma.conversationEpoch.findFirst({
      where: { conversationId: req.params.id },
      orderBy: { epochNumber: "desc" },
      include: {
        keys: { where: { userId: req.auth.user.id }, select: EPOCH_KEY_SELECT },
      },
    });

    if (!epoch) return { epoch: null };

    return {
      epoch: {
        id: epoch.id,
        epochNumber: epoch.epochNumber,
        myKey: epoch.keys[0] || null,
      },
    };
  });

  // GET /api/conversations/:id/epochs — all epochs + caller's keys (for history sharing)
  app.get("/api/conversations/:id/epochs", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const membership = await verifyMembership(prisma, req.params.id, req.auth.user.id);
    if (!membership) return reply.code(403).send({ error: "Forbidden" });

    const epochs = await prisma.conversationEpoch.findMany({
      where: { conversationId: req.params.id },
      orderBy: { epochNumber: "asc" },
      include: {
        keys: { where: { userId: req.auth.user.id }, select: EPOCH_KEY_SELECT },
      },
    });

    return {
      epochs: epochs.map((e) => ({
        id: e.id,
        epochNumber: e.epochNumber,
        createdAt: e.createdAt,
        myKey: e.keys[0] || null,
      })),
    };
  });

  // POST /api/conversations/:id/epochs — create a new epoch with keys
  app.post("/api/conversations/:id/epochs", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const membership = await verifyMembership(prisma, req.params.id, req.auth.user.id);
    if (!membership) return reply.code(403).send({ error: "Forbidden" });

    const { keys } = req.body || {};
    if (!Array.isArray(keys) || keys.length === 0) {
      return reply.code(400).send({ error: "Missing keys" });
    }

    const lastEpoch = await prisma.conversationEpoch.findFirst({
      where: { conversationId: req.params.id },
      orderBy: { epochNumber: "desc" },
      select: { epochNumber: true },
    });
    const newEpochNumber = (lastEpoch?.epochNumber ?? -1) + 1;

    const epoch = await prisma.conversationEpoch.create({
      data: {
        conversationId: req.params.id,
        epochNumber: newEpochNumber,
        createdById: req.auth.user.id,
        keys: {
          create: keys.map((k) => ({
            userId: k.userId,
            encryptedKey: k.encryptedKey,
            keyNonce: k.keyNonce,
            wrappedById: req.auth.user.id,
          })),
        },
      },
    });

    const participants = await prisma.conversationParticipant.findMany({
      where: { conversationId: req.params.id, leftAt: null },
      select: { userId: true },
    });
    app.broadcast(
      participants.map((p) => p.userId),
      "epoch:created",
      { conversationId: req.params.id, epochId: epoch.id, epochNumber: newEpochNumber },
    );

    return reply.code(201).send({ id: epoch.id, epochNumber: newEpochNumber });
  });

  // POST /api/conversations/:id/epochs/:epochId/keys — add keys to an existing epoch
  app.post("/api/conversations/:id/epochs/:epochId/keys", async (req, reply) => {
    if (!ensureAuth(req, reply)) return reply;

    const membership = await verifyMembership(prisma, req.params.id, req.auth.user.id);
    if (!membership) return reply.code(403).send({ error: "Forbidden" });

    const epoch = await prisma.conversationEpoch.findUnique({
      where: { id: req.params.epochId },
      select: { conversationId: true },
    });
    if (!epoch || epoch.conversationId !== req.params.id) {
      return reply.code(400).send({ error: "Invalid epoch for this conversation" });
    }

    const { keys } = req.body || {};
    if (!Array.isArray(keys) || keys.length === 0) {
      return reply.code(400).send({ error: "Missing keys" });
    }

    await prisma.epochKey.createMany({
      data: keys.map((k) => ({
        epochId: req.params.epochId,
        userId: k.userId,
        encryptedKey: k.encryptedKey,
        keyNonce: k.keyNonce,
        wrappedById: req.auth.user.id,
      })),
      skipDuplicates: true,
    });

    return { ok: true };
  });
};
