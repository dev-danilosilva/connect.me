from django.core.management.base import BaseCommand

from accounts.models import User
from personal_links_manager.models import LinkPage

DEMO_EMAIL = "test@example.com"
DEMO_PASSWORD = "password123"
DEMO_DISPLAY_NAME = "Tes Tuser"
DEMO_HANDLES = ["my-links", "portfolio"]


class Command(BaseCommand):
    help = (
        "Creates a demo user (matching linktree-ui's mock seed data) and a "
        "couple of demo pages, for manual login testing in development."
    )

    def handle(self, *args, **options):
        user, created = User.objects.get_or_create(
            email=DEMO_EMAIL, defaults={"display_name": DEMO_DISPLAY_NAME}
        )
        if created:
            user.set_password(DEMO_PASSWORD)
            user.save()
            self.stdout.write(self.style.SUCCESS(f"Created demo user {DEMO_EMAIL}"))
        else:
            self.stdout.write(f"Demo user {DEMO_EMAIL} already exists")

        for handle in DEMO_HANDLES:
            _, page_created = LinkPage.objects.get_or_create(handle=handle, defaults={"owner": user})
            if page_created:
                self.stdout.write(self.style.SUCCESS(f"Created demo page {handle}"))

        self.stdout.write(
            self.style.SUCCESS(f"Log in with {DEMO_EMAIL} / {DEMO_PASSWORD}")
        )
