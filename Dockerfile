# ─────────────────────────────────────────────────────────────────────────────
# Camoufox 0.1.19 — /dev/shm newPage() diagnostic
#
# Build:
#   docker compose build
#
# Run (default 64 MB /dev/shm — likely to reproduce the hang):
#   docker compose run diag-default-shm
#
# Run (256 MB /dev/shm — should fix the hang):
#   docker compose run diag-large-shm
# ─────────────────────────────────────────────────────────────────────────────

FROM node:20-bookworm-slim

# ── system dependencies required by Firefox / Playwright ─────────────────────
# Sourced from: https://playwright.dev/docs/docker
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core Firefox runtime libs
    libgtk-3-0 \
    libdbus-glib-1-2 \
    libxt6 \
    # Audio (Firefox still links against it even headless)
    libpulse0 \
    # Font rendering
    fonts-liberation \
    fonts-noto-color-emoji \
    # Shared memory / IPC helpers (for diagnostic readout)
    procps \
    # Misc runtime
    ca-certificates \
    wget \
    xvfb \
 && rm -rf /var/lib/apt/lists/*

# ── Render SSH / shell access (Docker-specific requirements) ──────────────────
# https://docs.render.com/ssh#docker-specific-configuration
# 1. ~/.ssh must exist with chmod 0700
# 2. Root account must not be locked (node:20-bookworm-slim locks it by default)
RUN mkdir -p /root/.ssh && chmod 0700 /root/.ssh \
 && passwd -u root || usermod --unlock root || true

WORKDIR /app

# ── node deps first (layer-cache friendly) ────────────────────────────────────
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

# ── install the Firefox binary that Camoufox/Playwright will use ──────────────
#
# Camoufox 0.1.19 bundles a patched Firefox and downloads it on first run via
# its own fetcher.  We pre-seed the download here so the container is self-
# contained and the diagnostic doesn't spend time downloading at runtime.
#
# PLAYWRIGHT_BROWSERS_PATH lets both Playwright and Camoufox find the binary
# in a predictable, layer-cached location.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

RUN npx playwright install firefox \
 && npx playwright install-deps firefox

# ── pre-seed Camoufox binary ──────────────────────────────────────────────────
# Without this, Camoufox throws "not installed" at runtime and prompts the user
# to run `camoufox fetch` manually.  Baking it in at build time avoids the
# download happening inside the container on Render.
RUN npx camoufox fetch

# ── diagnostic script ─────────────────────────────────────────────────────────
COPY shm-diag.js ./

# ── /dev/shm snapshot at startup (diagnostic aid) ─────────────────────────────
# Printed before the Node process starts so it's visible regardless of hang.
CMD ["/bin/sh", "-c", "\
  echo ''; \
  echo '=== /dev/shm at container startup ==='; \
  df -h /dev/shm 2>/dev/null || echo '  /dev/shm not present'; \
  echo '====================================='; \
  echo ''; \
  exec node shm-diag.js \
"]
