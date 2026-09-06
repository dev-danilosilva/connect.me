# Linktree

Backend for a multi-tenant SaaS linktree clone — users create a personal page that aggregates all their important links in one place, shareable via a single URL (`/:username`).

Built with Django and PostgreSQL.

## Development environment

The dev environment runs in Docker: a `web` container (Django, auto-reloading) and a `db` container (Postgres).

### Prerequisites

- Docker and Docker Compose

### Getting started

```bash
cp .env.example .env
docker compose up --build
```

- App: http://localhost:8000
- Admin: http://localhost:8000/admin/
- Postgres: exposed on `localhost:5432` if you want to connect with a local client (e.g. `psql`, TablePlus)

The project source is bind-mounted into the `web` container, so code changes are picked up immediately via Django's auto-reloading `runserver` — no rebuild needed. Only rebuild the image (`docker compose up --build`) after changing `requirements.txt`.

Migrations run automatically every time the `web` container starts.

### Common commands

```bash
# Create an admin user
docker compose exec web python manage.py createsuperuser

# Run a Django management command
docker compose exec web python manage.py <command>

# Make new migrations after changing models
docker compose exec web python manage.py makemigrations

# Open a Django shell
docker compose exec web python manage.py shell

# View logs
docker compose logs -f web

# Stop everything
docker compose down
```

### Environment variables

See `.env.example` for the full list. For local development the defaults work out of the box — you only need to fill anything in when deploying to production.

## Production deployment

See [`docs/deployment.md`](docs/deployment.md) for the production setup (multi-stage Docker build, nginx, TLS via Let's Encrypt).
