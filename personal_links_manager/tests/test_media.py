import pytest
from django.core.files.base import ContentFile
from django.core.files.uploadedfile import SimpleUploadedFile
from django.urls import reverse

from accounts.models import User
from personal_links_manager import layout, media
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


# ---- Upload endpoint ----


def upload(client, data, kind="video", name="clip.mp4", **extra):
    return client.post(
        reverse("api_media"), {"kind": kind, "file": SimpleUploadedFile(name, data)}, **extra
    )


@pytest.mark.parametrize(
    "data, kind, ext",
    [
        (samples.MP4, "video", "mp4"),
        (samples.WEBM, "video", "webm"),
        (samples.JPEG, "image", "jpg"),
        (samples.PNG, "image", "png"),
        (samples.WEBP, "image", "webp"),
    ],
)
def test_upload_stores_the_file_and_returns_its_url(client, user, media_root, data, kind, ext):
    client.force_login(user)

    # The name lies about the type; the bytes decide.
    response = upload(client, data, kind=kind, name="whatever.bin")

    assert response.status_code == 201
    asset = MediaAsset.objects.get()
    assert response.json() == {
        "id": str(asset.id),
        "kind": kind,
        "url": f"http://testserver/media/{asset.id}.{ext}",
    }
    assert asset.owner == user
    assert asset.size_bytes == len(data)
    assert (media_root / f"{asset.id}.{ext}").read_bytes() == data


# The test client's own host, "testserver", isn't a valid URL host, so
# these use a real domain and the development server's localhost.
@pytest.mark.parametrize("host", ["links.example.com", "localhost:8000"])
def test_uploaded_urls_are_valid_layout_urls(client, user, settings, host):
    settings.ALLOWED_HOSTS = [host.split(":")[0]]
    client.force_login(user)
    video = upload(client, samples.MP4, HTTP_HOST=host).json()["url"]
    poster = upload(client, samples.PNG, kind="image", HTTP_HOST=host).json()["url"]
    page = LinkPage.objects.create(owner=user, handle="my-page")
    document = page.draft_layout
    links = next(s for s in document["sections"] if s["type"] == "links")
    links["items"] = [link_tile("Talk", {"type": "video", "src": video, "poster": poster})]

    assert layout.validate(document)["sections"] == document["sections"]


@pytest.mark.parametrize(
    "data, kind, message",
    [
        (samples.SVG, "image", "Upload a JPEG, PNG or WebP image."),
        (b"MZ\x90\x00" + b"\x00" * 64, "video", "Upload an MP4 or WebM video."),
        (b"", "video", "Upload an MP4 or WebM video."),
        (samples.HEIC, "video", "Upload an MP4 or WebM video."),
        # Right format, wrong slot.
        (samples.PNG, "video", "Upload an MP4 or WebM video."),
        (samples.MP4, "image", "Upload a JPEG, PNG or WebP image."),
    ],
)
def test_upload_rejects_wrong_types(client, user, data, kind, message):
    client.force_login(user)

    response = upload(client, data, kind=kind)

    assert response.status_code == 400
    assert response.json() == {"file": [message]}
    assert not MediaAsset.objects.exists()


def test_upload_rejects_unknown_kind_and_missing_file(client, user):
    client.force_login(user)

    assert upload(client, samples.MP4, kind="audio").status_code == 400
    assert client.post(reverse("api_media"), {"kind": "video"}).status_code == 400


def test_upload_enforces_size_limits(client, user, monkeypatch):
    monkeypatch.setitem(media.MAX_BYTES, "video", len(samples.MP4) - 1)
    monkeypatch.setitem(media.MAX_BYTES, "image", len(samples.PNG) - 1)
    client.force_login(user)

    video = upload(client, samples.MP4)
    image = upload(client, samples.PNG, kind="image")

    assert video.json() == {"file": ["Videos can be at most 20 MB."]}
    assert image.json() == {"file": ["Images can be at most 5 MB."]}


def test_upload_enforces_the_per_user_quota(client, user, monkeypatch):
    monkeypatch.setattr(media, "QUOTA_BYTES", len(samples.MP4) * 2)
    other = User.objects.create_user(email="other@example.com", password="password123")
    client.force_login(other)
    assert upload(client, samples.MP4).status_code == 201  # others' uploads don't count
    client.force_login(user)

    assert upload(client, samples.MP4).status_code == 201
    assert upload(client, samples.MP4).status_code == 201
    response = upload(client, samples.MP4)

    assert response.status_code == 400
    assert response.json() == {"file": [media.QUOTA_MESSAGE]}
    assert MediaAsset.objects.filter(owner=user).count() == 2


def test_anonymous_uploads_are_forbidden(client):
    assert upload(client, samples.MP4).status_code == 403
    assert not MediaAsset.objects.exists()
