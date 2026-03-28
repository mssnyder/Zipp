# Zipp — Server

Node.js backend for Zipp. Handles REST API, WebSockets, file uploads, and Google OAuth.

## Tech stack

- **Runtime**: Node.js 24
- **Framework**: Fastify
- **Database**: PostgreSQL via Prisma ORM
- **Auth**: Session cookies (fastify-secure-session), Google OAuth (fastify-grant)
- **Passwords**: Argon2id (`@node-rs/argon2`)
- **File storage**: Local filesystem under `DATA_DIR`

## Prerequisites

- Node.js 24+
- PostgreSQL
- (Optional) ffmpeg — required for video transcoding

## Setup

```bash
npm install
```

Copy the example env file and fill in your values:

```bash
cp .env.example .env
```

### Environment variables

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string |
| `SESSION_SECRET` | Cookie signing secret (min 32 chars) |
| `ARGON2_PEPPER` | Additional secret mixed into password hashes |
| `GOOGLE_CLIENT_ID` | Google OAuth app client ID |
| `GOOGLE_CLIENT_SECRET` | Google OAuth app client secret |
| `KLIPY_API_KEY` | Klipy API key for GIF search |
| `SMTP_HOST/PORT/USER/PASS` | SMTP relay for email verification |
| `DATA_DIR` | Root directory for uploads and logs (default: `./`) |
| `SERVER_URL` | Public URL of this server |
| `FRONTEND_URL` | Public URL of the frontend (used for OAuth redirects) |
| `ALLOW_SIGNUPS` | Set to `false` to disable new registrations |
| `PORT` | Port to listen on (default: `4200`) |

### Database

Run migrations to initialise or update the schema:

```bash
npx prisma migrate deploy
```

To inspect the database interactively:

```bash
npx prisma studio
```

## Development

```bash
node src/server.js
```

The server reloads automatically if you use `nodemon`:

```bash
npx nodemon src/server.js
```

## Production / NixOS deployment

See the [top-level README](../README.md) for NixOS module setup.  The server runs as a rootless systemd user service.

To restart after config changes:

```bash
systemctl --user restart zipp
```

### Updating the database schema in production

```bash
npx prisma migrate deploy
systemctl --user restart zipp
```

## API overview

| Prefix | Description |
|---|---|
| `POST /api/auth/*` | Register, login, logout |
| `GET /api/me` | Current user profile |
| `PATCH /api/me` | Update display name / username / avatar |
| `POST /api/me/password` | Change password |
| `DELETE /api/me/accounts/:provider` | Unlink a social account |
| `GET /api/me/link-token` | Generate a one-time token to link a social account from desktop |
| `GET /api/conversations` | List conversations |
| `POST /api/conversations` | Start a conversation |
| `GET /api/messages/:convId` | Fetch messages |
| `POST /api/messages/:convId` | Send a message |
| `POST /api/upload` | Upload an attachment |
| `GET /ws` | WebSocket endpoint |
