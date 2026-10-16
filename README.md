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

### Elm frontend

Most of the app is server-rendered Django templates. Elm is used where a piece of UI needs real interactivity, as **separate Elm programs**: each one has its own `main`, compiles to its own bundle and is embedded on its own, so a page only loads the program it uses.

| Program | Entrypoint | Bundle | Started with | Embedded in |
|---|---|---|---|---|
| Page editor | `elm/src/PageEditor/Main.elm` | `static/js/page_editor.js` | `Elm.PageEditor.Main.init` | `page_editor.html` (`/dashboard/pages/<handle>/edit/`) |
| Visits chart | `elm/src/VisitsChart/Main.elm` | `static/js/visits_chart.js` | `Elm.VisitsChart.Main.init` | `dashboard.html` (`/dashboard/`) |

Layout conventions in `elm/src/`:

- **One folder per program**, named after it, with the entrypoint at `<Name>/Main.elm`. Modules only that program uses go next to it as `<Name>/*.elm`, e.g. `PageEditor/Preview.elm`, the link page as visitors see it, rendered in the editor's preview.
- **Shared modules** live under `elm/src/Lib/`, outside any program folder, as `Lib.<Module>`: `Lib.Format` (number and "YYYY-MM-DD" date formatting) and `Lib.List` (list helpers missing from elm/core). They hold no program-specific code.
- `elm/tests/` mirrors `src/` (e.g. `tests/PageEditor/MainTest.elm`).

To add a program: create `elm/src/<Name>/Main.elm` with a `main`, add it to `PROGRAMS` in `frontend/elm.py` and to the Elm stage of `Dockerfile.prod`, gitignore its bundle, and load it from a template with `Elm.<Name>.Main.init`.

| Path | What it is |
|---|---|
| `elm/elm.json` | Elm project file (dependencies, compiler version), shared by all programs |
| `static/js/*.js` (the bundles above) | Compiled output — build artifacts, **gitignored** |
| `static/css/page_editor.css` | Editor styles (shared tokens and glass styles, including the visits chart's, live in `static/css/app.css`) |
| `frontend/` | Django app that builds the bundles: `elm.py` (compile/watch helpers, `PROGRAMS`) and the `runserver` override |

There's no bundler and no `package.json`: the Elm compiler writes each bundle straight into `static/`, and Django serves it like any other static file.

#### Prerequisites

The Elm compiler, at the version pinned in `elm/elm.json` (`"elm-version": "0.19.2"`). Check it with:

```bash
elm --version   # must print 0.19.2
```

#### Compiling

In development you don't compile by hand: `python manage.py runserver` does it. On startup it compiles every program in **debug mode** (`elm make --debug`, which adds Elm's time-travel debugger in the bottom-right corner of the page) and then **watches `elm/src/` and `elm/elm.json`**, recompiling within about a second of every save:

```
Elm: compiled page_editor.js, visits_chart.js (debug)
Elm: watching …/elm for changes (debug mode)
```

Compile errors are printed in the `runserver` output; the server keeps running and the next save that fixes the error rebuilds the bundles. Reload the page to pick up a new build (do a hard refresh, Ctrl+Shift+R, if it looks stale — static files aren't cache-busted in development).

This only happens when `DEBUG=True`. To run the server without it, use `python manage.py runserver --no-elm`. To compile by hand (e.g. without the server), run from the repo root:

```bash
cd elm \
  && elm make src/PageEditor/Main.elm --debug --output=../static/js/page_editor.js \
  && elm make src/VisitsChart/Main.elm --debug --output=../static/js/visits_chart.js \
  && cd ..
```

**The bundles are not committed.** They're gitignored; commit only the `.elm` sources. Every production deploy compiles them from scratch with `--optimize` in an Elm stage of `Dockerfile.prod`, so deploys always ship what's in `elm/src/`. The dev `Dockerfile` (`--profile full-docker`) includes the `elm` binary too, so the watcher also works there.

When upgrading Elm, change the version in four places so they stay in sync: `elm/elm.json` (`elm-version`), the `npm install -g elm@…` line in both `Dockerfile` and `Dockerfile.prod`, and the pinned `elm-test@…` runner (the Testing commands below and `ELM_TEST_VERSION` in `.githooks/pre-commit`).

#### How Django hands data to Elm

Each program gets its own flags from the view that embeds it (`personal_links_manager/views.py`): `page_editor` builds `elm_flags` for the page editor, and `dashboard` builds `visits_chart_flags` for the visits chart (mock visit data for now, from `stats.mock_daily_visits`). The template serializes them with `json_script` and passes them to the program's `init`. The page editor decodes its flags with `flagsDecoder` in `PageEditor/Main.elm`; the visits chart decodes `{ "pages": [...] }` in `VisitsChart/Main.elm`.

To add a value to the page editor's flags:

1. Add the key to `elm_flags` in the view (plus a test in `personal_links_manager/tests/test_views.py`).
2. Add the field to the `Flags` type alias and to `flagsDecoder` (bump `Decode.mapN`).
3. Update the fallback `Flags …` value in `init` and the sample JSON in `elm/tests/PageEditor/MainTest.elm`.

If the JSON and the decoder disagree, decoding fails silently and the app starts with empty fallback flags, so a blank title or missing data usually means a mismatch here.

The page editor's `draftLayout` flag is the page's stored layout document, decoded by `PageEditor/Layout.elm` and rendered by `PageEditor/Preview.elm`. Its format, validation, API and versioning are described in [docs/page-layout-spec-v1.md](docs/page-layout-spec-v1.md).

#### Testing

```bash
cd elm && npx elm-test@0.19.2-1 && cd ..   # Elm unit tests (tests/ mirrors src/, e.g. tests/Lib/FormatTest.elm)
pytest e2e/test_page_editor.py e2e/test_dashboard.py   # end-to-end tests for both programs (Playwright)
```

> **Pin the runner version.** A bare `npx elm-test` fetches the latest runner (0.19.3-x), which expects Elm 0.19.3 and fails with `It requires 0.19.3, but you are using 0.19.2`. `elm-test@0.19.2-1` matches this project's compiler; bump it together with the Elm version.

The e2e suite compiles the bundles itself (debug mode) when any is missing or older than the Elm sources, so it works on a fresh clone; it needs `elm` on `PATH`. The `frontend` unit tests (`pytest frontend`, also run by the pre-commit hook) cover the build/watch helpers.

### Running tests

```bash
pytest accounts personal_links_manager   # unit tests (pytest-django), fast, no browser
playwright install chromium   # one-time, downloads the browser binary
pytest e2e               # UI tests (Playwright), spins up a real browser + LiveServer
pytest                   # runs both
```

### Git hooks

A `pre-commit` hook (runs the fast unit tests: `pytest accounts personal_links_manager frontend` and the Elm unit tests with `elm-test`) lives in `.githooks/`. The Elm step needs `npx`; without it the hook prints a warning and skips that step. Activate it once per clone:

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
