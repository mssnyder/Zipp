/**
 * File/image/video attachment uploads.
 *
 * Videos are transcoded to H.264/AAC MP4 with -movflags +faststart so they
 * can begin playing before the full file is downloaded (pseudo-streaming).
 * The RTX 4090 CUDA encoder (h264_nvenc) is used when available; falls back
 * to libx264 on CPU.
 *
 * Uploaded file URLs are returned to the client. The client then encrypts a
 * JSON payload (url, thumbUrl, mimeType, filename, sizeBytes, duration) and
 * sends it as the message ciphertext. The server only stores the URL.
 */
import { randomBytes } from "node:crypto";
import { writeFile, mkdir, unlink } from "node:fs/promises";
import { createWriteStream, statSync } from "node:fs";
import { join, extname } from "node:path";
import { pipeline } from "node:stream/promises";
import ffmpeg from "fluent-ffmpeg";

const UPLOAD_BASE = join(process.env.DATA_DIR ?? process.cwd(), "uploads");
const ATTACH_DIR = join(UPLOAD_BASE, "attachments");
const THUMB_DIR = join(UPLOAD_BASE, "thumbs");

const ALLOWED_IMAGE = ["image/jpeg", "image/png", "image/webp", "image/gif", "image/avif"];
const ALLOWED_VIDEO = ["video/mp4", "video/quicktime", "video/x-msvideo", "video/webm", "video/mpeg", "video/x-matroska"];
const ALLOWED_FILE = [
  "application/pdf",
  "text/plain",
  "application/zip",
  "application/x-zip-compressed",
  "application/gzip",
];

const MAX_IMAGE_BYTES = 50 * 1024 * 1024;   // 50 MB
const MAX_VIDEO_BYTES = 2 * 1024 * 1024 * 1024; // 2 GB
const MAX_FILE_BYTES = 100 * 1024 * 1024;   // 100 MB

function ensureAuth(req, reply) {
  if (!req.auth?.user) { reply.code(401).send({ error: "Unauthorized" }); return false; }
  return true;
}

function randomName(ext) {
  return `${randomBytes(16).toString("hex")}${ext}`;
}

/**
 * Transcode video to H.264/AAC MP4 with faststart for streaming.
 * Uses NVENC hardware encoder when available, falls back to libx264.
 */
function transcodeVideo(inputPath, outputPath) {
  return new Promise((resolve, reject) => {
    const cmd = ffmpeg(inputPath)
      .outputOptions([
        "-c:v h264_nvenc",   // NVIDIA GPU encoding
        "-preset p4",        // NVENC balanced quality preset
        "-cq 23",            // Constant quality
        "-c:a aac",
        "-b:a 128k",
        "-movflags +faststart", // Move moov atom to front for streaming
        "-pix_fmt yuv420p",  // Maximum compatibility
      ])
      .output(outputPath)
      .on("end", resolve)
      .on("error", (err) => {
        // Fallback to CPU libx264 if NVENC not available
        ffmpeg(inputPath)
          .outputOptions([
            "-c:v libx264",
            "-preset fast",
            "-crf 23",
            "-c:a aac",
            "-b:a 128k",
            "-movflags +faststart",
            "-pix_fmt yuv420p",
          ])
          .output(outputPath)
          .on("end", resolve)
          .on("error", reject)
          .run();
      });
    cmd.run();
  });
}

function getVideoDuration(inputPath) {
  return new Promise((resolve) => {
    ffmpeg.ffprobe(inputPath, (err, meta) => {
      resolve(err ? null : Math.round(meta?.format?.duration || 0));
    });
  });
}

function extractVideoThumbnail(inputPath, thumbPath) {
  return new Promise((resolve, reject) => {
    ffmpeg(inputPath)
      .screenshots({ count: 1, timemarks: ["5%"], filename: thumbPath, size: "480x?" })
      .on("end", resolve)
      .on("error", reject);
  });
}

