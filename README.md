# CS2 2D Demo Viewer – Docker Setup

Self-hosted Docker setup for [sparkoo/csgo-2d-demo-viewer](https://github.com/sparkoo/csgo-2d-demo-viewer),
adapted to work with your own (non-Faceit) demo sources, plus automatic
HTTPS via Caddy.

Builds the project from source on every deploy - no manual cloning, no
third-party Docker image. `docker compose up -d --build` is all it takes.

## What this does

- Clones `sparkoo/csgo-2d-demo-viewer` fresh from GitHub on every build
- Applies a small patch that allows additional (your own) demo hosts
- Builds the WASM parser (Go), the frontend (Preact/Vite), and the server (Go)
- Runs as a single container on port 8080 internally - no separate Nginx,
  the Go server itself serves the frontend and the download proxy
- Puts Caddy in front of it for automatic Let's Encrypt HTTPS - no manual
  certificate handling, no cron jobs

## Why the patch is needed

The original player is hardcoded to Faceit as the only demo source: the
built-in `/download` proxy only accepts two fixed Faceit Backblaze hosts and
rewrites the target URL to the fixed pattern
`https://<faceit-host>/cs2/<match-id>.dem.zst` - any other source gets
rejected with `403 forbidden host`.

The patch (`download-proxy-extra-hosts.patch`) adds a list of your own
hosts, configurable via the `EXTRA_ALLOWED_HOSTS` environment variable. For
those hosts, the original URL is passed through unchanged instead of being
forced into the Faceit pattern. The original Faceit behavior is left
untouched.

## Requirements

- Docker + Docker Compose
- Outbound internet access from the Docker build host (to clone the repo
  and download Go/npm dependencies)
- A DNS A record for your chosen subdomain pointing at the server's public
  IP (e.g. `cs2-demo.stinky-ol-looters.de -> 5.45.109.51`)
- Ports 80 and 443 reachable from the internet (needed for Caddy to issue
  the certificate)

## Setup

1. Put these four files in one folder:
   - `Dockerfile`
   - `docker-compose.yml`
   - `download-proxy-extra-hosts.patch`
   - `Caddyfile`

2. In `docker-compose.yml`, set your own demo host(s):

   ```yaml
   environment:
     - EXTRA_ALLOWED_HOSTS=demo.example.com,demo2.example.com
   ```

   Comma-separated, no `https://`, hostname only.

3. In `Caddyfile`, set your own domain:

   ```
   cs2-demo.stinky-ol-looters.de {
       reverse_proxy demo-viewer:8080
   }
   ```

4. Start it:

   ```bash
   docker compose up -d --build
   ```

   Caddy will automatically request and renew a Let's Encrypt certificate
   for the domain on first start - no extra steps.

5. The player is then reachable at
   `https://cs2-demo.stinky-ol-looters.de/`, with the demo URL passed via
   the `demourl` query parameter:

   ```
   https://cs2-demo.stinky-ol-looters.de/player?demourl=https://demo.example.com/path/to/demo.dem
   ```

## Important: your own download endpoint must be HTTPS

The proxy only accepts `https://` URLs as a source in production mode
(hardcoded, not part of the patch). Your own demo server must serve the
file over HTTPS.

## Troubleshooting

**Build fails with `mkdir /root/.docker: read-only file system` or
similar:** The Docker build is running through a deployment tool with
restricted filesystem access (e.g. systemd sandboxing with
`ProtectSystem=strict` / `ProtectHome=true`). The affected paths
(`/root/.docker`, `/tmp`) need to be explicitly allowed there
(`ReadWritePaths=`, `BindPaths=`) - specifics depend on the deployment tool.

**`403 forbidden host` despite setting `EXTRA_ALLOWED_HOSTS`:** Check that
the hostname matches exactly (no `https://`, no path, no trailing slash),
and that the container was rebuilt (not just restarted) after changing the
environment variable.

**WASM doesn't load / `importScripts` NetworkError in the worker:** Check
whether `wasm_exec.js` actually made it into the image:

```bash
docker exec <container> ls -la /app/web/dist/wasm/
```

If it's missing: rebuild the image (`docker compose build --no-cache`). The
Dockerfile includes a workaround for a path bug in the upstream Makefile
that otherwise leaves `wasm_exec.js` outside the expected directory.

**Caddy doesn't get a certificate:** Confirm the DNS A record for your
domain actually resolves to the server's public IP, and that ports 80/443
aren't blocked by a firewall or already in use by another service on the
host.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Multi-stage build: clone repo -> apply patch -> build WASM + server + frontend -> slim runtime image |
| `docker-compose.yml` | Starts the demo-viewer container plus Caddy, sets `EXTRA_ALLOWED_HOSTS` |
| `download-proxy-extra-hosts.patch` | Allows your own demo hosts in addition to Faceit |
| `Caddyfile` | Reverse proxy + automatic HTTPS for the demo-viewer container |

## Credits

Based on [sparkoo/csgo-2d-demo-viewer](https://github.com/sparkoo/csgo-2d-demo-viewer) (MIT License).
