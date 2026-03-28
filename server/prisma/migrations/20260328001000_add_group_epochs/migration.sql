-- CreateEnum
CREATE TYPE "ConversationRole" AS ENUM ('MEMBER', 'ADMIN');

-- AlterTable
ALTER TABLE "Conversation" ADD COLUMN     "isGroup" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "name" TEXT;

-- AlterTable
ALTER TABLE "ConversationParticipant" ADD COLUMN     "leftAt" TIMESTAMP(3),
ADD COLUMN     "role" "ConversationRole" NOT NULL DEFAULT 'MEMBER';

-- AlterTable
ALTER TABLE "Message" ADD COLUMN     "ciphertext" TEXT,
ADD COLUMN     "epochId" TEXT;

-- CreateTable
CREATE TABLE "ConversationEpoch" (
    "id" TEXT NOT NULL,
    "conversationId" TEXT NOT NULL,
    "epochNumber" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdById" TEXT NOT NULL,

    CONSTRAINT "ConversationEpoch_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "EpochKey" (
    "id" TEXT NOT NULL,
    "epochId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "encryptedKey" TEXT NOT NULL,
    "keyNonce" TEXT NOT NULL,
    "wrappedById" TEXT NOT NULL,

    CONSTRAINT "EpochKey_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ConversationEpoch_conversationId_idx" ON "ConversationEpoch"("conversationId");

-- CreateIndex
CREATE UNIQUE INDEX "ConversationEpoch_conversationId_epochNumber_key" ON "ConversationEpoch"("conversationId", "epochNumber");

-- CreateIndex
CREATE INDEX "EpochKey_epochId_idx" ON "EpochKey"("epochId");

-- CreateIndex
CREATE INDEX "EpochKey_userId_idx" ON "EpochKey"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "EpochKey_epochId_userId_key" ON "EpochKey"("epochId", "userId");

-- CreateIndex
CREATE INDEX "Message_epochId_idx" ON "Message"("epochId");

-- AddForeignKey
ALTER TABLE "ConversationEpoch" ADD CONSTRAINT "ConversationEpoch_conversationId_fkey" FOREIGN KEY ("conversationId") REFERENCES "Conversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ConversationEpoch" ADD CONSTRAINT "ConversationEpoch_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EpochKey" ADD CONSTRAINT "EpochKey_epochId_fkey" FOREIGN KEY ("epochId") REFERENCES "ConversationEpoch"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EpochKey" ADD CONSTRAINT "EpochKey_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EpochKey" ADD CONSTRAINT "EpochKey_wrappedById_fkey" FOREIGN KEY ("wrappedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Message" ADD CONSTRAINT "Message_epochId_fkey" FOREIGN KEY ("epochId") REFERENCES "ConversationEpoch"("id") ON DELETE SET NULL ON UPDATE CASCADE;
