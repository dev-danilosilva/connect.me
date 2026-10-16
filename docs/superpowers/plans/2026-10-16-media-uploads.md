# Media Uploads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Page owners can upload a video, poster image or image file from the page editor as a link tile's background, instead of pasting a URL.

**Architecture:** A `MediaAsset` model and `POST /api/media/` endpoint store validated files on local disk and return an absolute URL. The Elm editor puts that URL into the tile's `src`/`poster`/`url` exactly like a pasted link, so layout spec v1 is unchanged. nginx serves `/media/` from a Docker volume, and a `prune_media` command deletes files no layout references.

**Tech Stack:** Django 6.1 + DRF 3.18, pytest-django, Elm 0.19 (`elm/http`, `elm/file`), elm-test, Playwright e2e, nginx, Docker Compose.

**Spec:** `docs/superpowers/specs/2026-10-16-media-uploads-design.md`

## Global Constraints

- Layout spec v1 is not changed: no new version, no data migration of layouts. `poster` stays required.
- Accepted: MP4, WebM (videos, ≤ 20 MB); JPEG, PNG, WebP (images, ≤ 5 MB). The type comes from the file's bytes; extension and client `Content-Type` are ignored. SVG is never accepted.
- Quota: 200 MB per user, the sum of `MediaAsset.size_bytes`.
- No new Python dependencies. No ffmpeg, no background jobs.
- `MEDIA_ROOT = BASE_DIR / "media"`, `MEDIA_URL = "/media/"`. Files are stored as `<uuid>.<ext>`.
- Upload API: session auth + CSRF, `IsAuthenticated` (the DRF default), multipart, errors as `400 {"file": ["…"]}`.
- nginx `client_max_body_size 25M`; `/media/` served with `X-Content-Type-Options: nosniff` and `expires 30d`.
- `prune_media` only deletes unreferenced assets older than 24 hours.
- The Elm `Editor` module never does HTTP; `PageEditor.Main` does all requests.
- Error copy, verbatim:
  - "Upload an MP4 or WebM video."
  - "Upload a JPEG, PNG or WebP image."
  - "Videos can be at most 20 MB." / "Images can be at most 5 MB."
  - "This upload would go over your 200 MB of media. Remove unused tiles and try again tomorrow."

**Changes from the spec, made while planning:**
- The upload request carries a `kind` field (`video`/`image`) naming what the slot needs, and the server rejects a file of the other kind with that kind's message. This replaces the spec's single combined "Upload an MP4 or WebM video, or a JPEG, PNG or WebP image." message, and stops an image landing in a video's `src`.
- Upload state lives in `Editor.Model` (still no HTTP in Editor), instead of a Dict handed in by Main. It's the same split with less plumbing.

## Review Focus

1. **Uploaded URLs on a `localhost` dev or e2e server fail the editor's URL check.** `Editor.urlProblem` requires a dot in the host, so `http://localhost:8000/media/….mp4` shows "Enter a full URL" and blocks Save. Expected: uploaded URLs are always accepted. Pinned by an Elm test in Task 5.
2. **A HEIC/AVIF photo picked for the video slot.** These also start with an `ftyp` box, so a naive MP4 check accepts a phone photo as `video/mp4`. Expected: rejected with "Upload an MP4 or WebM video." Pinned in Task 1.
3. **The tile's background kind changes, or the tile is removed, while an upload runs.** Expected: the finished upload's URL is dropped instead of overwriting the new background, and nothing crashes. Pinned in Task 5.
4. **A file over nginx's 25M limit.** nginx answers 413 with an HTML body before Django sees it. Expected: the editor shows "That file is too big. Videos can be at most 20 MB.", not a generic error. Pinned in Task 6.
5. **Deleting a user, or a bulk queryset delete of assets.** Expected: the files are removed from disk too, not orphaned. Pinned in Task 1.

---

## File Structure

| File | Responsibility |
|---|---|
| `personal_links_manager/media.py` (new) | File type detection from bytes, size limits, quota constant, error messages |
| `personal_links_manager/models.py` | `MediaAsset` model + `post_delete` file cleanup |
| `personal_links_manager/migrations/00XX_mediaasset.py` (generated) | Migration |
| `personal_links_manager/api_views.py`, `urls.py` | `MediaUploadAPIView` at `/api/media/` |
| `linktree_project/settings.py`, `linktree_project/urls.py` | `MEDIA_ROOT`/`MEDIA_URL`, dev serving |
| `personal_links_manager/management/commands/prune_media.py` (new) | Cleanup command |
| `docker-compose.prod.yml`, `nginx.conf.template`, `Dockerfile.prod`, `.gitignore`, `docs/deployment.md` | Storage and serving in production |
| `elm/src/PageEditor/Editor.elm` | Upload slots, upload state, Upload buttons, localhost URL fix |
| `elm/src/PageEditor/Main.elm`, `elm/elm.json` | File picking, multipart request, progress, Save blocking |
| `static/css/page_editor.css` | Media field layout |
| Tests | `personal_links_manager/tests/test_media.py`, `test_prune_media.py`, `elm/tests/PageEditor/EditorTest.elm`, `MainTest.elm`, `e2e/test_page_editor.py` |

Test bytes used throughout (valid signatures, not playable media):

```python
MP4 = b"\x00\x00\x00\x18ftypisom" + b"\x00" * 64
WEBM = b"\x1a\x45\xdf\xa3" + b"\x00" * 64
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
WEBP = b"RIFF\x00\x00\x00\x00WEBPVP8 " + b"\x00" * 64
HEIC = b"\x00\x00\x00\x18ftypheic" + b"\x00" * 64
```

They're put in `personal_links_manager/tests/media_samples.py` (Task 1), so the e2e tests can import them too.

---

### Task 1: File detection, `MediaAsset` model and media settings

**Files:**
- Create: `personal_links_manager/media.py`
- Create: `personal_links_manager/tests/media_samples.py`
- Create: `personal_links_manager/tests/test_media.py`
- Modify: `personal_links_manager/models.py`
- Modify: `linktree_project/settings.py` (after `STATICFILES_DIRS`, ~line 173)
- Modify: `.gitignore`
- Generated: `personal_links_manager/migrations/00XX_mediaasset.py`

