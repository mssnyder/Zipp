# NixOS module for the Zipp messaging server + nginx reverse proxy.
#
# Usage:
#
#   services.zipp = {
#     enable    = true;
#     domain    = "messaging.example.com";
#     user      = "myuser";
#     acmeEmail = "admin@example.com";
#
#     settings = {
#       serverUrl    = "https://messaging.example.com";
#       allowSignups = true;
#       smtp.host    = "smtp.gmail.com";
#       smtp.user    = "you@gmail.com";
#       smtp.from    = "Zipp <noreply@example.com>";
#     };
#
#     # Secrets via sops-nix (recommended):
#     secrets.databaseUrlFile      = config.sops.secrets."zipp/databaseUrl".path;
#     secrets.sessionSecretFile    = config.sops.secrets."zipp/sessionSecret".path;
#     secrets.argon2PepperFile     = config.sops.secrets."zipp/argon2Pepper".path;
#
#     # Or set secrets directly (ends up in the Nix store — fine for testing):
#     secrets.sessionSecret = "my-dev-secret-min-32-chars-long!!";
#   };
{ zipp-server, zipp-web }:

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.zipp;

  # For each secret, prefer the *File variant (read at runtime, never
  # touches the Nix store) over the direct value.  The startup wrapper
  # script cats each file or falls back to the literal.
  secretExport = envName: directVal: filePath:
    if filePath != null then
      ''export ${envName}="$(cat '${filePath}')"''
    else if directVal != null then
      ''export ${envName}=${lib.escapeShellArg directVal}''
    else
      "";

  startupScript = pkgs.writeShellScript "zipp-start" ''
    # ── Non-sensitive settings ──────────────────────────────────────
    export NODE_ENV=${lib.escapeShellArg cfg.settings.nodeEnv}
    export PORT=${toString cfg.settings.port}
    export DATA_DIR=${lib.escapeShellArg cfg.dataDir}
    export SERVER_URL=${lib.escapeShellArg cfg.settings.serverUrl}
    export FRONTEND_URL=${lib.escapeShellArg cfg.settings.frontendUrl}
    export ALLOW_SIGNUPS=${lib.boolToString cfg.settings.allowSignups}
    export LOG_LEVEL=${lib.escapeShellArg cfg.settings.logLevel}
    export SESSION_LENGTH=${lib.escapeShellArg cfg.settings.sessionLength}
    export ARGON2_MEMORY_MB=${toString cfg.settings.argon2.memoryMb}
    export ARGON2_TIME=${toString cfg.settings.argon2.time}
    export ARGON2_PARALLELISM=${toString cfg.settings.argon2.parallelism}
    export ARGON2_HASH_LEN=${toString cfg.settings.argon2.hashLen}
    ${lib.optionalString (cfg.settings.smtp.host != null) ''
    export SMTP_HOST=${lib.escapeShellArg cfg.settings.smtp.host}
    export SMTP_PORT=${toString cfg.settings.smtp.port}
    export SMTP_FROM=${lib.escapeShellArg cfg.settings.smtp.from}
    ''}
    ${lib.optionalString (cfg.settings.smtp.user != null) ''
    export SMTP_USER=${lib.escapeShellArg cfg.settings.smtp.user}
    ''}

    # ── Secrets (read from files at runtime) ────────────────────────
    ${secretExport "DATABASE_URL" cfg.secrets.databaseUrl cfg.secrets.databaseUrlFile}
    ${secretExport "SESSION_SECRET" cfg.secrets.sessionSecret cfg.secrets.sessionSecretFile}
    ${secretExport "ARGON2_PEPPER" cfg.secrets.argon2Pepper cfg.secrets.argon2PepperFile}
    ${secretExport "SMTP_PASS" cfg.secrets.smtpPass cfg.secrets.smtpPassFile}
    ${secretExport "GOOGLE_CLIENT_ID" cfg.secrets.googleClientId cfg.secrets.googleClientIdFile}
    ${secretExport "GOOGLE_CLIENT_SECRET" cfg.secrets.googleClientSecret cfg.secrets.googleClientSecretFile}
    ${secretExport "KLIPY_API_KEY" cfg.secrets.klipyApiKey cfg.secrets.klipyApiKeyFile}

    exec ${zipp-server}/bin/zipp-server "$@"
  '';
