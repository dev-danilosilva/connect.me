# Deployment

This project ships two separate Docker setups: one for local development (Postgres in Docker, Django in a local virtualenv) and one for production. They deliberately don't share a compose file — the dev setup optimizes for fast iteration, the prod setup for security and reliability.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Dev image for the optional `full-docker` profile. Installs deps and the `elm` binary, no build optimizations. |
| `docker-compose.yml` | Dev stack: `db` (always) + `web` (only with `--profile full-docker`: bind-mounted source, `runserver`, auto-reload). |
| `Dockerfile.prod` | Multi-stage prod build with two targets. `web`: compiles the Elm page editor with `--optimize` in a Node stage (the bundle isn't in git, so every build compiles it), runs `collectstatic`, and produces an image with no compilers/dev headers that runs Gunicorn as a non-root user. `nginx`: `nginx:1.27-alpine` with that build's `collectstatic` output and `nginx-reload-certs.sh` copied in. |
| `docker-compose.prod.yml` | Prod stack: `db` + `web` (Gunicorn, no ports exposed to the host) + `nginx` (reverse proxy, TLS termination, serves `/static/`) + `certbot` (auto-renewal). |
| `nginx-reload-certs.sh` | Built into the `nginx` image; reloads nginx periodically so renewed certificates are served. |
| `nginx.conf.template` | nginx config, templated with `${DOMAIN}` at container start. |
| `init-letsencrypt.sh` | One-time script to bootstrap Let's Encrypt certificates. |
| `.env.example` | Reference for every environment variable used by both stacks. |

## Local development

Development uses a mixed setup: **Postgres runs in Docker** and **Django runs from a local virtualenv**. The full steps are in the [README](../README.md#development-environment).

```bash
cp .env.example .env   # defaults work out of the box for local dev
docker compose up -d db
source venv/bin/activate
python manage.py migrate
python manage.py runserver
```

- App: http://localhost:8000
- Postgres: exposed on `localhost:5432`, matching `POSTGRES_HOST=localhost` in `.env.example`
- `runserver` also compiles the Elm page editor in debug mode and recompiles it on every change to `elm/`; this needs `DEBUG=True` in `.env` and the `elm` binary on your `PATH`
- Django serves static files itself in dev (`DEBUG=True`); nginx is only part of the production stack

If you want to run everything in Docker instead (for example, to check behavior closer to production), use the `full-docker` profile. It runs `web` from the dev `Dockerfile`, bind-mounts the source, and runs migrations on start:

```bash
docker compose --profile full-docker up --build
```

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

This brings up `db`, `web` (migrations run automatically on start), `nginx`, and `certbot`. Every 12 hours `certbot` checks the certificate and renews it once it's within 30 days of expiry.

nginx keeps the certificate it loaded in memory, so the `nginx` image reloads nginx every 6 hours (`nginx-reload-certs.sh`) to pick up a renewed certificate. The reload is graceful: in-flight requests finish on the old workers. To change the interval, set `NGINX_RELOAD_INTERVAL` (seconds) on the `nginx` service.

nginx serves `/static/` from files built into its own image (the `nginx` target of `Dockerfile.prod`) and proxies everything else to Gunicorn. No volume is shared with `web`, so every `up -d --build` serves exactly the static files that build produced. A shared named volume would keep serving the first deploy's CSS/JS, because Docker only fills a named volume from the image while the volume is empty.

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

# Load a renewed certificate into nginx now, instead of at the next scheduled reload
docker compose -f docker-compose.prod.yml exec nginx nginx -s reload
```

## Known gaps

- No automated database backup/restore is set up — `postgres_data` is a local Docker volume with no offsite replication.
- No CI/CD pipeline; deployment above is manual.
- Content-Security-Policy and similar headers are not configured. HSTS is: when `DEBUG=False`, Django sends `Strict-Transport-Security` for 30 days with `includeSubDomains` and `preload` (`linktree_project/settings.py`). HSTS is hard to undo once browsers have cached it, and even harder once the domain is on the preload list. Before raising `SECURE_HSTS_SECONDS` or submitting the domain for preload, make sure every subdomain serves HTTPS.