export default async (app, prisma) => {
  await mkdir(ATTACH_DIR, { recursive: true });
  await mkdir(THUMB_DIR, { recursive: true });

  // POST /api/upload — upload image, video, or file attachment
  app.post("/api/upload", async (req, reply) => {
    if (!ensureAuth(req, reply)) return;

    const data = await req.file();
    if (!data) return reply.code(400).send({ error: "No file provided" });

    const mime = data.mimetype.toLowerCase();
    const isImage = ALLOWED_IMAGE.includes(mime);
    const isVideo = ALLOWED_VIDEO.includes(mime);
    const isFile = ALLOWED_FILE.includes(mime);

    if (!isImage && !isVideo && !isFile) {
      return reply.code(400).send({ error: `Unsupported file type: ${mime}` });
    }

    // Determine max size
    const maxBytes = isVideo ? MAX_VIDEO_BYTES : isImage ? MAX_IMAGE_BYTES : MAX_FILE_BYTES;

    // Stream to a temp file first to enforce size limit
    const ext = extname(data.filename || "").toLowerCase() || `.${mime.split("/")[1]}`;
    const tmpName = `tmp-${randomName(ext)}`;
    const tmpPath = join(ATTACH_DIR, tmpName);

    let bytesWritten = 0;
    const ws = createWriteStream(tmpPath);
    let limitExceeded = false;

    data.file.on("data", (chunk) => {
      bytesWritten += chunk.length;
      if (bytesWritten > maxBytes) {
        limitExceeded = true;
        ws.destroy();
        data.file.resume();
      }
    });

    await pipeline(data.file, ws).catch(() => {});

    if (limitExceeded) {
      await unlink(tmpPath).catch(() => {});
      return reply.code(413).send({ error: `File too large. Max ${Math.round(maxBytes / 1024 / 1024)} MB` });
    }

    const sizeBytes = statSync(tmpPath).size;
    let url, thumbUrl, duration;

    if (isVideo) {
      // Transcode video
      const outName = randomName(".mp4");
      const outPath = join(ATTACH_DIR, outName);
      const thumbName = randomName(".jpg");
      const thumbPath = join(THUMB_DIR, thumbName);

      try {
        await transcodeVideo(tmpPath, outPath);
        await extractVideoThumbnail(outPath, thumbPath).catch(() => {});
        duration = await getVideoDuration(outPath);
      } finally {
        await unlink(tmpPath).catch(() => {});
      }

      url = `/uploads/attachments/${outName}`;
      thumbUrl = `/uploads/thumbs/${thumbName}`;
    } else {
      // Images and files — store as-is (images stay uncompressed per requirement)
      const finalName = randomName(ext);
      const finalPath = join(ATTACH_DIR, finalName);
      // Rename temp file to final
      const { rename } = await import("node:fs/promises");
      await rename(tmpPath, finalPath);
      url = `/uploads/attachments/${finalName}`;

      // Generate thumbnail for images via ffmpeg (scale to 480px wide)
      if (isImage) {
        const thumbName = randomName(".webp");
        const thumbPath = join(THUMB_DIR, thumbName);
        await new Promise((resolve) => {
          ffmpeg(finalPath)
            .outputOptions(["-vf scale=480:-1", "-quality 80"])
            .output(thumbPath)
            .on("end", resolve)
            .on("error", resolve) // non-fatal
            .run();
        });
        thumbUrl = `/uploads/thumbs/${thumbName}`;
      }
    }

    // Store attachment record
    const attachment = await prisma.attachment.create({
      data: {
        uploaderId: req.auth.user.id,
        url,
        thumbUrl: thumbUrl || null,
        mimeType: mime,
        sizeBytes,
        duration: duration || null,
      },
    });

    return reply.code(201).send({
      attachment: {
        id: attachment.id,
        url: attachment.url,
        thumbUrl: attachment.thumbUrl,
        mimeType: attachment.mimeType,
        sizeBytes: attachment.sizeBytes,
        duration: attachment.duration,
      },
    });
  });

  // Serve attachment files — require auth
  app.get("/uploads/attachments/:filename", async (req, reply) => {
    if (!req.auth?.user) return reply.code(401).send({ error: "Unauthorized" });
    return reply.sendFile(`attachments/${req.params.filename}`, UPLOAD_BASE);
  });

  app.get("/uploads/thumbs/:filename", async (req, reply) => {
    if (!req.auth?.user) return reply.code(401).send({ error: "Unauthorized" });
    return reply.sendFile(`thumbs/${req.params.filename}`, UPLOAD_BASE);
  });
};
