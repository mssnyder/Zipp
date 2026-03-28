# Zipp

Private end-to-end encrypted messaging platform with a Node.js/Fastify backend and a Flutter client (web, desktop, mobile).

## Project structure

```
server/     Node.js backend (Fastify, Prisma, PostgreSQL)
client/     Flutter client (web, Linux desktop, Android)
nix/        Nix packaging & NixOS module
```

## NixOS deployment

Zipp is packaged as a Nix flake.  Add it as an input to your NixOS config:

```nix
# flake.nix
inputs.zipp = {
  url = "github:SinisterSwiss/Zipp";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### Server module

Import the NixOS module and configure the service:

```nix
# In your modules list:
zipp.nixosModules.default

# In a module file:
services.zipp = {
  enable    = true;
  domain    = "messaging.example.com";
  user      = "myuser";
  acmeEmail = "admin@example.com";

  settings = {
    serverUrl    = "https://messaging.example.com";
    allowSignups = true;

    smtp = {
      host = "smtp.gmail.com";
      user = "you@gmail.com";
      from = "Zipp <noreply@example.com>";
    };
  };

  # Secrets via sops-nix (recommended):
  secrets.databaseUrlFile      = config.sops.secrets."zipp/databaseUrl".path;
  secrets.sessionSecretFile    = config.sops.secrets."zipp/sessionSecret".path;
  secrets.argon2PepperFile     = config.sops.secrets."zipp/argon2Pepper".path;
  secrets.googleClientIdFile   = config.sops.secrets."zipp/googleClientId".path;
  secrets.googleClientSecretFile = config.sops.secrets."zipp/googleClientSecret".path;
  secrets.smtpPassFile         = config.sops.secrets."zipp/smtpPass".path;

  # Or set secrets directly (ends up in the Nix store -- fine for testing):
  # secrets.sessionSecret = "my-dev-secret-at-least-32-characters";
};
```

The module sets up:
- A rootless systemd user service running the Node.js server
- Nginx reverse proxy with SSL (ACME/Let's Encrypt)
- Data directories under `/var/lib/zipp/`

All available options are documented in [nix/module.nix](nix/module.nix).

### Desktop client

The client is a pre-built Flutter Linux desktop app.  Build it, then install via your home-manager config:

```bash
cd client
nix develop        # enter the Flutter dev shell
flutter build linux --release
./deploy-linux.sh  # copies bundle to client/bundle/
```

Then in your NixOS config:

```nix
home.packages = [
  (pkgs.callPackage "${inputs.zipp}/nix/client.nix" {
    serverUrl = "https://messaging.example.com";
  })
];
```

The `serverUrl` is injected as the `ZIPP_SERVER_URL` environment variable at runtime.

### Web client

Build and deploy the Flutter web app:

```bash
cd client
nix develop
flutter build web --release
```

Copy `client/build/web/` to your web root (default: `/var/lib/zipp/web/`).

## Development

Each subdirectory has its own dev shell:

```bash
cd server && nix develop    # Node.js 24 + Prisma engines
cd client && nix develop    # Flutter + Android SDK + desktop deps
```

See [server/README.md](server/README.md) for backend setup details.

## License

All Rights Reserved
