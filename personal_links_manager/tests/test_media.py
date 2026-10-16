import pytest
from django.core.files.base import ContentFile

from accounts.models import User
from personal_links_manager import media
from personal_links_manager.models import MediaAsset

from . import media_samples as samples

pytestmark = pytest.mark.django_db


@pytest.fixture(autouse=True)
def media_root(settings, tmp_path):
    settings.MEDIA_ROOT = tmp_path
    return tmp_path


@pytest.fixture
def user():
    return User.objects.create_user(email="owner@example.com", password="password123")


@pytest.mark.parametrize(
    "data, expected",
    [
        (samples.MP4, ("video", "mp4", "video/mp4")),
        (samples.WEBM, ("video", "webm", "video/webm")),
        (samples.JPEG, ("image", "jpg", "image/jpeg")),
        (samples.PNG, ("image", "png", "image/png")),
        (samples.WEBP, ("image", "webp", "image/webp")),
    ],
)
def test_detect_recognises_accepted_formats(data, expected):
    assert tuple(media.detect(data[: media.HEAD_BYTES])) == expected


@pytest.mark.parametrize(
    "data",
    [samples.HEIC, samples.AVIF, samples.SVG, b"", b"hello world", b"MZ\x90\x00" + b"\x00" * 64],
)
def test_detect_rejects_everything_else(data):
    assert media.detect(data[: media.HEAD_BYTES]) is None


def make_asset(user, data=samples.MP4):
    asset = MediaAsset(owner=user, kind="video", content_type="video/mp4", size_bytes=len(data))
    asset.file.save(f"{asset.id}.mp4", ContentFile(data), save=False)
    asset.save()
    return asset


def test_asset_file_is_named_by_its_id(user, media_root):
    asset = make_asset(user)

    assert asset.file.name == f"{asset.id}.mp4"
    assert (media_root / f"{asset.id}.mp4").read_bytes() == samples.MP4


def test_deleting_an_asset_deletes_its_file(user, media_root):
    asset = make_asset(user)
    path = media_root / asset.file.name

    asset.delete()

    assert not path.exists()


def test_bulk_and_cascade_deletes_remove_files(user, media_root):
    first, second = make_asset(user), make_asset(user)
    paths = [media_root / first.file.name, media_root / second.file.name]

    MediaAsset.objects.filter(pk=first.pk).delete()
    user.delete()

    assert not any(path.exists() for path in paths)
