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