**Interfaces:**
- Produces:
  - `media.detect(head: bytes) -> media.Detected | None`, where `Detected` is a `NamedTuple(kind: str, ext: str, content_type: str)`.
  - Constants: `media.VIDEO`, `media.IMAGE`, `media.KINDS`, `media.MAX_BYTES: dict[str, int]`, `media.QUOTA_BYTES`, `media.HEAD_BYTES`.
  - Messages: `media.TYPE_MESSAGES: dict[str, str]`, `media.SIZE_MESSAGES: dict[str, str]`, `media.QUOTA_MESSAGE`.
  - `models.MediaAsset` with fields `id, owner, kind, file, content_type, size_bytes, created_at`.

- [ ] **Step 1: Write the sample bytes module**

`personal_links_manager/tests/media_samples.py`:

```python
"""Smallest byte strings with each format's signature, for upload tests.
They're not playable media; only the signature matters to the server."""

MP4 = b"\x00\x00\x00\x18ftypisom" + b"\x00" * 64
WEBM = b"\x1a\x45\xdf\xa3" + b"\x00" * 64
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
WEBP = b"RIFF\x00\x00\x00\x00WEBPVP8 " + b"\x00" * 64
HEIC = b"\x00\x00\x00\x18ftypheic" + b"\x00" * 64
AVIF = b"\x00\x00\x00\x18ftypavif" + b"\x00" * 64
SVG = b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
```

- [ ] **Step 2: Write the failing tests**

`personal_links_manager/tests/test_media.py`:

```python
import pytest

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


def make_asset(user, data=samples.MP4, name="clip.mp4"):
    from django.core.files.base import ContentFile

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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `venv/bin/pytest personal_links_manager/tests/test_media.py -q`
Expected: FAIL with `ImportError: cannot import name 'media'` (or `MediaAsset`).

- [ ] **Step 4: Implement `media.py`**

```python
"""Uploaded media files (docs/superpowers/specs/2026-10-16-media-uploads-design.md).

A file's type comes from its first bytes, never its name or the browser's
Content-Type: the file is served from our own domain, so it must be the
video or image it claims to be.
"""

from typing import NamedTuple

VIDEO = "video"
IMAGE = "image"
KINDS = [VIDEO, IMAGE]

MB = 1024 * 1024
MAX_BYTES = {VIDEO: 20 * MB, IMAGE: 5 * MB}
QUOTA_BYTES = 200 * MB

# Enough of the file to see every signature below.
HEAD_BYTES = 16

TYPE_MESSAGES = {
    VIDEO: "Upload an MP4 or WebM video.",
    IMAGE: "Upload a JPEG, PNG or WebP image.",
}
SIZE_MESSAGES = {
    VIDEO: "Videos can be at most 20 MB.",
    IMAGE: "Images can be at most 5 MB.",
}
QUOTA_MESSAGE = (
    "This upload would go over your 200 MB of media. "
    "Remove unused tiles and try again tomorrow."
)

# ISO media files (HEIC/AVIF photos) share MP4's `ftyp` box; these major
# brands mark them as images, not video.
STILL_IMAGE_BRANDS = {b"heic", b"heix", b"hevc", b"heim", b"heis", b"mif1", b"msf1", b"avif", b"avis"}


class Detected(NamedTuple):
    kind: str
    ext: str
    content_type: str


def detect(head):
    """The accepted format `head` (the file's first HEAD_BYTES) starts
    with, or None."""
    if head[4:8] == b"ftyp" and head[8:12] not in STILL_IMAGE_BRANDS:
        return Detected(VIDEO, "mp4", "video/mp4")
    if head.startswith(b"\x1a\x45\xdf\xa3"):
        return Detected(VIDEO, "webm", "video/webm")
    if head.startswith(b"\xff\xd8\xff"):
        return Detected(IMAGE, "jpg", "image/jpeg")
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return Detected(IMAGE, "png", "image/png")
    if head.startswith(b"RIFF") and head[8:12] == b"WEBP":
        return Detected(IMAGE, "webp", "image/webp")
    return None
```

- [ ] **Step 5: Add the model and the delete signal**

In `personal_links_manager/models.py`, add `import uuid` at the top, add `from django.db.models.signals import post_delete` and `from django.dispatch import receiver` to the imports, and append:

```python
class MediaAsset(models.Model):
    """A video or image a user uploaded (personal_links_manager/media.py).
    Layouts reference it by its URL, like any pasted link."""

    KIND_CHOICES = [("video", "Video"), ("image", "Image")]

    # Also the file's name, so media URLs can't be guessed.
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="media_assets"
    )
    kind = models.CharField(max_length=5, choices=KIND_CHOICES)
    file = models.FileField()
    content_type = models.CharField(max_length=50)
    size_bytes = models.PositiveBigIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]

    def __str__(self):
        return self.file.name


# A signal rather than delete(): it also runs for queryset deletes and for
# cascades from a deleted user, so no path leaves files on disk.
@receiver(post_delete, sender=MediaAsset)
def delete_media_file(sender, instance, **kwargs):
    instance.file.delete(save=False)
```

- [ ] **Step 6: Add the settings and ignore the media folder**

In `linktree_project/settings.py`, right after `STATICFILES_DIRS = [BASE_DIR / 'static']`:

```python

