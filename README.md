# Mednean Flutter Web deployment

This repository is the server-side deployment project. It runs an Nginx static-file server behind `nginxproxy/nginx-proxy` and `nginxproxy/acme-companion` for HTTPS certificates. Flutter Web is built by the main application/CI and copied into `web/`; it is not built in this Compose project.

## First setup

1. Clone this repository onto the server, e.g. `git clone https://github.com/nananaseek/flutter-deploy.git "$DEPLOY_PATH"`.
2. Copy `.env.example` to `.env` and set `DOMAIN` and `LETSENCRYPT_EMAIL` to the production hostname and certificate contact. The included defaults were copied from `rust-flutter-server`; verify them before production.
3. Make sure the domain's public DNS A/AAAA records point to this server and inbound TCP ports 80 and 443 are reachable. If the server should not serve IPv6, disable `ENABLE_IPV6` in `docker-compose.yml` and ensure no stale AAAA record remains.
4. Build the Flutter web release in the main project and publish all contents of `build/web/` into this directory's `web/`. A valid `web/index.html` must exist before starting the site.
5. Run `docker compose config -q` and then `docker compose up -d`. Check `docker compose ps` and `docker compose logs -f nginx-proxy acme-companion web`.

The `vhost.d` file is named for the default hostname. If `DOMAIN` changes, rename `vhost.d/app.hideinbasement.xyz` to `vhost.d/<DOMAIN>` and update the app/API origins in its CSP and Permissions-Policy. The Rust server's CORS policy was intentionally not copied: static files are same-origin, while cross-origin API responses must be allowed by the API server itself. Keep the policy in step with LiqPay, Apple Pay, Google Fonts/CanvasKit, and API integrations in the Flutter app. The CSP/security configuration was carried over from `rust-flutter-server`'s Rust middleware and Nginx vhost; Apple Pay authorization still depends on the payment integration, domain verification, HTTPS, and browser/device support as well as these headers.

## Updating a release

Build on CI, for example:

```sh
flutter build web --release
```

Upload the complete `build/web/` output to the server's deployment `web/` directory, then run:

```sh
docker compose restart web
```

Prefer staging the upload into a temporary sibling directory and atomically swapping it into place, or otherwise ensure the deployment does not expose a mixed old/new set of files. `rsync --delete` to the live folder can briefly serve an incomplete build. Do not delete old content-addressed assets while clients may still have an older `index.html` open.

The Nginx config sends `no-cache, no-store, must-revalidate` for the app entrypoint, bootstrap/runtime scripts, `main.dart.js`, Flutter service worker, version and manifests; other Flutter static assets are revalidated with `no-cache, must-revalidate` because their paths are generally not content-hashed. Flutter's generated service worker participates in browser-side updates; users may still need a page reload, and an already open tab will not become a new release without app-side update handling. `.wasm` files get `application/wasm` MIME. Missing real files return 404 instead of silently falling back to `index.html`; SPA routes fall back to the entrypoint.

## GitHub Actions CI/CD

The main repository workflow is [`deploy-web.yml`](https://github.com/HideAndFish/MedneanFront/blob/main/.github/workflows/deploy-web.yml). A push to `main` runs Flutter tests and builds the release; a manual `workflow_dispatch` run is also available. It uploads into a per-commit staging directory over SSH, swaps the complete `web/` release, recreates the web container, waits for its health check, and restores the previous release if activation fails. A concurrency group prevents two production deployments from swapping files simultaneously.

Configure these GitHub Actions repository **Secrets** before enabling deployment:

| Secret | Value |
| --- | --- |
| `DEPLOY_HOST` | Public SSH hostname or IP of the deployment server |
| `DEPLOY_USER` | SSH account allowed to write the deployment directory and run `docker compose` |
| `DEPLOY_SSH_KEY` | Private key for that account (public key installed in `authorized_keys`) |
| `DEPLOY_KNOWN_HOSTS` | Pinned known-hosts line(s), collected and verified out-of-band; do not disable host-key checking |

Configure these Actions repository **Variables**:

| Variable | Value |
| --- | --- |
| `DEPLOY_PATH` | Absolute path to this deployment project on the server (contains `docker-compose.yml` and `.env`) |
| `DEPLOY_PORT` | Optional SSH port; defaults to `22` |
| `API_BASE_URL` | Optional API URL embedded from `.env` during build; defaults to `https://api.hideinbasement.xyz:8078` |

Prepare the server once: install Docker Engine + Compose plugin; clone this repository to the path in `DEPLOY_PATH`; create its `.env` from `.env.example`; confirm the SSH user can run Docker without an interactive password prompt and has write permission to the project directory. Start the stack once after DNS/ports are ready (`docker compose up -d`) so proxy and ACME are initialized. The workflow does not copy or replace server secrets/certificates.

`rsync` on the server is optional: the workflow probes for it over SSH and falls back to `scp` when it is missing. Because `scp` has no `--delete`, the staging directory is recreated before every upload in both modes, so switching transports never leaves stale files behind.

The CI build writes root `.env` from `API_BASE_URL`, because the app loads that file at startup and packages it as a Flutter asset. Keep production API configuration in GitHub Variables, not in committed files. The server's deployment `.env` is separate and configures the Compose `DOMAIN` and `LETSENCRYPT_EMAIL`.

The deployment uses directory renames and Docker Compose on the server, so staging and `web/` must be on the same filesystem. The SSH account is effectively privileged: membership in the Docker group usually grants root-equivalent host control. Use a dedicated key/account and restrict access as appropriate.

## Useful checks

```sh
docker compose config -q
docker compose ps
curl -fsS -H 'Host: app.hideinbasement.xyz' http://127.0.0.1/health
curl -sSI -H 'Host: app.hideinbasement.xyz' http://127.0.0.1/some/flutter/route
curl -sSI -H 'Host: app.hideinbasement.xyz' http://127.0.0.1/main.dart.js
```

`nginx-proxy` and ACME need Docker socket access. Mounting the Docker socket grants powerful control over the host; use this stack only on a trusted deployment server. Certificate issuance requires public DNS and reachable HTTP-01 challenge paths.
