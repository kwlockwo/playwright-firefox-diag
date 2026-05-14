# ─────────────────────────────────────────────────────────────────────────────
# Camoufox 0.1.19 — /dev/shm newPage() diagnostic
#
# Self-contained: only this file + docker-compose.yml are needed.
#
# Build:  docker compose build
# Run:    docker compose run --rm diag-default-shm   (64 MB — reproduce hang)
#         docker compose run --rm diag-large-shm     (256 MB — confirm fix)
# ─────────────────────────────────────────────────────────────────────────────

FROM node:20-bookworm-slim

# ── system dependencies required by Firefox / Playwright ─────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core Firefox runtime libs
    libgtk-3-0 \
    libdbus-glib-1-2 \
    libxt6 \
    libpulse0 \
    # Font rendering
    fonts-liberation \
    fonts-noto-color-emoji \
    # For diagnostic /dev/shm readout
    procps \
    # Download tools
    ca-certificates \
    curl \
    unzip \
    xvfb \
 && rm -rf /var/lib/apt/lists/*

# ── Render SSH / shell access (Docker-specific requirements) ──────────────────
# https://docs.render.com/ssh#docker-specific-configuration
# 1. ~/.ssh must exist with chmod 0700
# 2. Root account must not be locked (node:20-bookworm-slim locks it by default)
RUN mkdir -p /root/.ssh && chmod 0700 /root/.ssh \
 && passwd -u root || usermod --unlock root || true

WORKDIR /app

# ── package.json (inline — no external files needed) ─────────────────────────
RUN cat > package.json <<'EOF'
{
  "name": "camoufox-shm-diag",
  "version": "1.0.0",
  "description": "Camoufox 0.1.19 /dev/shm newPage() hang diagnostic",
  "main": "shm-diag.js",
  "dependencies": {
    "camoufox": "0.1.19"
  },
  "engines": { "node": ">=18" }
}
EOF

# ── node deps ─────────────────────────────────────────────────────────────────
RUN npm install --omit=dev

# ── Camoufox browser binary (direct download — no GitHub API, no token) ──────
# Iterates releases API to find latest in range >=beta.19, <1.
# We hardcode the result to avoid the API call entirely.
# Note: release tag is v150.0.2-beta.25 but the asset filename uses alpha.25 —
# that is how upstream published it.
#
# To update: run this snippet and replace the URL below with the result:
#   curl -s https://api.github.com/repos/daijro/camoufox/releases \
#   | node -e "
#       const r = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
#       const pat = /camoufox-(.+)-(.+)-lin\.x86_64\.zip/;
#       for (const rel of r) {
#         const a = rel.assets.find(a => pat.test(a.name));
#         if (a) { console.log(a.browser_download_url); break; }
#       }
#     "
RUN curl -fsSL \
    https://github.com/daijro/camoufox/releases/download/v150.0.2-beta.25/camoufox-150.0.2-alpha.26-lin.x86_64.zip \
    -o /tmp/camoufox.zip \
 && mkdir -p /root/.cache/camoufox \
 && unzip -q /tmp/camoufox.zip -d /root/.cache/camoufox \
 && rm /tmp/camoufox.zip

# ── diagnostic script ─────────────────────────────────────────────────────────
COPY shm-diag.js ./

# ── /dev/shm snapshot at startup ─────────────────────────────────────────────
CMD ["/bin/sh", "-c", "\
  echo ''; \
  echo '=== /dev/shm at container startup ==='; \
  df -h /dev/shm 2>/dev/null || echo '  /dev/shm not present'; \
  echo '====================================='; \
  echo ''; \
  exec node shm-diag.js \
"]
