# Linktree

Backend for a multi-tenant SaaS linktree clone — users create a personal page that aggregates all their important links in one place, shareable via a single URL (`/:username`). Also serves the public landing page for the product itself.

Built with Django and PostgreSQL.

## Features

Implemented so far (server-rendered Django views, session-based auth):

- Public landing page (`/`)
- Registration / login / logout (email + password, `accounts` app)
- Dashboard (`/dashboard/`) — create/list link pages with live handle-availability checking

Not yet implemented (see [`docs/roadmap.md`](docs/roadmap.md) for the full roadmap): per-page link CRUD, public profile pages, theming, analytics.

## Development environment

Hybrid setup: **Postgres runs in Docker**, the **Django app runs from a local virtualenv** on the host. This gives fast autoreload and a native debugger, at the cost of needing a matching local Python. An "everything in Docker" fallback is still available (see below) for prod-parity checks.

### Prerequisites

- Docker and Docker Compose (for Postgres)
- Python 3.12
- A C toolchain + Postgres client headers, to build `psycopg2-binary`:
  - Debian/Ubuntu: `sudo apt install build-essential libpq-dev`
  - macOS: `brew install postgresql`

### Getting started

```bash
cp .env.example .env

# Start Postgres only (the `web` service is off by default now)
docker compose up -d db

python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt   # or requirements.txt if you don't need the test stack

python manage.py migrate
python manage.py seed_demo_data       # creates test@example.com / password123
python manage.py runserver
```

- App: http://localhost:8000
- Admin: http://localhost:8000/admin/
- Postgres: exposed on `localhost:5432` (matches `POSTGRES_HOST=localhost` in `.env.example`) if you want to connect with a local client (e.g. `psql`, TablePlus)

### Common commands

```bash
# Create an admin user
python manage.py createsuperuser

# Run a Django management command
python manage.py <command>

# Make new migrations after changing models
python manage.py makemigrations

# Open a Django shell
python manage.py shell

# Stop Postgres
docker compose down
```

### Running tests

```bash
pytest accounts personal_links_manager   # unit tests (pytest-django), fast, no browser
playwright install chromium   # one-time, downloads the browser binary
pytest e2e               # UI tests (Playwright), spins up a real browser + LiveServer
pytest                   # runs both
```

### Git hooks

A `pre-commit` hook (runs the fast unit tests, `pytest accounts personal_links_manager`) lives in `.githooks/`. Activate it once per clone:

```bash
git config core.hooksPath .githooks
```

Skip it for a single commit with `git commit --no-verify`.

### Full Docker (optional, prod-parity check)

The original all-in-Docker dev flow still works via the existing `Dockerfile`, gated behind a Compose profile so it doesn't start by accident:

```bash
docker compose --profile full-docker up --build
```

### Environment variables

See `.env.example` for the full list. For local development the defaults work out of the box — you only need to fill anything in when deploying to production.

`DEBUG` defaults to `False` (fails closed) and `SECRET_KEY` is mandatory once it is — Django raises `ImproperlyConfigured` at startup rather than silently running production on the checked-in dev key.

## Production deployment

See [`docs/deployment.md`](docs/deployment.md) for the production setup (multi-stage Docker build, nginx, TLS via Let's Encrypt).
