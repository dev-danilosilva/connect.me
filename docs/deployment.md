# Deployment

This project ships two separate Docker setups: one for local development and one for production. They deliberately don't share a compose file — the dev setup optimizes for fast iteration, the prod setup for security and reliability.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Dev image. Installs deps, no build optimizations. |
| `docker-compose.yml` | Dev stack: `web` (bind-mounted source, `runserver`, auto-reload) + `db`. |
| `Dockerfile.prod` | Multi-stage prod image. No compilers/dev headers in the final image, runs as a non-root user, bakes in `collectstatic` output, serves via Gunicorn. |
| `docker-compose.prod.yml` | Prod stack: `db` + `web` (Gunicorn, no ports exposed to the host) + `nginx` (reverse proxy + TLS termination) + `certbot` (auto-renewal). |
| `nginx.conf.template` | nginx config, templated with `${DOMAIN}` at container start. |
| `init-letsencrypt.sh` | One-time script to bootstrap Let's Encrypt certificates. |
| `.env.example` | Reference for every environment variable used by both stacks. |

## Local development

```bash
cp .env.example .env   # defaults work out of the box for local dev
docker compose up --build
```

- App: http://localhost:8000
- Postgres: exposed on `localhost:5432` for connecting with a local client
- Source is bind-mounted into the container — edits to the code are picked up immediately by `runserver`, no rebuild needed (only rebuild after changing `requirements.txt`)
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

## Known gaps

- No automated database backup/restore is set up — `postgres_data` is a local Docker volume with no offsite replication.
- No CI/CD pipeline; deployment above is manual.
- HTTP security headers beyond TLS (HSTS, CSP, etc.) are not configured.
