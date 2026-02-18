function ensureAuth(req, reply) {
  if (!req.auth?.user) { reply.code(401).send({ error: "Unauthorized" }); return false; }
  return true;
}

export default async (app) => {
  // GET /api/tenor/search?q=<query>&limit=20
  app.get("/api/tenor/search", async (req, reply) => {
    if (!ensureAuth(req, reply)) return;

    const apiKey = process.env.TENOR_API_KEY;
    if (!apiKey) return reply.code(503).send({ error: "GIF search not configured" });

    const q = String(req.query.q || "").trim();
    const limit = Math.min(Number(req.query.limit) || 20, 50);

    const url = new URL("https://tenor.googleapis.com/v2/search");
    url.searchParams.set("key", apiKey);
    url.searchParams.set("q", q || "trending");
    url.searchParams.set("limit", String(limit));
    url.searchParams.set("media_filter", "gif,tinygif");
    url.searchParams.set("contentfilter", "medium");

    const res = await fetch(url.toString());
    if (!res.ok) return reply.code(502).send({ error: "Tenor API error" });

    const data = await res.json();
    return { results: data.results || [] };
  });

  // GET /api/tenor/trending
  app.get("/api/tenor/trending", async (req, reply) => {
    if (!ensureAuth(req, reply)) return;

    const apiKey = process.env.TENOR_API_KEY;
    if (!apiKey) return reply.code(503).send({ error: "GIF search not configured" });

    const limit = Math.min(Number(req.query.limit) || 20, 50);

    const url = new URL("https://tenor.googleapis.com/v2/featured");
    url.searchParams.set("key", apiKey);
    url.searchParams.set("limit", String(limit));
    url.searchParams.set("media_filter", "gif,tinygif");
    url.searchParams.set("contentfilter", "medium");

    const res = await fetch(url.toString());
    if (!res.ok) return reply.code(502).send({ error: "Tenor API error" });

    const data = await res.json();
    return { results: data.results || [] };
  });
};
