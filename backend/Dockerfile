# ── Stage 1: install dependencies ──────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN npm install --production

# ── Stage 2: final image ────────────────────────────────────────
FROM node:20-alpine
WORKDIR /app

# Copy installed packages from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy source code
COPY server.js .

# Run as non-root user (security best practice)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 3000

# Liveness probe: GET /health
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "server.js"]
