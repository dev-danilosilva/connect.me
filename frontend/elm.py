"""Builds the Elm page editor (elm/) into static/js/page_editor.js.

The bundle is a build artifact and is not committed: `runserver` compiles it
in debug mode and recompiles on change, the e2e suite rebuilds it when it's
stale, and the production image compiles it with --optimize.
"""

import shutil
import subprocess
import threading
import time
from pathlib import Path

from django.conf import settings

ELM_DIR = Path(settings.BASE_DIR) / "elm"
ENTRYPOINT = "src/Main.elm"
OUTPUT = Path(settings.BASE_DIR) / "static" / "js" / "page_editor.js"


class ElmNotInstalled(Exception):
    pass


def compile_elm(debug=False):
    """Runs `elm make`; returns (succeeded, compiler output)."""
    elm = shutil.which("elm")
    if elm is None:
        raise ElmNotInstalled("The `elm` compiler is not on PATH (see README: Elm frontend).")
    args = [elm, "make", ENTRYPOINT, f"--output={OUTPUT}"]
    if debug:
        args.append("--debug")
    result = subprocess.run(args, cwd=ELM_DIR, capture_output=True, text=True)
    return result.returncode == 0, (result.stdout + result.stderr).strip()


def source_mtimes():
    files = [ELM_DIR / "elm.json", *(ELM_DIR / "src").rglob("*.elm")]
    return {path: path.stat().st_mtime_ns for path in files if path.exists()}


def bundle_is_stale():
    if not OUTPUT.exists():
        return True
    built_at = OUTPUT.stat().st_mtime_ns
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
