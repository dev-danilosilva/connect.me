import copy
from datetime import timedelta
from io import StringIO

import pytest
from django.core.files.base import ContentFile
from django.core.management import call_command
from django.utils import timezone

from accounts.models import User
from personal_links_manager.models import LinkPage, MediaAsset

from . import media_samples as samples
from .layouts import link_tile

pytestmark = pytest.mark.django_db


@pytest.fixture(autouse=True)
def media_root(settings, tmp_path):
    settings.MEDIA_ROOT = tmp_path
    return tmp_path


@pytest.fixture
def user():
    return User.objects.create_user(email="owner@example.com", password="password123")


def make_asset(user, hours_old):
    asset = MediaAsset(owner=user, kind="video", content_type="video/mp4", size_bytes=len(samples.MP4))
    asset.file.save(f"{asset.id}.mp4", ContentFile(samples.MP4), save=False)
    asset.save()
    MediaAsset.objects.filter(pk=asset.pk).update(
        created_at=timezone.now() - timedelta(hours=hours_old)
    )
    return asset


def layout_using(page, asset):
    document = copy.deepcopy(page.draft_layout)
    links = next(s for s in document["sections"] if s["type"] == "links")
    url = f"https://example.com/media/{asset.id}.mp4"
    links["items"] = [link_tile("Talk", {"type": "video", "src": url, "poster": url})]
    return document


def run():
    out = StringIO()
    call_command("prune_media", stdout=out)
    return out.getvalue()


def test_deletes_old_unreferenced_assets_and_their_files(user, media_root):
    asset = make_asset(user, hours_old=25)

    output = run()

    assert not MediaAsset.objects.exists()
    assert not (media_root / asset.file.name).exists()
    assert output.strip() == f"Removed 1 media assets ({len(samples.MP4)} bytes)."


def test_keeps_recent_unreferenced_assets(user):
    make_asset(user, hours_old=23)

    run()

    assert MediaAsset.objects.count() == 1


def test_keeps_assets_referenced_by_a_draft(user):
    asset = make_asset(user, hours_old=25)
    page = LinkPage.objects.create(owner=user, handle="drafted")
    page.draft_layout = layout_using(page, asset)
    page.save()

    run()

    assert MediaAsset.objects.filter(pk=asset.pk).exists()


def test_keeps_assets_referenced_only_by_a_published_layout(user):
    asset = make_asset(user, hours_old=25)
    page = LinkPage.objects.create(owner=user, handle="published")
    page.published_layout = layout_using(page, asset)
    page.save()

    run()

    assert MediaAsset.objects.filter(pk=asset.pk).exists()
