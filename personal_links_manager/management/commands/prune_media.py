import json
import re
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db.models import Sum
from django.utils import timezone

from personal_links_manager.models import LinkPage, MediaAsset

# Uploads not yet saved into a draft are kept this long.
GRACE_PERIOD = timedelta(hours=24)

MEDIA_URL_ID = re.compile(r"/media/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.")


class Command(BaseCommand):
    help = "Deletes uploaded media that no page's draft or published layout uses."

    def handle(self, *args, **options):
        referenced = set()
        for draft, published in LinkPage.objects.values_list("draft_layout", "published_layout"):
            # Scans the whole document, so it doesn't depend on which fields hold URLs.
            referenced.update(MEDIA_URL_ID.findall(json.dumps([draft, published])))

        unused = MediaAsset.objects.filter(
            created_at__lt=timezone.now() - GRACE_PERIOD
        ).exclude(id__in=referenced)
        size = unused.aggregate(total=Sum("size_bytes"))["total"] or 0
        # The post_delete signal removes each file.
        count, _ = unused.delete()
        self.stdout.write(f"Removed {count} media assets ({size} bytes).")
