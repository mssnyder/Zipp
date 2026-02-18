// Ported from apitaph — Argon2id password hashing
import { hash as a2hash, verify as a2verify, Algorithm, Version } from "@node-rs/argon2";

const cfg = {
  memMB: Number(process.env.ARGON2_MEMORY_MB ?? 128),
  time: Number(process.env.ARGON2_TIME ?? 3),
  par: Number(process.env.ARGON2_PARALLELISM ?? 1),
  len: Number(process.env.ARGON2_HASH_LEN ?? 32),
  pepper: process.env.ARGON2_PEPPER ?? "",
};

if (!cfg.pepper) {
  const msg = "ARGON2_PEPPER environment variable is required";
  console.error(msg);
  if (process.env.NODE_ENV !== "development") throw new Error(msg);
}

const opts = {
  memoryCost: cfg.memMB * 1024,
  timeCost: cfg.time,
  parallelism: cfg.par,
  hashLength: cfg.len,
  algorithm: Algorithm.Argon2id,
  version: Version.V0x13,
};

export async function hashPassword(password) {
  if (typeof password !== "string" || !password) throw new Error("bad password");
  return a2hash(password + cfg.pepper, opts);
}

export async function verifyPassword(hashed, password) {
  if (!hashed || !password) return false;
  return a2verify(hashed, password + cfg.pepper);
}

export function needsRehash(hashed) {
  try {
    const m = hashed.match(/\$argon2id\$v=\d+\$m=(\d+),t=(\d+),p=(\d+)\$/);
    if (!m) return true;
    const [memKiB, time, par] = m.slice(1).map(Number);
    return memKiB < opts.memoryCost || time < opts.timeCost || par < opts.parallelism;
  } catch { return true; }
}

export async function verifyAndUpgrade(hashed, password) {
  const ok = await verifyPassword(hashed, password);
  if (!ok) return { ok: false };
  if (needsRehash(hashed)) return { ok: true, newHash: await hashPassword(password) };
  return { ok: true };
}
