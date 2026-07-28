# ---- Stage 1: build the static SPA ----
FROM node:22-alpine AS build
WORKDIR /app

# Install deps first for better layer caching.
COPY package.json package-lock.json* ./
RUN npm install

# Build. VITE_API_BASE_URL defaults to "/" so the SPA talks to the same ingress.
COPY . .
ARG VITE_API_BASE_URL=/
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
RUN npm run build

# ---- Stage 2: serve with nginx (non-root friendly) ----
FROM nginx:alpine AS runtime

# Pull every available Alpine security patch on top of the base. The official
# nginx:alpine tag occasionally lags behind Alpine's package repos for a day or
# two after a CVE fix lands (e.g. libxml2 CVE-2026-6732 — fix is in r1, image
# ships r0). `apk upgrade` reconciles the layer at build time so Trivy sees
# the patched versions.
RUN apk update && apk upgrade --no-cache && rm -rf /var/cache/apk/*

# Custom SPA config (try_files fallback to index.html).
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Static assets from the build stage.
COPY --from=build /app/dist /usr/share/nginx/html

# Make the paths nginx writes to writable by arbitrary (non-root) UIDs so the
# container can run with `--user` / a restricted securityContext.
RUN touch /var/run/nginx.pid \
    && chown -R nginx:nginx /var/cache/nginx /var/run/nginx.pid /usr/share/nginx/html \
    && chmod -R g+rwX /var/cache/nginx /var/run/nginx.pid

USER nginx

# Non-root nginx serves on 8080 (see nginx.conf); a Service/ingress maps :80 -> :8080.
EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
