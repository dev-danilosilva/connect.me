# Deployment

This project ships two separate Docker setups: one for local development and one for production. They deliberately don't share a compose file — the dev setup optimizes for fast iteration, the prod setup for security and reliability.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Dev image. Installs deps, no build optimizations. |
| `docker-compose.yml` | Dev stack: `web` (bind-mounted source, `runserver`, auto-reload) + `db`. |
| `Dockerfile.prod` | Multi-stage prod image. Compiles the Elm page editor with `--optimize` in a Node stage (the bundle isn't in git, so every build compiles it), then a final image with no compilers/dev headers, run as a non-root user, with `collectstatic` output baked in, served via Gunicorn. |
| `docker-compose.prod.yml` | Prod stack: `db` + `web` (Gunicorn, no ports exposed to the host) + `nginx` (reverse proxy + TLS termination) + `certbot` (auto-renewal). |
| `nginx.conf.template` | nginx config, templated with `${DOMAIN}` at container start. |
| `init-letsencrypt.sh` | One-time script to bootstrap Let's Encrypt certificates. |
| `.env.example` | Reference for every environment variable used by both stacks. |
| `k8s/linktree.yaml` | Kubernetes manifest: Postgres (Deployment + PVC) and the app pod (Gunicorn + nginx sidecar serving `/static/`). Generated with `podman kube generate`, then hand-edited. |

## Local development

```bash
cp .env.example .env   # defaults work out of the box for local dev
docker compose up --build
```

- App: http://localhost:8000
- Postgres: exposed on `localhost:5432` for connecting with a local client
- Source is bind-mounted into the container — edits to the code are picked up immediately by `runserver`, no rebuild needed (only rebuild after changing `requirements.txt`)
- `runserver` also compiles the Elm page editor in debug mode and recompiles it on every change to `elm/` (the image ships the `elm` binary); this needs `DEBUG=True` in `.env`
- Migrations run automatically on container start

## Production

### Prerequisites

- A server with Docker and Docker Compose installed
- A domain name with its DNS A/AAAA record already pointing at the server's public IP
- Ports 80 and 443 open to the internet

### 1. Configure environment

```bash
cp .env.example .env
```

Set at minimum:

- `SECRET_KEY` — a real, unique secret (do not reuse the dev default)
- `DEBUG=False`
- `ALLOWED_HOSTS` — your domain(s), comma-separated (e.g. `example.com,www.example.com`)
- `CSRF_TRUSTED_ORIGINS` — the full origin(s) with scheme, comma-separated (e.g. `https://example.com`)
- `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` — real credentials, not the dev defaults
- `DOMAIN` — the domain nginx and certbot will serve/request a certificate for
- `LETSENCRYPT_EMAIL` — email used for Let's Encrypt expiry notices

### 2. Bootstrap the TLS certificate (one-time)

```bash
./init-letsencrypt.sh
```

This script:
1. Generates a throwaway self-signed certificate so nginx has something to load and can start.
2. Starts the `nginx` service.
3. Deletes the dummy certificate.
4. Requests a real certificate from Let's Encrypt via the HTTP-01 webroot challenge (served by nginx on port 80).
5. Reloads nginx with the real certificate.

Consider testing against Let's Encrypt's staging environment first (add `--staging` to the `certbot certonly` call in the script) to avoid hitting production rate limits while debugging DNS/firewall issues.

### 3. Start the stack

```bash
docker compose -f docker-compose.prod.yml up -d --build
```

This brings up `db`, `web` (migrations run automatically on start, static files are already baked into the image via `collectstatic`), `nginx`, and `certbot` (which renews the certificate automatically every 12 hours when needed).

### Common operations

```bash
# View logs
docker compose -f docker-compose.prod.yml logs -f web

# Create an admin user
docker compose -f docker-compose.prod.yml exec web python manage.py createsuperuser

# Run a Django management command
docker compose -f docker-compose.prod.yml exec web python manage.py <command>

# Restart after pulling new code
docker compose -f docker-compose.prod.yml up -d --build

# Force a certificate renewal check manually
docker compose -f docker-compose.prod.yml exec certbot certbot renew
docker compose -f docker-compose.prod.yml exec nginx nginx -s reload
```

## Kubernetes

`k8s/linktree.yaml` runs the same production image on a cluster:

- `linktree-db`: Postgres 16 with a 5Gi PVC, exposed in-cluster on the `linktree-db` Service.
- `linktree-web`: an init container copies the image's baked-in `collectstatic` output into an `emptyDir`; nginx (config in the `linktree-nginx` ConfigMap) serves `/static/` from it and proxies everything else to Gunicorn on `127.0.0.1:8000` in the same pod. Exposed on the `linktree-web` Service, port 80.
- TLS is not handled in the pod. Put an Ingress or load balancer in front of `linktree-web`, and have it set `X-Forwarded-Proto`.

Before applying:

```bash
podman build -f Dockerfile.prod -t <registry>/linktree:<tag> .
podman push <registry>/linktree:<tag>
```

Then edit `k8s/linktree.yaml`: replace both `localhost/linktree:latest` references with that image, set real values in the `linktree` Secret, and set `ALLOWED_HOSTS` / `CSRF_TRUSTED_ORIGINS` for your domain. Then run `kubectl apply -f k8s/linktree.yaml`.

The manifest started as `podman kube generate --type deployment --service linktree-db linktree-web`, run against local pods that had the same containers. Podman's output needed manual fixes: it drops podman secrets, emits a hostPath for the nginx config, turns named volumes into undeclared PVCs, and leaves the db Service without a port. To try it locally with `podman kube play`, change `POSTGRES_HOST` to `linktree-db-pod`, because podman ignores Services.

## Known gaps

- No automated database backup/restore is set up — `postgres_data` is a local Docker volume with no offsite replication.
- No CI/CD pipeline; deployment above is manual.
- HTTP security headers beyond TLS (HSTS, CSP, etc.) are not configured.