# Uploaded media (personal_links_manager/media.py). nginx serves /media/ in
# production; linktree_project/urls.py serves it in development.
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'
```

In `.gitignore`, after `staticfiles/`, add a line `media/`.

- [ ] **Step 7: Generate the migration**

Run: `venv/bin/python manage.py makemigrations personal_links_manager -n mediaasset`
Expected: `Migrations for 'personal_links_manager': … - Create model MediaAsset`

- [ ] **Step 8: Run the tests to verify they pass**

Run: `venv/bin/pytest personal_links_manager/tests/test_media.py -q --create-db`
Expected: all pass. (`--create-db` because `pytest.ini` uses `--reuse-db` and there's a new table.)

- [ ] **Step 9: Commit**

```bash
git add personal_links_manager/media.py personal_links_manager/models.py personal_links_manager/migrations/ personal_links_manager/tests/media_samples.py personal_links_manager/tests/test_media.py linktree_project/settings.py .gitignore
git commit -m "Add MediaAsset and media type detection"
```

---

### Task 2: Upload endpoint `POST /api/media/`

**Files:**
- Modify: `personal_links_manager/api_views.py`
- Modify: `personal_links_manager/urls.py`
- Modify: `linktree_project/urls.py`
- Test: `personal_links_manager/tests/test_media.py` (append)

**Interfaces:**
- Consumes: `media.detect`, `media.HEAD_BYTES`, `media.KINDS`, `media.MAX_BYTES`, `media.QUOTA_BYTES`, `media.TYPE_MESSAGES`, `media.SIZE_MESSAGES`, `media.QUOTA_MESSAGE`, `MediaAsset` (Task 1).
- Produces:
  - URL name `api_media`, path `/api/media/`.
  - Request: multipart with `kind` (`"video"` | `"image"`) and `file`.
  - Response: `201 {"id": str, "kind": str, "url": str}`, where `url` is absolute.
  - Errors: `400 {"file": [msg]}`, or `400 {"kind": [msg]}` for a bad kind; `403` when anonymous.

- [ ] **Step 1: Write the failing tests**

Append to `personal_links_manager/tests/test_media.py`:

```python
from django.core.files.uploadedfile import SimpleUploadedFile
from django.urls import reverse

from personal_links_manager import layout
from personal_links_manager.models import LinkPage

from .layouts import link_tile


