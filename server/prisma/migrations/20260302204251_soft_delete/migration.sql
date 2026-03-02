-- AlterTable
ALTER TABLE "Message" ADD COLUMN     "deletedAt" TIMESTAMP(3),
ALTER COLUMN "nonce" DROP NOT NULL,
ALTER COLUMN "recipientCiphertext" DROP NOT NULL,
ALTER COLUMN "senderCiphertext" DROP NOT NULL;
