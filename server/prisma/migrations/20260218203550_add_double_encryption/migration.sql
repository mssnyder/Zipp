/*
  Warnings:

  - You are about to drop the column `ciphertext` on the `Message` table. All the data in the column will be lost.
  - Added the required column `recipientCiphertext` to the `Message` table without a default value. This is not possible if the table is not empty.
  - Added the required column `senderCiphertext` to the `Message` table without a default value. This is not possible if the table is not empty.

*/
-- AlterTable
ALTER TABLE "Message" DROP COLUMN "ciphertext",
ADD COLUMN     "recipientCiphertext" TEXT NOT NULL,
ADD COLUMN     "senderCiphertext" TEXT NOT NULL;
