import os

from django.conf import settings
from django.contrib.staticfiles.management.commands.runserver import (
    Command as StaticfilesRunserverCommand,
)
from django.utils import autoreload

from frontend import elm


class Command(StaticfilesRunserverCommand):
    help = (
        "Starts the development server, compiling the Elm programs in debug "
        "mode and recompiling them whenever their sources change."
    )

    def add_arguments(self, parser):
        super().add_arguments(parser)
        parser.add_argument(
            "--no-elm",
            action="store_false",
            dest="use_elm",
            help="Don't compile or watch the Elm frontend.",
        )

    def handle(self, *args, **options):
        # With autoreload on, Django re-runs this command in a child process
        # (DJANGO_AUTORELOAD_ENV="true") and restarts that child on every
        # Python change. Building in the parent keeps the watcher alive across
        # those restarts and compiles only once at startup.
        in_reloader_child = os.environ.get(autoreload.DJANGO_AUTORELOAD_ENV) == "true"
        if options["use_elm"] and settings.DEBUG and not in_reloader_child:
            self.start_elm()
        super().handle(*args, **options)

    def start_elm(self):
        try:
            self.build_elm()
        except elm.ElmNotInstalled as error:
            self.stderr.write(f"Elm: {error} Pages that embed Elm will not load.")
            return
        elm.watch(self.build_elm)
        self.stdout.write(f"Elm: watching {elm.ELM_DIR} for changes (debug mode)")
        self.stdout.flush()

    def build_elm(self):
        ok, output = elm.compile_elm(debug=True)
        if ok:
            bundles = ", ".join(bundle.name for bundle in elm.outputs())
            self.stdout.write(self.style.SUCCESS(f"Elm: compiled {bundles} (debug)"))
        else:
            self.stderr.write(self.style.ERROR("Elm: compile failed") + "\n" + output)
        # The watcher thread logs between requests; flush so messages show up
        # promptly even when output isn't a TTY (e.g. `docker compose logs`).
        self.stdout.flush()
        self.stderr.flush()
