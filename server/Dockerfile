# syntax=docker/dockerfile:1

# TripSplit funding server — production image.
#
# Build:   docker build -t tripsplit-funding:prod server
# Run:     docker run --rm -p 8081:8080 \
#            -e PORT=8080 -e GATEWAY_MODE=razorpay -e FUNDING_ENV=production \
#            -e RAZORPAY_KEY_ID=... -e RAZORPAY_KEY_SECRET=... \
#            -e RAZORPAY_WEBHOOK_SECRET=... -e FUNDING_DB_PATH=/data/funding.sqlite3 \
#            tripsplit-funding:prod
#
# The sqlite3 package uses native-assets build hooks, so `dart compile exe` is
# unsupported. `dart build cli` produces the AOT bundle; the server dlopens the
# system libsqlite3 at runtime (installed below), so no SQLite is bundled.
# The sqlite3 hook is pinned to the system library in pubspec.yaml.
#
# Secrets are supplied exclusively through environment variables (Render env /
# Docker -e). Nothing here reads a `.env` file.

# ---- build: resolve dependencies and compile the server --------------------
FROM dart:stable AS build

WORKDIR /app

# Layered dependency resolution: this layer is cached until the lockfile
# changes. The sqlite3 hook resolves against the system library (source: system
# in pubspec.yaml), so no external SQLite download happens at build time.
COPY pubspec.yaml pubspec.lock ./

RUN dart pub get

COPY bin ./bin
COPY lib ./lib

RUN dart build cli -o /out

# ---- runtime: copy only the compiled bundle --------------------------------
FROM dart:stable AS runtime

WORKDIR /app

# The server dlopens libsqlite3.so at runtime (system sqlite, not bundled).
# libsqlite3-dev provides the linker symlink; ca-certificates are needed for
# outbound HTTPS to the Razorpay API.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libsqlite3-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /data

COPY --from=build /out/bundle ./

ENV PORT=8080
EXPOSE 8080

# Bind 0.0.0.0:$PORT (the server does this itself in bin/server.dart).
# Render injects PORT; graceful shutdown is handled via SIGTERM in the server.
CMD ["./bin/server"]