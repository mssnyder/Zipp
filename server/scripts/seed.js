/**
 * Seed script — creates an admin user.
 * Usage: node scripts/seed.js
 * Set SEED_EMAIL, SEED_USERNAME, SEED_PASSWORD env vars or update defaults below.
 */
import "dotenv/config";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import pg from "pg";
import { hashPassword } from "../src/auth/crypto.js";

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });

const email = process.env.SEED_EMAIL || "admin@sinisterswiss.ch";
const username = process.env.SEED_USERNAME || "sinisterswiss";
const password = process.env.SEED_PASSWORD || "changeme123";

const existing = await prisma.user.findUnique({ where: { email } });
if (existing) {
  console.log(`User ${email} already exists.`);
} else {
  const user = await prisma.user.create({
    data: {
      email,
      username,
      displayName: username,
      hashedPassword: await hashPassword(password),
      emailVerified: true, // Skip email verification for seeded users
      isAdmin: true,
    },
  });
  console.log(`Created admin user: ${user.email} (id: ${user.id})`);
}

await prisma.$disconnect();
await pool.end();
