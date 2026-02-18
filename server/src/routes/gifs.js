function ensureAuth(req, reply) {
  if (!req.auth?.user) { reply.code(401).send({ error: "Unauthorized" }); return false; }
  return true;
}

// Klipy API base: https://api.klipy.com/api/v1/{app_key}/gifs
// Response shape: { result: true, data: { data: [...gifs], has_next: bool, ... } }
// GIF object: { id, slug, title, file: { hd, md, sm, xs: { gif, webp, mp4, jpg } } }

export default async (app) => {
  // GET /api/gifs/search?q=<query>&limit=20
  app.get("/api/gifs/search", async (req, reply) => {
    if (!ensureAuth(req, reply)) return;

    const apiKey = process.env.KLIPY_API_KEY;
    if (!apiKey) return reply.code(503).send({ error: "GIF search not configured" });

    const q = String(req.query.q || "").trim();
    const limit = Math.min(Number(req.query.limit) || 20, 50);

    const url = new URL(`https://api.klipy.com/api/v1/${apiKey}/gifs/search`);
    url.searchParams.set("q", q || "trending");
    url.searchParams.set("per_page", String(limit));
    url.searchParams.set("content_filter", "medium");

    const res = await fetch(url.toString());
    if (!res.ok) return reply.code(502).send({ error: "GIF API error" });

    const data = await res.json();
    return { results: data.data?.data || [] };
  });

  // GET /api/gifs/trending
  app.get("/api/gifs/trending", async (req, reply) => {
    if (!ensureAuth(req, reply)) return;

    const apiKey = process.env.KLIPY_API_KEY;
    if (!apiKey) return reply.code(503).send({ error: "GIF search not configured" });

    const limit = Math.min(Number(req.query.limit) || 20, 50);

    const url = new URL(`https://api.klipy.com/api/v1/${apiKey}/gifs/trending`);
    url.searchParams.set("per_page", String(limit));

    const res = await fetch(url.toString());
    if (!res.ok) return reply.code(502).send({ error: "GIF API error" });

    const data = await res.json();
    return { results: data.data?.data || [] };
  });
};
