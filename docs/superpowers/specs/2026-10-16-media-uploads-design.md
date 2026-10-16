# Media uploads design

## Context

Link tiles can already have a video background (`{ "type": "video", "src",
"poster" }`, docs/page-layout-spec-v1.md) or an image background
(`{ "type": "image", "url" }`), but every URL has to be hosted somewhere else
and pasted in. The app has no file storage at all: no `MEDIA_ROOT`, no upload
model or endpoint, no media volume in `docker-compose.prod.yml`.

This spec lets a page owner **upload a video (and its poster image) as a tile
background** from the page editor. The same mechanism covers image
backgrounds.

## Decisions

- **The layout format does not change.** Uploading returns an absolute URL
  that the editor puts into `src`, `poster` or `url`, exactly like a pasted
  link. Spec v1 stays as it is, so there's no new version or data migration.
- **Poster stays required**, as spec v1 says. The owner uploads one or pastes
  a URL.
- **Local disk storage**: a Docker volume served by nginx. Django's storage
  API is used throughout, so moving to object storage later only means
  changing settings.
- **Validate only, no processing**: no ffmpeg, no transcoding, no background
  jobs. Files are stored exactly as uploaded.
- **`MediaAsset` records** track each upload for per-user quotas and cleanup.

## Out of scope

- Hero cover / avatar upload (roadmap: "Avatar/image upload"). The endpoint
  can serve it later, but the hero's `imageUrl` field gets no Upload button
  here.
- Transcoding, generating posters automatically, thumbnails.
- A media library UI for browsing or deleting your uploads.
- Object storage (S3/R2).

## Data model

`personal_links_manager.models.MediaAsset`:

| Field | Type | Notes |
|---|---|---|
| `id` | `UUIDField(primary_key=True, default=uuid4)` | Also the file's name, so URLs can't be guessed |
| `owner` | `ForeignKey(User, on_delete=CASCADE, related_name="media_assets")` | Quotas count per user |
| `kind` | `CharField(choices=video/image)` | |
| `file` | `FileField(upload_to=…)` | Stored at `<MEDIA_ROOT>/<uuid>.<ext>` |
| `content_type` | `CharField` | From the detected type, not the client's |
| `size_bytes` | `PositiveBigIntegerField` | |
| `created_at` | `DateTimeField(auto_now_add=True)` | Grace period for cleanup |

When an asset is deleted, its file is deleted too. This is done by a
`post_delete` signal, which also fires for bulk queryset deletes and for
cascades from a deleted user, so no path leaves files behind.

## API

`POST /api/media/`: DRF `APIView`, session auth with CSRF, logged-in users
only. The body is multipart with one `file` part.

Returns `201` and:

```json
{ "id": "…uuid…", "kind": "video", "url": "https://example.com/media/…uuid….mp4" }
```

The URL is absolute (`request.build_absolute_uri`), so it passes the
layout's http(s) URL validation unchanged.

Errors are `400` with `{ "file": ["<message>"] }`, and anonymous requests
get `403`, as with the other APIs.

### Accepted files

The type comes from the file's first bytes. The extension and the client's
`Content-Type` are ignored. The detection helper lives in
`personal_links_manager/media.py` and needs no new dependency.

| Kind | Format | Signature | Stored as | Max size |
|---|---|---|---|---|
| video | MP4 | `ftyp` at byte offset 4 | `.mp4`, `video/mp4` | 20 MB |
| video | WebM | `1A 45 DF A3` | `.webm`, `video/webm` | 20 MB |
| image | JPEG | `FF D8 FF` | `.jpg`, `image/jpeg` | 5 MB |
| image | PNG | `89 50 4E 47 0D 0A 1A 0A` | `.png`, `image/png` | 5 MB |
| image | WebP | `RIFF` … `WEBP` | `.webp`, `image/webp` | 5 MB |

SVG and every other type are rejected. SVG can carry scripts and would be
served from our own origin.

**Quota:** 200 MB per user, the sum of `size_bytes` over their assets. An
upload that would go over it is rejected.

Error messages, shown as they are in the editor:

