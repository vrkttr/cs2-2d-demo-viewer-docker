# ============================================================
# CS2 2D Demo Viewer
#
# The actual project is cloned automatically from GitHub
# during the Docker build.
# ============================================================

ARG REPO_URL=https://github.com/sparkoo/csgo-2d-demo-viewer.git
ARG REPO_BRANCH=dev


# ============================================================
# Stage 1: Clone source
# ============================================================

FROM alpine:latest AS source

ARG REPO_URL
ARG REPO_BRANCH

RUN apk add --no-cache git

WORKDIR /src

RUN git clone \
    --depth 1 \
    --branch "${REPO_BRANCH}" \
    "${REPO_URL}" .


# ============================================================
# Stage 2: Build WASM parser
# ============================================================

FROM golang:1.25 AS wasm-builder

WORKDIR /src

COPY --from=source /src .

RUN mkdir -p web/public/wasm

RUN cd parser && \
    GOOS=js GOARCH=wasm \
    go build \
    -ldflags="-s -w" \
    -o ../web/public/wasm/csdemoparser.wasm \
    ./wasm.go

RUN cp "$(go env GOROOT)/lib/wasm/wasm_exec.js" \
    web/public/wasm/wasm_exec.js


# ============================================================
# Stage 3: Build frontend
# ============================================================

FROM node:22-alpine AS web-builder

WORKDIR /src

COPY --from=wasm-builder /src .

WORKDIR /src/web

RUN npm ci

RUN npm run build


# ============================================================
# Stage 4: Build Go server
# ============================================================

FROM golang:1.25 AS server-builder

WORKDIR /src

COPY --from=web-builder /src .

WORKDIR /src/server

RUN go mod download

RUN CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    go build \
    -ldflags="-s -w" \
    -o /server


# ============================================================
# Stage 5: Runtime
# ============================================================

FROM alpine:latest

RUN apk add --no-cache ca-certificates

WORKDIR /app

COPY --from=server-builder /server ./server

COPY --from=web-builder /src/web/dist ./web/dist

EXPOSE 8080

CMD ["./server"]
