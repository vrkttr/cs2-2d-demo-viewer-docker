# ==========================================================================
# Stage 1: Quellcode klonen + Patch anwenden
# ==========================================================================
FROM alpine/git AS source

WORKDIR /src
RUN git clone --depth 1 https://github.com/sparkoo/csgo-2d-demo-viewer.git .

COPY download-proxy-extra-hosts.patch .
RUN apk add --no-cache patch \
    && patch -p1 < download-proxy-extra-hosts.patch


# ==========================================================================
# Stage 2: WASM-Parser + Server-Binary bauen (Go)
# ==========================================================================
FROM golang:1.25 AS go-builder

WORKDIR /src
COPY --from=source /src .

# Erzeugt web/public/wasm/csdemoparser.wasm + wasm_exec.js,
# genau wie im README dokumentiert (von Repo-Root aus).
RUN make wasm

# Workaround fuer einen Pfad-Bug im Makefile: "cp ... ../web/public/wasm/wasm_exec.js"
# laeuft ohne das "-C ./parser", das der go-build-Aufruf davor nutzt, und landet
# dadurch ausserhalb des Repos statt in web/public/wasm/. Datei hier an die
# richtige Stelle kopieren.
RUN cp "$(go env GOROOT)/lib/wasm/wasm_exec.js" web/public/wasm/wasm_exec.js

# Server-Binary bauen
RUN cd server && go build -ldflags="-s -w" -o /out/server-bin .


# ==========================================================================
# Stage 3: Frontend bauen (Preact/Vite) - braucht die WASM-Dateien aus Stage 2
# ==========================================================================
FROM node:20 AS web-builder

WORKDIR /src
COPY --from=go-builder /src .

# VITE_DOWNLOAD_SERVER_URL bewusst leer: Server liefert Frontend + /download
# selbst aus (siehe main.go), damit ist alles same-origin -> relative URLs.
RUN npm --prefix web install
RUN npm --prefix web run build


# ==========================================================================
# Stage 4: Laufzeit-Image - nur die Server-Binary + das gebaute Frontend
# ==========================================================================
FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# main.go erwartet web/dist unter "../web/dist" relativ zum Arbeitsverzeichnis
# der Binary -> Layout: /app/server/server-bin und /app/web/dist
WORKDIR /app/server
COPY --from=go-builder /out/server-bin ./server-bin
COPY --from=web-builder /src/web/dist ../web/dist

EXPOSE 8080

ENV EXTRA_ALLOWED_HOSTS=""

CMD ["./server-bin"]