- "Upload an MP4 or WebM video, or a JPEG, PNG or WebP image."
- "Videos can be at most 20 MB." / "Images can be at most 5 MB."
- "This upload would go over your 200 MB of media. Remove unused tiles and try again tomorrow."
  (Unreferenced files are pruned after 24 hours, see below.)

The limits are module constants in `media.py`.

## Storage and serving

- Settings: `MEDIA_ROOT = BASE_DIR / "media"` (i.e. `/app/media` in the
  image), `MEDIA_URL = "/media/"`.
- Development: `urls.py` serves media with `django.conf.urls.static.static`
  when `DEBUG` is on.
- `docker-compose.prod.yml` gets a `media_data` volume, mounted at
  `/app/media` read-write in `web` and read-only in `nginx`.
- `nginx.conf.template`:
  - `client_max_body_size` goes from `20M` to `25M`, leaving room for the
    multipart overhead on a 20 MB video.
  - A new block:
    ```nginx
    location /media/ {
        alias /app/media/;
        add_header X-Content-Type-Options nosniff;
        expires 30d;
    }
    ```
    File names are UUIDs and never reused, so long caching is safe.
- `.gitignore` ignores `media/`.

## Cleanup

`python manage.py prune_media`:

1. Collects every `/media/<uuid>.<ext>` URL found anywhere in any page's
   `draft_layout` or `published_layout`. It walks the JSON for string values,
   so it doesn't depend on which fields hold URLs.
2. Deletes `MediaAsset`s whose id is not referenced and that are **older than
   24 hours**, removing both the row and the file. The grace period protects
   uploads that haven't been saved into a draft yet.
3. Prints how many assets and bytes it removed.

`docs/deployment.md` documents running it daily from cron with
`docker compose -f docker-compose.prod.yml exec web python manage.py prune_media`.

## Editor UI

In `PageEditor/Editor.elm`, next to the **Video URL**, **Poster image URL** and
**Image URL** fields of a tile background:

- An **Upload** button opens a file picker (`elm/file`'s `File.Select.file`)
  filtered to the slot's accepted types: videos for Video URL, images for the
  other two. `elm/file` moves from indirect to direct dependencies.
- **While uploading:** the button reads "Uploading… 42%" (from `Http.track`)
  and the field is disabled.
- **On success:** the returned URL replaces the field's value, as a
  `SetLinkBackground`, so the preview updates at once. Saving works like any
  other edit.
- **On failure:** the server's message shows as the field's problem text,
  until the next edit or upload for that slot.
- **Save and Publish** are disabled while any upload is in progress.

Responsibilities:

- `Editor` stays free of HTTP. Its view emits an "upload requested" message
  naming the tile and the slot (`VideoSrc | VideoPoster | ImageUrl`) and the
  chosen `File`. It also renders upload state from a
  `Dict tileSlotKey UploadState` that it is handed.
- `Main` runs the multipart request (with the CSRF header, like save and
  publish), subscribes to progress, keeps the upload states, and passes the
  result back to `Editor`.

## Testing

**Django (pytest)**, `personal_links_manager/tests/test_media.py`:

- Accepts a small real MP4, WebM, JPEG, PNG and WebP. Each returns `201`, an
  asset row, a file on disk, and a URL under `/media/` that passes
  `layout.validate` when it's used as a video `src` or `poster`.
- Rejects an SVG, a text file renamed `.mp4`, an empty file, a video over 20
  MB, an image over 5 MB, an upload over the quota, and anonymous requests.
- Tests use `override_settings(MEDIA_ROOT=tmp_path)` and small size limits
  instead of real 20 MB files.

`prune_media` tests:

- It deletes an unreferenced asset older than 24 hours, row and file.
- It keeps a recent unreferenced asset.
- It keeps an asset referenced only by a published layout.
- It keeps an asset referenced only by a draft layout.

**Elm**:

- How upload results update the upload states and the layout.
- How errors become field problems.
- Save is blocked while an upload is in progress.

**e2e (Playwright)**, `e2e/test_page_editor.py`:

- Upload a tiny MP4 and a PNG poster on a tile.
- Check that the preview's `video.lp-tile-media` has a `/media/…` `src` and
  `poster`.
- Save, reload, and confirm both persisted.
