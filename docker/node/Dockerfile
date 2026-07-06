# Multi-stage build for the SvelteKit administration panel.
#
#   dev  (default) — Vite dev server with HMR; source is bind-mounted by
#                    docker-compose, so this is what `docker compose up` builds.
#   prod           — the static bundle (adapter-static) served by Caddy, which
#                    also proxies /api, /ws, /sse and /chat to the backend
#                    services (same-origin, replacing the Vite dev proxy).
#                    Selected by docker-compose.prod.yml via `build.target: prod`.

# ---------------------------------------------------------------------------
# Dependencies (shared by dev + build).
# ---------------------------------------------------------------------------
FROM node:22-alpine AS deps
RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app
COPY administration/package.json administration/pnpm-lock.yaml administration/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

# ---------------------------------------------------------------------------
# Build the static bundle. The runtime endpoints are same-origin and served /
# proxied by the prod Caddy below, so they are baked as relative URLs.
# ---------------------------------------------------------------------------
FROM deps AS build
ENV VITE_API_HOST=""
ENV VITE_WS_URL="/ws"
COPY administration/ .
RUN pnpm build

# ---------------------------------------------------------------------------
# Production image: Caddy serving the SPA + proxying API/WS to the services.
# ---------------------------------------------------------------------------
FROM caddy:2-alpine AS prod
COPY docker/node/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/build /srv
EXPOSE 3000

# ---------------------------------------------------------------------------
# Development image (default target).
# ---------------------------------------------------------------------------
FROM deps AS dev
COPY administration/ .
EXPOSE 3000
CMD ["pnpm", "dev", "--host"]
