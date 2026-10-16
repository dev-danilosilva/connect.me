"""Versioned page layout documents (docs/page-layout-spec-v1.md).

A page's layout is a JSON document with a top-level `version`. Stored
documents are always at CURRENT_VERSION: when the spec changes, add the new
version's serializer to SERIALIZERS, an upgrade step to UPGRADES, and a data
migration that runs `upgrade` over stored layouts.
"""

import json
import uuid

from rest_framework.exceptions import ValidationError

from . import v1

CURRENT_VERSION = v1.VERSION

SERIALIZERS = {
    1: v1.LayoutV1Serializer,
}

# version n -> function turning an n document into an n+1 document.
UPGRADES = {}


def upgrade(document):
    """Brings a document of any supported version up to CURRENT_VERSION."""
    version = document.get("version") if isinstance(document, dict) else None
    supported = isinstance(version, int) and not isinstance(version, bool)
    if not supported or not 1 <= version <= CURRENT_VERSION:
        raise ValidationError({"version": [f"Unsupported layout version: {version!r}."]})
    while version < CURRENT_VERSION:
        document = UPGRADES[version](document)
        version = document["version"]
    return document


def validate(document):
    """Returns the document, upgraded and cleaned, or raises ValidationError."""
    serializer = SERIALIZERS[CURRENT_VERSION](data=upgrade(document))
    serializer.is_valid(raise_exception=True)
    # Plain dicts and lists, ready for a JSONField.
    return json.loads(json.dumps(serializer.validated_data))


def new_id():
    return str(uuid.uuid4())


def default_layout(page):
    """A new page: its title as the hero's name, and nothing else yet."""
    return {
        "version": CURRENT_VERSION,
        "sections": [
            {
                "id": new_id(),
                "type": "hero",
                "displayName": page.title,
                "bio": "",
                "imageUrl": "",
            },
            {"id": new_id(), "type": "socials", "items": []},
            {"id": new_id(), "type": "links", "items": []},
        ],
    }