def upload(client, data, kind="video", name="clip.mp4"):
    return client.post(
        reverse("api_media"), {"kind": kind, "file": SimpleUploadedFile(name, data)}
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
    body = response.json()
    asset = MediaAsset.objects.get()
    assert body == {
        "id": str(asset.id),
        "kind": kind,
        "url": f"http://testserver/media/{asset.id}.{ext}",
    }
    assert asset.owner == user
    assert asset.size_bytes == len(data)
    assert (media_root / f"{asset.id}.{ext}").read_bytes() == data


def test_uploaded_urls_are_valid_layout_urls(client, user):
    client.force_login(user)
    video = upload(client, samples.MP4).json()["url"]
    poster = upload(client, samples.PNG, kind="image").json()["url"]
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `venv/bin/pytest personal_links_manager/tests/test_media.py -q`
Expected: the new tests FAIL with `NoReverseMatch: Reverse for 'api_media' not found`.

- [ ] **Step 3: Implement the view**

In `personal_links_manager/api_views.py`:
- Add `from django.db.models import Sum`.
- Add `from rest_framework import serializers, status` and `from rest_framework.parsers import MultiPartParser`.
- Extend the imports to `from . import layout, media` and `from .models import LinkPage, MediaAsset`.
- Append:

```python
class MediaUploadSerializer(serializers.Serializer):
    kind = serializers.ChoiceField(choices=media.KINDS)
    file = serializers.FileField(allow_empty_file=True)


class MediaUploadAPIView(APIView):
    """Stores an uploaded video or image and returns its URL, which the
    editor uses in a layout like any pasted link."""

    parser_classes = [MultiPartParser]

    def post(self, request):
        serializer = MediaUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        kind = serializer.validated_data["kind"]
        upload = serializer.validated_data["file"]

        def reject(message):
            return Response({"file": [message]}, status=status.HTTP_400_BAD_REQUEST)

        detected = media.detect(upload.read(media.HEAD_BYTES))
        upload.seek(0)
        if detected is None or detected.kind != kind:
            return reject(media.TYPE_MESSAGES[kind])
        if upload.size > media.MAX_BYTES[kind]:
            return reject(media.SIZE_MESSAGES[kind])
        used = request.user.media_assets.aggregate(total=Sum("size_bytes"))["total"] or 0
        if used + upload.size > media.QUOTA_BYTES:
            return reject(media.QUOTA_MESSAGE)

        asset = MediaAsset(
            owner=request.user,
            kind=kind,
            content_type=detected.content_type,
            size_bytes=upload.size,
        )
        asset.file.save(f"{asset.id}.{detected.ext}", upload, save=False)
        asset.save()
        return Response(
            {
                "id": str(asset.id),
                "kind": asset.kind,
                "url": request.build_absolute_uri(asset.file.url),
            },
            status=status.HTTP_201_CREATED,
        )
```

- [ ] **Step 4: Route it and serve media in development**

In `personal_links_manager/urls.py`, add `MediaUploadAPIView` to the `api_views` import and add to `urlpatterns`:

```python
    path("api/media/", MediaUploadAPIView.as_view(), name="api_media"),
```

In `linktree_project/urls.py`, add `from django.conf import settings` and `from django.conf.urls.static import static` to the imports, and after `urlpatterns = [...]`:

```python

# nginx serves uploaded media in production (nginx.conf.template).
urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
```

`static()` returns `[]` unless `DEBUG` is on.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `venv/bin/pytest personal_links_manager/tests/test_media.py -q`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add personal_links_manager/api_views.py personal_links_manager/urls.py linktree_project/urls.py personal_links_manager/tests/test_media.py
git commit -m "Add the media upload endpoint"
```

---

### Task 3: `prune_media` command

**Files:**
- Create: `personal_links_manager/management/commands/prune_media.py`
- Test: `personal_links_manager/tests/test_prune_media.py`

**Interfaces:**
- Consumes: `MediaAsset`, `LinkPage.draft_layout` / `published_layout`.
- Produces: `manage.py prune_media`, which prints `Removed <n> media assets (<bytes> bytes).`

- [ ] **Step 1: Write the failing tests**

`personal_links_manager/tests/test_prune_media.py`:

```python
from datetime import timedelta

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
    document = page.draft_layout
    links = next(s for s in document["sections"] if s["type"] == "links")
    url = f"https://example.com/media/{asset.id}.mp4"
    links["items"] = [link_tile("Talk", {"type": "video", "src": url, "poster": url})]
    return document


def run():
    from io import StringIO

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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `venv/bin/pytest personal_links_manager/tests/test_prune_media.py -q`
Expected: FAIL with `CommandError: Unknown command: 'prune_media'`.

- [ ] **Step 3: Implement the command**

`personal_links_manager/management/commands/prune_media.py`:

```python
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `venv/bin/pytest personal_links_manager/tests/test_prune_media.py -q`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add personal_links_manager/management/commands/prune_media.py personal_links_manager/tests/test_prune_media.py
git commit -m "Add the prune_media command"
```

---

### Task 4: Production storage and serving

**Files:**
- Modify: `docker-compose.prod.yml`
- Modify: `nginx.conf.template:22` and the HTTPS `server` block
- Modify: `Dockerfile.prod` (web stage, the `RUN mkdir -p /app/staticfiles` line)
- Modify: `docs/deployment.md`

**Interfaces:**
- Consumes: `MEDIA_ROOT = /app/media` in the image (Task 1).
- Produces: `/media/` served by nginx, and a `media_data` volume.

- [ ] **Step 1: Create the media folder in the image, owned by the app user**

In `Dockerfile.prod`, change

```dockerfile
RUN mkdir -p /app/staticfiles && chown django:django /app/staticfiles
```

to

```dockerfile
# /app/media is where the media_data volume mounts. A new named volume
# copies this folder's ownership, so the django user can write uploads.
RUN mkdir -p /app/staticfiles /app/media && chown django:django /app/staticfiles /app/media
```

- [ ] **Step 2: Add the volume**

In `docker-compose.prod.yml`, under `web:` add (after `depends_on`'s block, at the same indent as `environment:`):

```yaml
    volumes:
      - media_data:/app/media
```

Under `nginx:` → `volumes:`, add:

```yaml
      - media_data:/app/media:ro
```

Under the top-level `volumes:`, add `  media_data:`.

- [ ] **Step 3: Serve `/media/` in nginx**

In `nginx.conf.template`, change `client_max_body_size 20M;` to

```nginx
    # Room for a 20 MB video upload plus multipart overhead (personal_links_manager/media.py).
    client_max_body_size 25M;
```

After the existing `location /static/ { … }` block in the same server, add:

```nginx
    # Uploaded media. Names are UUIDs and never reused, so caching is safe;
    # nosniff stops browsers treating a file as anything but its type.
    location /media/ {
        alias /app/media/;
        add_header X-Content-Type-Options nosniff;
        expires 30d;
    }
```

- [ ] **Step 4: Check the configs parse**

Run: `docker compose -f docker-compose.prod.yml config --quiet && echo ok`
Expected: `ok`

Run: `docker run --rm -v "$PWD/nginx.conf.template:/t:ro" nginx:1.27-alpine sh -c "sed 's/\${DOMAIN}/localhost/g' /t > /etc/nginx/conf.d/default.conf && mkdir -p /etc/letsencrypt/live/localhost && apk add -q openssl && openssl req -x509 -nodes -newkey rsa:2048 -subj /CN=localhost -keyout /etc/letsencrypt/live/localhost/privkey.pem -out /etc/letsencrypt/live/localhost/fullchain.pem 2>/dev/null; nginx -t"`
Expected: `nginx: configuration file /etc/nginx/nginx.conf test is successful`. If the template references other files (e.g. `options-ssl-nginx.conf`) and the test fails only on those, note it and move on: the change is two plain directives.

- [ ] **Step 5: Document it**

In `docs/deployment.md`, in the "Common operations" code block, add:

```bash
# Delete uploaded media that no page uses (run daily, e.g. from cron)
docker compose -f docker-compose.prod.yml exec -T web python manage.py prune_media
```

Under "Known gaps", add:

```markdown
- Uploaded media (`media_data` volume) isn't backed up either. Losing it breaks every uploaded tile background; the layouts keep their URLs.
```

- [ ] **Step 6: Commit**

```bash
git add Dockerfile.prod docker-compose.prod.yml nginx.conf.template docs/deployment.md
git commit -m "Serve uploaded media from a volume in production"
```

---

### Task 5: Editor upload slots, state and Upload buttons (Elm, no HTTP)

**Files:**
- Modify: `elm/src/PageEditor/Editor.elm`
- Modify: `static/css/page_editor.css`
- Test: `elm/tests/PageEditor/EditorTest.elm`

**Interfaces:**
- Produces (all exported from `PageEditor.Editor`):
  - `type Slot = VideoSrc | VideoPoster | ImageSrc`
  - `type alias UploadTarget = { sectionId : String, itemId : String, slot : Slot }`
  - `type UploadState = Uploading Int | UploadFailed String`, where `Int` is the percent sent (0–100).
  - `Model` gains `uploads : Dict String { target : UploadTarget, state : UploadState }`.
  - `Msg` gains `RequestUpload UploadTarget`, which is a no-op in `Editor.update`; `Main` intercepts it.
  - `uploadKey : UploadTarget -> String`, used as the Http tracker name.
  - `slotKind : Slot -> String`, giving `"video"` or `"image"`.
  - `acceptedTypes : Slot -> List String`, the MIME types for the file picker.
  - `uploadStarted : UploadTarget -> Model -> Model`
  - `uploadProgress : UploadTarget -> Int -> Model -> Model`
  - `uploadFinished : UploadTarget -> Result String String -> Model -> Model`, where `Ok` carries the URL.
  - `uploadsInProgress : Model -> List UploadTarget`
  - `isUploading : Model -> Bool`

- [ ] **Step 1: Write the failing tests**

In `elm/tests/PageEditor/EditorTest.elm`, extend the `PageEditor.Editor` import to `exposing (Direction(..), HeroField(..), Msg(..), Slot(..))`, change the sample layout's tile `"b"` background to `Video { src = "", poster = "" }`, and add these tests to `suite`'s list. (If an existing test relies on `b`'s background being `Solid`, give the video background to a new tile `"c"` instead and use `"c"` below.)

```elm
        , describe "uploads"
            (let
                videoSrc =
                    { sectionId = "links", itemId = "b", slot = VideoSrc }

                poster =
                    { sectionId = "links", itemId = "b", slot = VideoPoster }

                start =
                    Editor.init 42 layout

                backgroundOf id model =
                    model.layout.sections
                        |> List.concatMap
                            (\section ->
                                case section.content of
                                    Links tiles ->
                                        tiles

                                    _ ->
                                        []
                            )
                        |> List.filter (\tile -> tile.id == id)
                        |> List.map
                            (\tile ->
                                case tile.content of
                                    LinkTile link ->
                                        link.background
                            )
                        |> List.head
             in
             [ test "a started upload blocks saving until it finishes" <|
                \_ ->
                    let
                        uploading =
                            Editor.uploadStarted videoSrc start
                    in
                    Expect.equal
                        ( Editor.isUploading uploading
                        , Editor.isUploading (Editor.uploadFinished videoSrc (Ok "https://x.example/media/a.mp4") uploading)
                        )
                        ( True, False )
             , test "a finished upload fills its slot" <|
                \_ ->
                    start
                        |> Editor.uploadStarted videoSrc
                        |> Editor.uploadFinished videoSrc (Ok "https://x.example/media/a.mp4")
                        |> Editor.uploadStarted poster
                        |> Editor.uploadFinished poster (Ok "https://x.example/media/p.png")
                        |> backgroundOf "b"
                        |> Expect.equal (Just (Video { src = "https://x.example/media/a.mp4", poster = "https://x.example/media/p.png" }))
             , test "progress is tracked per slot" <|
                \_ ->
                    start
                        |> Editor.uploadStarted videoSrc
                        |> Editor.uploadProgress videoSrc 42
                        |> Editor.uploadsInProgress
                        |> Expect.equal [ videoSrc ]
             , test "a failed upload keeps the field and stops blocking saves" <|
                \_ ->
                    let
                        failed =
                            start
                                |> Editor.uploadStarted videoSrc
                                |> Editor.uploadFinished videoSrc (Err "Videos can be at most 20 MB.")
                    in
                    Expect.equal ( backgroundOf "b" failed, Editor.isUploading failed )
                        ( Just (Video { src = "", poster = "" }), False )
             , test "an upload that finishes after the background changed kind is dropped" <|
                \_ ->
                    start
                        |> Editor.uploadStarted videoSrc
                        |> Editor.update (SetLinkBackground "links" "b" (Solid "#112233"))
                        |> Editor.uploadFinished videoSrc (Ok "https://x.example/media/a.mp4")
                        |> backgroundOf "b"
                        |> Expect.equal (Just (Solid "#112233"))
             , test "an upload that finishes after its tile was removed changes nothing" <|
                \_ ->
                    let
                        removed =
                            start
                                |> Editor.uploadStarted videoSrc
                                |> Editor.update (RemoveItem "links" "b")
                    in
                    Editor.uploadFinished videoSrc (Ok "https://x.example/media/a.mp4") removed
                        |> .layout
                        |> Expect.equal removed.layout
             , test "slots map to the server's kinds" <|
                \_ ->
                    List.map Editor.slotKind [ VideoSrc, VideoPoster, ImageSrc ]
                        |> Expect.equal [ "video", "image", "image" ]
             , test "localhost URLs, as uploads return in development, are accepted" <|
                \_ ->
                    List.map Editor.urlProblem
                        [ "http://localhost:8000/media/a.mp4", "http://localhost/media/a.mp4", "https://localhost" ]
                        |> Expect.equal [ Nothing, Nothing, Nothing ]
             ]
            )
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd elm && npx elm-test tests/PageEditor/EditorTest.elm`
Expected: compile error, `Slot` / `uploadStarted` not exposed.

- [ ] **Step 3: Implement state and update functions**

In `elm/src/PageEditor/Editor.elm`:

Add to the `exposing` list: `Slot(..)`, `UploadState(..)`, `UploadTarget`, `acceptedTypes`, `isUploading`, `slotKind`, `uploadFinished`, `uploadKey`, `uploadProgress`, `uploadStarted`, `uploadsInProgress`. Add `import Dict exposing (Dict)`.

Change `Model` and `init`:

```elm
type alias Model =
    { layout : Layout

    -- The link tile whose fields are shown; the others are collapsed.
    , openTile : Maybe String

    -- For the ids of new items.
    , seed : Random.Seed

    -- Uploads in progress or failed, by uploadKey. PageEditor.Main sends
    -- the requests and reports back through uploadProgress/uploadFinished.
    , uploads : Dict String { target : UploadTarget, state : UploadState }
    }


init : Int -> Layout -> Model
init idSeed layout =
    { layout = layout
    , openTile = Nothing
    , seed = Random.initialSeed idSeed
    , uploads = Dict.empty
    }


{-| A background field a file can be uploaded into.
-}
type Slot
    = VideoSrc
    | VideoPoster
    | ImageSrc


type alias UploadTarget =
    { sectionId : String
    , itemId : String
    , slot : Slot
    }


type UploadState
    = Uploading Int
    | UploadFailed String
```

Add `| RequestUpload UploadTarget` to `Msg` with the doc line `-- Handled by PageEditor.Main, which picks the file and uploads it.` above it.

In `update`, add:

```elm
        RequestUpload _ ->
            model
```

and change the `SetLinkBackground` branch so a manual edit clears that tile's failed uploads (uploads in progress are kept):

```elm
        SetLinkBackground sectionId itemId background ->
            { model | uploads = Dict.filter (\_ upload -> upload.target.itemId /= itemId || isInProgress upload.state) model.uploads }
                |> mapSection sectionId (mapTiles (updateById itemId (mapLink (\link -> { link | background = background }))))
```

Add, after `defaultTileColor`:

```elm
-- UPLOADS


uploadKey : UploadTarget -> String
uploadKey target =
    target.itemId ++ "/" ++ slotName target.slot


slotName : Slot -> String
slotName slot =
    case slot of
        VideoSrc ->
            "video-src"

        VideoPoster ->
            "video-poster"

        ImageSrc ->
            "image-src"


{-| The `kind` the upload endpoint checks the file against.
-}
slotKind : Slot -> String
slotKind slot =
    case slot of
        VideoSrc ->
            "video"

        _ ->
            "image"


{-| What the file picker offers; the server checks the bytes anyway.
-}
acceptedTypes : Slot -> List String
acceptedTypes slot =
    case slot of
        VideoSrc ->
            [ "video/mp4", "video/webm" ]

        _ ->
            [ "image/jpeg", "image/png", "image/webp" ]


isInProgress : UploadState -> Bool
isInProgress state =
    case state of
        Uploading _ ->
            True

        UploadFailed _ ->
            False


uploadStarted : UploadTarget -> Model -> Model
uploadStarted target model =
    { model | uploads = Dict.insert (uploadKey target) { target = target, state = Uploading 0 } model.uploads }


uploadProgress : UploadTarget -> Int -> Model -> Model
uploadProgress target percent model =
    { model
        | uploads =
            Dict.update (uploadKey target)
                (Maybe.map (\upload -> { upload | state = Uploading percent }))
                model.uploads
    }


{-| Puts an uploaded file's URL into its slot, if the tile still has a
background of that kind; or keeps the error to show under the field.
-}
uploadFinished : UploadTarget -> Result String String -> Model -> Model
uploadFinished target result model =
    case result of
        Ok url ->
            { model | uploads = Dict.remove (uploadKey target) model.uploads }
                |> mapSection target.sectionId
                    (mapTiles (updateById target.itemId (mapLink (\link -> { link | background = fillSlot target.slot url link.background }))))

        Err message ->
            { model | uploads = Dict.insert (uploadKey target) { target = target, state = UploadFailed message } model.uploads }


fillSlot : Slot -> String -> TileBackground -> TileBackground
fillSlot slot url background =
    case ( slot, background ) of
        ( VideoSrc, Video clip ) ->
            Video { clip | src = url }

        ( VideoPoster, Video clip ) ->
            Video { clip | poster = url }

        ( ImageSrc, Image _ ) ->
            Image url

        _ ->
            background


uploadsInProgress : Model -> List UploadTarget
uploadsInProgress model =
    Dict.values model.uploads
        |> List.filter (.state >> isInProgress)
        |> List.map .target


isUploading : Model -> Bool
isUploading model =
    not (List.isEmpty (uploadsInProgress model))


uploadState : Model -> UploadTarget -> Maybe UploadState
uploadState model target =
    Dict.get (uploadKey target) model.uploads |> Maybe.map .state
```

- [ ] **Step 4: Accept `localhost` in `urlProblem`**

In `urlProblem`, change the host check from

```elm
                if String.contains "." name && not (String.contains " " url) then
```

to

```elm
                -- localhost: uploads return the server's own URL, which is
                -- localhost in development.
                if (String.contains "." name || isLocalhost name) && not (String.contains " " url) then
```

and add:

```elm
isLocalhost : String -> Bool
isLocalhost host =
    host == "localhost" || String.startsWith "localhost:" host
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd elm && npx elm-test`
Expected: all pass. The view doesn't compile-check `RequestUpload` yet, but nothing else references it.

- [ ] **Step 6: Add the Upload buttons to the view**

Change `viewLinkFields`'s last line to `, viewBackgroundFields model sectionId itemId link.background`. Change `viewLinkFields`'s signature to `Model -> String -> String -> Link -> List (Html Msg)` and its call in `viewTile` to `viewLinkFields model sectionId tile.id link`.

Change `viewBackgroundFields`'s signature and opening:

```elm
viewBackgroundFields : Model -> String -> String -> TileBackground -> Html Msg
viewBackgroundFields model sectionId itemId background =
    let
        toMsg =
            SetLinkBackground sectionId itemId

        target slot =
            { sectionId = sectionId, itemId = itemId, slot = slot }
```

(keep the existing `kindButton` and `( isSolid, isImage, isVideo )` bindings), and replace the `Image url ->` and `Video clip ->` branches of `fields` with:

```elm
                Image url ->
                    [ mediaField model
                        (target ImageSrc)
                        { label = "Image URL"
                        , value = url
                        , placeholder = "https://"
                        , toMsg = \u -> toMsg (Image u)
                        }
                    ]

                Video clip ->
                    [ mediaField model
                        (target VideoSrc)
                        { label = "Video URL"
                        , value = clip.src
                        , placeholder = "https://….mp4"
                        , toMsg = \u -> toMsg (Video { clip | src = u })
                        }
                    , mediaField model
                        (target VideoPoster)
                        { label = "Poster image URL"
                        , value = clip.poster
                        , placeholder = "Shown before the video plays"
                        , toMsg = \u -> toMsg (Video { clip | poster = u })
                        }
                    ]
```

Add to VIEW HELPERS:

```elm
{-| A URL field with an Upload button beside it. While uploading, the
field is locked and the button shows progress; a failed upload's message
replaces the URL problem until the next edit.
-}
mediaField :
    Model
    -> UploadTarget
    -> { label : String, value : String, placeholder : String, toMsg : String -> Msg }
    -> Html Msg
mediaField model target config =
    let
        state =
            uploadState model target

        uploading =
            case state of
                Just (Uploading percent) ->
                    Just percent

                _ ->
                    Nothing

        problem =
            case state of
                Just (UploadFailed message) ->
                    Just message

                Just (Uploading _) ->
                    Nothing

                Nothing ->
                    urlProblem config.value
    in
    div [ class "editor-field" ]
        [ label [ class "editor-media-field" ]
            [ span [ class "editor-field-label" ] [ text config.label ]
            , div [ class "editor-media-row" ]
                [ input
                    [ type_ "text"
                    , class "editor-input"
                    , classList [ ( "editor-input-invalid", problem /= Nothing ) ]
                    , value config.value
                    , placeholder config.placeholder
                    , maxlength 2000
                    , disabled (uploading /= Nothing)
                    , onInput config.toMsg
                    ]
                    []
                , button
                    [ type_ "button"
                    , class "editor-upload-button"
                    , attribute "aria-label" ("Upload " ++ String.toLower config.label)
                    , disabled (uploading /= Nothing)
                    , onClick (RequestUpload target)
                    ]
                    (case uploading of
                        Just percent ->
                            [ text ("Uploading… " ++ String.fromInt percent ++ "%") ]

                        Nothing ->
                            [ i [ class "fa-solid fa-arrow-up-from-bracket", attribute "aria-hidden" "true" ] []
                            , text "Upload"
                            ]
                    )
                ]
            ]
        , case problem of
            Just message ->
                span [ class "editor-field-problem" ] [ text message ]

            Nothing ->
                text ""
        ]
```

The button sits outside the `<label>`'s text but inside the label element, so `get_by_label("Video URL")` still finds the input. If Playwright's label lookup gets ambiguous because of the button, move the button out of the `label` into the `editor-media-row` div wrapping both, and keep the `label` around the span + input only.

- [ ] **Step 7: Style it**

Append to `static/css/page_editor.css`:

```css
/* A URL field with its Upload button (Editor.mediaField). */
.editor-media-row {
    display: flex;
    gap: 0.5rem;
    align-items: stretch;
}

.editor-media-row .editor-input {
    flex: 1;
    min-width: 0;
}

.editor-upload-button {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    white-space: nowrap;
    padding: 0 0.75rem;
    border: 1px solid var(--editor-border, #d4d4d8);
    border-radius: 0.5rem;
    background: var(--editor-surface, #fff);
    font: inherit;
    cursor: pointer;
}

.editor-upload-button:disabled {
    cursor: progress;
    opacity: 0.7;
}
```

Before committing, check the custom property names against the ones `page_editor.css` already uses for `.editor-input` borders and backgrounds (`grep -n "editor-input {" -A12 static/css/page_editor.css`), and use those.

- [ ] **Step 8: Compile and test**

Run: `cd elm && npx elm make src/PageEditor/Main.elm --output=/dev/null && npx elm-test`
Expected: `Success!` and all tests pass. Main still compiles: it maps `Editor.view` and never constructs `RequestUpload`.

- [ ] **Step 9: Commit**

```bash
git add elm/src/PageEditor/Editor.elm elm/tests/PageEditor/EditorTest.elm static/css/page_editor.css
git commit -m "Track uploads and show Upload buttons in the page editor"
```

---

### Task 6: Main sends uploads (file picker, multipart, progress, Save blocking)

**Files:**
- Modify: `elm/elm.json`
- Modify: `elm/src/PageEditor/Main.elm`
- Test: `elm/tests/PageEditor/MainTest.elm`

**Interfaces:**
- Consumes: everything Task 5 produces. Also `/api/media/` from Task 2: multipart `kind` + `file`, answering `{id, kind, url}`.
- Produces: `PageEditor.Main.uploadErrorMessage : Int -> String -> String`, exposed for tests.

- [ ] **Step 1: Make `elm/file` a direct dependency**

In `elm/elm.json`, move `"elm/file": "1.0.5"` from `"indirect"` to `"direct"`, keeping both lists alphabetical.

- [ ] **Step 2: Write the failing tests**

In `elm/tests/PageEditor/MainTest.elm`, change the import to `import PageEditor.Main exposing (Device(..), deviceWidth, flagsDecoder, uploadErrorMessage)` and add a suite. The module must expose it: add `uploadSuite` to its `exposing` list. Check how the existing `deviceSuite` is exposed and do the same.

```elm
uploadSuite : Test
uploadSuite =
    describe "uploadErrorMessage"
        [ test "shows the server's message as it is" <|
            \_ ->
                uploadErrorMessage 400 """{"file": ["Videos can be at most 20 MB."]}"""
                    |> Expect.equal "Videos can be at most 20 MB."
        , test "explains nginx's 413, which has no JSON body" <|
            \_ ->
                uploadErrorMessage 413 "<html><body>413 Request Entity Too Large</body></html>"
                    |> Expect.equal "That file is too big. Videos can be at most 20 MB."
        , test "asks to sign in again on 403" <|
            \_ ->
                uploadErrorMessage 403 ""
                    |> Expect.equal "Your session has expired. Sign in again in another tab, then retry."
        , test "falls back to a generic message" <|
            \_ ->
                uploadErrorMessage 500 ""
                    |> Expect.equal "Couldn't upload the file (error 500). Try again."
        ]
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd elm && npx elm-test tests/PageEditor/MainTest.elm`
Expected: compile error, `uploadErrorMessage` not exposed.

- [ ] **Step 4: Implement**

In `elm/src/PageEditor/Main.elm`:

Imports: add `import File exposing (File)` and `import File.Select`. Add `uploadErrorMessage` to the module's `exposing` list.

Add to `Msg`:

```elm
    | FileChosen Editor.UploadTarget File
    | GotUploadProgress Editor.UploadTarget Http.Progress
    | GotUploaded Editor.UploadTarget (Result String String)
```

In `update`, put this branch **before** the general `EditorMsg editorMsg ->` branch:

```elm
        EditorMsg (Editor.RequestUpload target) ->
            ( model, File.Select.file (Editor.acceptedTypes target.slot) (FileChosen target) )
```

And add:

```elm
        FileChosen target file ->
            ( { model | editor = Editor.uploadStarted target model.editor }
            , Http.request
                { method = "POST"
                , headers = [ Http.header "X-CSRFToken" model.flags.csrfToken ]
                , url = model.flags.apiBase ++ "media/"
                , body =
                    Http.multipartBody
                        [ Http.stringPart "kind" (Editor.slotKind target.slot)
                        , Http.filePart "file" file
                        ]
                , expect = expectJsonWith uploadErrorMessage (GotUploaded target) (Decode.field "url" Decode.string)
                , timeout = Nothing
                , tracker = Just (Editor.uploadKey target)
                }
            )

        GotUploadProgress target progress ->
            case progress of
                Http.Sending sending ->
                    ( { model | editor = Editor.uploadProgress target (round (100 * Http.fractionSent sending)) model.editor }
                    , Cmd.none
                    )

                Http.Receiving _ ->
                    ( model, Cmd.none )

        GotUploaded target result ->
            ( { model | editor = Editor.uploadFinished target result model.editor }, Cmd.none )
```

Block Save and Publish while uploading. Change `isBusy`'s use in `canSave` and `canPublish` by adding `&& not (Editor.isUploading model.editor)` to both.

Generalise `expectJson`:

```elm
expectJson : (Result String a -> msg) -> Decoder a -> Http.Expect msg
expectJson =
    expectJsonWith statusMessage


{-| Like Http.expectJson, but failures become a message for the person
editing, made by `messageFor status body` for error statuses.
-}
expectJsonWith : (Int -> String -> String) -> (Result String a -> msg) -> Decoder a -> Http.Expect msg
expectJsonWith messageFor toMsg decoder =
    Http.expectStringResponse toMsg
        (\response ->
            case response of
                Http.GoodStatus_ _ body ->
                    Decode.decodeString decoder body
                        |> Result.mapError (\_ -> "The server sent an unexpected response.")

                Http.BadStatus_ metadata body ->
                    Err (messageFor metadata.statusCode body)

                Http.NetworkError_ ->
                    Err "Couldn't reach the server. Check your connection and try again."

                Http.Timeout_ ->
                    Err "The server took too long to answer. Try again."

                Http.BadUrl_ _ ->
                    Err "Couldn't send the request."
        )
```

Delete the old `expectJson` body; its doc comment moves to `expectJsonWith`.

Add:

```elm
{-| Upload errors are shown under the field, so the server's message
(personal\_links\_manager/media.py) is used as it is.
-}
uploadErrorMessage : Int -> String -> String
uploadErrorMessage status body =
    case status of
        400 ->
            case Decode.decodeString errorMessagesDecoder body of
                Ok (first :: _) ->
                    first

                _ ->
                    "Couldn't upload the file."

        403 ->
            "Your session has expired. Sign in again in another tab, then retry."

        -- From nginx's client_max_body_size, before Django sees the file.
        413 ->
            "That file is too big. Videos can be at most 20 MB."

        _ ->
            "Couldn't upload the file (error " ++ String.fromInt status ++ "). Try again."
```

Subscriptions: replace `subscriptions = \_ -> Sub.none` in `main` with `subscriptions = subscriptions` and add:

```elm
subscriptions : Model -> Sub Msg
subscriptions model =
    Editor.uploadsInProgress model.editor
        |> List.map (\target -> Http.track (Editor.uploadKey target) (GotUploadProgress target))
        |> Sub.batch
```

`updateAndGuard` needs no change: uploads only change the layout through `uploadFinished`, and the existing unsaved check compares layouts.

- [ ] **Step 5: Run the tests**

Run: `cd elm && npx elm make src/PageEditor/Main.elm --output=/dev/null && npx elm-test`
Expected: `Success!`, all tests pass.

Run: `venv/bin/pytest frontend/tests/test_elm.py -q`
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add elm/elm.json elm/src/PageEditor/Main.elm elm/tests/PageEditor/MainTest.elm
git commit -m "Upload tile background files from the page editor"
```

---

### Task 7: End-to-end upload test

**Files:**
- Test: `e2e/test_page_editor.py` (append)

**Interfaces:**
- Consumes: the whole feature; the `demo_user`, `demo_page_with_layout` and `open_editor` helpers already in `e2e/`; `personal_links_manager.tests.media_samples`.

- [ ] **Step 1: Write the test**

The first tile of `sample_layout()` is the video tile "Watch my talk". Append to `e2e/test_page_editor.py`:

```python
from personal_links_manager.tests import media_samples


def test_uploading_a_video_and_poster_sets_the_tile_background(
    page, live_server, demo_user, demo_page_with_layout, settings, tmp_path
):
    settings.MEDIA_ROOT = tmp_path
    settings.DEBUG = True  # so Django serves /media/, like runserver
    open_editor(page, live_server, demo_user, demo_page_with_layout)
    page.locator(".editor-item-toggle", has_text="Watch my talk").click()
    item = page.locator(".editor-item-open")

    with page.expect_file_chooser() as chooser:
        item.get_by_role("button", name="Upload video url").click()
    chooser.value.set_files(
        files=[{"name": "talk.mp4", "mimeType": "video/mp4", "buffer": media_samples.MP4}]
    )
    expect(item.get_by_label("Video URL")).to_have_value(re.compile(r"/media/[0-9a-f-]{36}\.mp4$"))

    with page.expect_file_chooser() as chooser:
        item.get_by_role("button", name="Upload poster image url").click()
    chooser.value.set_files(
        files=[{"name": "poster.png", "mimeType": "image/png", "buffer": media_samples.PNG}]
    )
    expect(item.get_by_label("Poster image URL")).to_have_value(re.compile(r"/media/[0-9a-f-]{36}\.png$"))

    video = page.locator(".preview-frame .lp-tile--video video.lp-tile-media").first
    expect(video).to_have_attribute("src", re.compile(r"/media/.+\.mp4$"))
    expect(video).to_have_attribute("poster", re.compile(r"/media/.+\.png$"))

    page.locator("button.editor-action", has_text="Save").click()
    expect(page.locator(".editor-status")).to_have_text(re.compile("^Saved"))
    page.reload()
    expect(page.locator(".preview-frame .lp-tile--video video.lp-tile-media").first).to_have_attribute(
        "src", re.compile(r"/media/.+\.mp4$")
    )


def test_a_rejected_upload_shows_the_servers_message(
    page, live_server, demo_user, demo_page_with_layout, settings, tmp_path
):
    settings.MEDIA_ROOT = tmp_path
    open_editor(page, live_server, demo_user, demo_page_with_layout)
    page.locator(".editor-item-toggle", has_text="Watch my talk").click()
    item = page.locator(".editor-item-open")

    with page.expect_file_chooser() as chooser:
        item.get_by_role("button", name="Upload video url").click()
    chooser.value.set_files(
        files=[{"name": "photo.mp4", "mimeType": "video/mp4", "buffer": media_samples.HEIC}]
    )

    expect(item.locator(".editor-field-problem")).to_have_text("Upload an MP4 or WebM video.")
```

The video won't play (the bytes are only a signature), so the test asserts attributes, not playback. If `settings.DEBUG = True` doesn't make `static()` serve media, because URLconfs are loaded once, drop that line: the test only checks attributes and the saved layout, not that the file loads.

- [ ] **Step 2: Run the e2e tests**

Run: `venv/bin/pytest e2e/test_page_editor.py -q -k "upload"`
Expected: 2 passed.

- [ ] **Step 3: Run the whole suite**

Run: `venv/bin/pytest -q --create-db && (cd elm && npx elm-test)`
Expected: everything passes.

- [ ] **Step 4: Commit**

```bash
git add e2e/test_page_editor.py
git commit -m "Test uploading tile backgrounds end to end"
```