in
{
  options.services.zipp = {
    enable = lib.mkEnableOption "Zipp messaging server";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "FQDN for the nginx virtual host (e.g. messaging.example.com).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "zipp";
      description = "System user that runs the Zipp server. Created automatically if it does not exist.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/zipp";
      description = "Directory for uploads, logs, and web assets.";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Email address for ACME / Let's Encrypt certificate issuance.";
    };

    # ── Non-sensitive settings ────────────────────────────────────────
    settings = {
      serverUrl = lib.mkOption {
        type = lib.types.str;
        description = "Public URL of the server (e.g. https://messaging.example.com).";
      };

      frontendUrl = lib.mkOption {
        type = lib.types.str;
        default = cfg.settings.serverUrl;
        defaultText = lib.literalExpression "config.services.zipp.settings.serverUrl";
        description = "Public URL of the frontend.  Defaults to serverUrl.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 4200;
        description = "Port the Node.js server listens on.";
      };

      nodeEnv = lib.mkOption {
        type = lib.types.str;
        default = "production";
        description = "NODE_ENV value.";
      };

      logLevel = lib.mkOption {
        type = lib.types.str;
        default = "info";
        description = "Pino log level.";
      };

      allowSignups = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to allow new user registration.";
      };

      sessionLength = lib.mkOption {
        type = lib.types.str;
        default = "30d";
        description = "Session cookie lifetime (ms-style, e.g. 30d, 12h).";
      };

      argon2 = {
        memoryMb = lib.mkOption {
          type = lib.types.int;
          default = 128;
          description = "Argon2id memory cost in MiB.";
        };
        time = lib.mkOption {
          type = lib.types.int;
          default = 3;
          description = "Argon2id time cost (iterations).";
        };
        parallelism = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Argon2id parallelism factor.";
        };
        hashLen = lib.mkOption {
          type = lib.types.int;
          default = 32;
          description = "Argon2id hash length in bytes.";
        };
      };

      smtp = {
        host = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "SMTP server hostname.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 587;
          description = "SMTP server port.";
        };
        user = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "SMTP username.";
        };
        from = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "SMTP From header value.";
        };
      };
    };

    # ── Secrets ───────────────────────────────────────────────────────
    # Each secret has two options: a direct string value and a file path.
    # File-based (*File) options are preferred for production — the value
    # is read at service startup and never enters the Nix store.
    # If both are set, the file takes precedence.
    secrets = {
      databaseUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "PostgreSQL connection URL.  Prefer databaseUrlFile.";
      };
      databaseUrlFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing DATABASE_URL (e.g. sops secret path).";
      };

      sessionSecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Session signing secret (min 32 chars).  Prefer sessionSecretFile.";
      };
      sessionSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing SESSION_SECRET.";
      };

      argon2Pepper = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Argon2 pepper string.  Prefer argon2PepperFile.";
      };
      argon2PepperFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing ARGON2_PEPPER.";
      };

      smtpPass = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SMTP password.  Prefer smtpPassFile.";
      };
      smtpPassFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing SMTP_PASS.";
      };

      googleClientId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Google OAuth client ID.  Prefer googleClientIdFile.";
      };
      googleClientIdFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing GOOGLE_CLIENT_ID.";
      };

      googleClientSecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Google OAuth client secret.  Prefer googleClientSecretFile.";
      };
      googleClientSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing GOOGLE_CLIENT_SECRET.";
      };

      klipyApiKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Klipy API key.  Prefer klipyApiKeyFile.";
      };
      klipyApiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing KLIPY_API_KEY.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Data directories ──────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}                    0751 ${cfg.user} ${cfg.user} -"
      "d ${cfg.dataDir}/uploads            0750 ${cfg.user} ${cfg.user} -"
      "d ${cfg.dataDir}/uploads/attachments 0750 ${cfg.user} ${cfg.user} -"
      "d ${cfg.dataDir}/uploads/thumbs     0750 ${cfg.user} ${cfg.user} -"
      "d ${cfg.dataDir}/uploads/avatars    0750 ${cfg.user} ${cfg.user} -"
      "d ${cfg.dataDir}/logs               0750 ${cfg.user} ${cfg.user} -"
    ];

    # ── Systemd system service ────────────────────────────────────────
    systemd.services.zipp = {
      description = "Zipp Messaging Server";
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.user;
        WorkingDirectory = "${zipp-server}/lib/node_modules/zipp-server";
        ExecStart = "${startupScript}";
        ReadWritePaths = [ cfg.dataDir ];
        Restart = "on-failure";
        RestartSec = "5s";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # ── Nginx reverse proxy ───────────────────────────────────────────
    services.nginx.virtualHosts."${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      extraConfig = ''
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-Frame-Options SAMEORIGIN always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        client_max_body_size 2048M;

        proxy_buffering off;
        proxy_request_buffering off;
      '';

      locations = {
        "/api/auth/login" = {
          proxyPass = "http://127.0.0.1:${toString cfg.settings.port}";
          extraConfig = ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Real-IP $remote_addr;
            limit_req zone=perip burst=10 nodelay;
          '';
        };
        "/api/auth/register" = {
          proxyPass = "http://127.0.0.1:${toString cfg.settings.port}";
          extraConfig = ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Real-IP $remote_addr;
            limit_req zone=perip burst=10 nodelay;
          '';
        };

        "~ ^/api" = {
          proxyPass = "http://127.0.0.1:${toString cfg.settings.port}";
          extraConfig = ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Real-IP $remote_addr;
            limit_req zone=perip burst=80 nodelay;
          '';
        };

        "/ws" = {
          proxyPass = "http://127.0.0.1:${toString cfg.settings.port}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_read_timeout 86400;
            proxy_send_timeout 86400;
          '';
        };

        "/uploads/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.settings.port}";
          extraConfig = ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Real-IP $remote_addr;
          '';
        };

        "/connect/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.settings.port}";
          extraConfig = ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Real-IP $remote_addr;
          '';
        };

        "/" = {
          root = "${zipp-web}";
          tryFiles = "$uri /index.html";
        };
      };
    };

    # ── Dedicated service user ────────────────────────────────────────
    users.users.${cfg.user} = lib.mkIf (cfg.user == "zipp") {
      isSystemUser = true;
      group = cfg.user;
      home = cfg.dataDir;
      description = "Zipp messaging server";
    };
    users.groups.${cfg.user} = lib.mkIf (cfg.user == "zipp") {};

    # ── ACME / Let's Encrypt ──────────────────────────────────────────
    security.acme = {
      acceptTerms = true;
      certs."${cfg.domain}" = {
        email = cfg.acmeEmail;
      };
    };

    environment.systemPackages = [ pkgs.ffmpeg-full ];
  };
}
