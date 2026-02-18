-- AlterTable
ALTER TABLE "User" ADD COLUMN     "encryptedPrivateKey" TEXT,
ADD COLUMN     "keyNonce" TEXT,
ADD COLUMN     "keySalt" TEXT;
