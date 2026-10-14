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
- The Elm compiler 0.19.2 (e.g. `npm install -g elm@0.19.2-0`) — `runserver` uses it to build the page editor; see [Elm frontend](#elm-frontend-page-editor)
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

### Elm frontend (page editor)

Most of the app is server-rendered Django templates. The one exception is the page editor (`/dashboard/pages/<handle>/edit/`), which is a small Elm app.

| Path | What it is |
|---|---|
| `elm/elm.json` | Elm project file (dependencies, compiler version) |
| `elm/src/Main.elm` | The editor app |
| `elm/tests/` | Elm unit tests (`elm-explorations/test`) |
| `static/js/page_editor.js` | Compiled output — a build artifact, **gitignored** |
| `static/css/page_editor.css` | Editor styles (shared tokens and glass styles live in `static/css/app.css`) |
| `personal_links_manager/templates/personal_links_manager/page_editor.html` | Loads the bundle and starts the app |
| `frontend/` | Django app that builds the bundle: `elm.py` (compile/watch helpers) and the `runserver` override |

There's no bundler and no `package.json`: the Elm compiler writes one JS file straight into `static/`, and Django serves it like any other static file.

#### Prerequisites

The Elm compiler, at the version pinned in `elm/elm.json` (`"elm-version": "0.19.2"`). Check it with:

```bash
elm --version   # must print 0.19.2
```

#### Compiling

In development you don't compile by hand: `python manage.py runserver` does it. On startup it compiles the editor in **debug mode** (`elm make --debug`, which adds Elm's time-travel debugger in the bottom-right corner of the editor) and then **watches `elm/src/` and `elm/elm.json`**, recompiling within about a second of every save:

```
Elm: compiled page_editor.js (debug)
Elm: watching …/elm for changes (debug mode)
```

Compile errors are printed in the `runserver` output; the server keeps running and the next save that fixes the error rebuilds the bundle. Reload the editor page to pick up a new build (do a hard refresh, Ctrl+Shift+R, if it looks stale — static files aren't cache-busted in development).

This only happens when `DEBUG=True`. To run the server without it, use `python manage.py runserver --no-elm`. To compile by hand (e.g. without the server), run from the repo root:

```bash
cd elm && elm make src/Main.elm --debug --output=../static/js/page_editor.js && cd ..
```

**The bundle is not committed.** `static/js/page_editor.js` is gitignored; commit only the `.elm` sources. Every production deploy compiles it from scratch with `--optimize` in an Elm stage of `Dockerfile.prod`, so deploys always ship what's in `elm/src/`. The dev `Dockerfile` (`--profile full-docker`) includes the `elm` binary too, so the watcher also works there.

When upgrading Elm, change the version in three places so they stay in sync: `elm/elm.json` (`elm-version`), and the `npm install -g elm@…` line in both `Dockerfile` and `Dockerfile.prod`.

#### How Django hands data to Elm

The `page_editor` view (`personal_links_manager/views.py`) builds an `elm_flags` dict. The template serializes it with `json_script`, and `Elm.Main.init` receives it as flags. Elm decodes it with `flagsDecoder` in `Main.elm`.

To add a new value:

1. Add the key to `elm_flags` in the view (plus a test in `personal_links_manager/tests/test_views.py`).
2. Add the field to the `Flags` type alias and to `flagsDecoder` (bump `Decode.mapN`).
3. Update the fallback `Flags …` value in `init` and the sample JSON in `elm/tests/MainTest.elm`.

If the JSON and the decoder disagree, decoding fails silently and the app starts with empty fallback flags, so a blank title or missing data usually means a mismatch here.

#### Testing

```bash
cd elm && npx elm-test && cd ..         # Elm unit tests
pytest e2e/test_page_editor.py          # end-to-end editor tests (Playwright)
```

> **Known issue:** `npx elm-test` currently fails with `It requires 0.19.3, but you are using 0.19.2` because the test runner doesn't support this project's Elm version. Until that's resolved, rely on the e2e tests for coverage of the editor.

The e2e suite compiles the bundle itself (debug mode) when it's missing or older than the Elm sources, so it works on a fresh clone; it needs `elm` on `PATH`. The `frontend` unit tests (`pytest frontend`, also run by the pre-commit hook) cover the build/watch helpers.

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
