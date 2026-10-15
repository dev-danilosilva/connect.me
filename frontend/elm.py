"""Builds the Elm programs (elm/) into static/js/, one bundle per program.

Each program is a `<Name>/Main.elm` entrypoint with its own `main`, compiled
on its own so a page loads only the program it embeds (see PROGRAMS).

The bundles are build artifacts and are not committed: `runserver` compiles
them in debug mode and recompiles on change, the e2e suite rebuilds them when
they're stale, and the production image compiles them with --optimize.
"""

import shutil
import subprocess
import threading
import time
from pathlib import Path

from django.conf import settings

ELM_DIR = Path(settings.BASE_DIR) / "elm"
OUTPUT_DIR = Path(settings.BASE_DIR) / "static" / "js"

# Entrypoint (relative to ELM_DIR) -> bundle filename in OUTPUT_DIR.
PROGRAMS = {
    "src/PageEditor/Main.elm": "page_editor.js",
    "src/VisitsChart/Main.elm": "visits_chart.js",
}


def outputs():
    return [OUTPUT_DIR / bundle for bundle in PROGRAMS.values()]


class ElmNotInstalled(Exception):
    pass


def compile_elm(debug=False):
    """Runs `elm make` once per program; returns (all succeeded, compiler output)."""
    elm = shutil.which("elm")
    if elm is None:
        raise ElmNotInstalled("The `elm` compiler is not on PATH (see README: Elm frontend).")
    succeeded, output = True, []
    for entrypoint, bundle in PROGRAMS.items():
        args = [elm, "make", entrypoint, f"--output={OUTPUT_DIR / bundle}"]
        if debug:
            args.append("--debug")
        result = subprocess.run(args, cwd=ELM_DIR, capture_output=True, text=True)
        succeeded = succeeded and result.returncode == 0
        output.append((result.stdout + result.stderr).strip())
    return succeeded, "\n".join(output)


def source_mtimes():
    files = [ELM_DIR / "elm.json", *(ELM_DIR / "src").rglob("*.elm")]
    return {path: path.stat().st_mtime_ns for path in files if path.exists()}


def bundle_is_stale():
    """True if any bundle is missing or older than any source. Programs share
    modules, so any source change rebuilds them all."""
    bundles = outputs()
    if not all(bundle.exists() for bundle in bundles):
        return True
    built_at = min(bundle.stat().st_mtime_ns for bundle in bundles)
    return any(mtime > built_at for mtime in source_mtimes().values())


def watch(on_change, interval=0.5):
    """Polls the Elm sources and calls on_change() whenever they change.

    Runs forever in a daemon thread. Polling keeps this dependency-free; the
    source tree is a handful of files, so it's cheap.
    """

    seen = source_mtimes()

    def loop():
        nonlocal seen
        while True:
            time.sleep(interval)
            current = source_mtimes()
            if current != seen:
                seen = current
                on_change()

    thread = threading.Thread(target=loop, name="elm-watcher", daemon=True)
    thread.start()
    return thread
