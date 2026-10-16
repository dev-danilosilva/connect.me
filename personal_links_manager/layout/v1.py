"""Page layout spec v1 (docs/page-layout-spec-v1.md).

A layout is an ordered list of typed sections; a links section holds an
ordered list of typed tiles. Each level dispatches on `type` through a
registry (SECTION_TYPES, TILE_TYPES), so a new kind of section or tile is
one serializer added to its registry.

Validation is strict: every key is required and keys the spec doesn't
define are rejected, so a stored v1 document is exactly v1.
"""

from django.core.validators import RegexValidator, URLValidator
from rest_framework import serializers

VERSION = 1

MAX_SECTIONS = 20
MAX_LINK_TILES = 50
MAX_SOCIALS = 20

NETWORKS = [
    "instagram",
    "youtube",
    "github",
    "linkedin",
    "x",
    "tiktok",
    "facebook",
    "spotify",
    "website",
]


class StrictSerializer(serializers.Serializer):
    """Rejects keys the spec doesn't define."""

    def to_internal_value(self, data):
        if isinstance(data, dict):
            unknown = sorted(set(data) - set(self.fields))
            if unknown:
                raise serializers.ValidationError(
                    {key: ["Not part of the layout spec."] for key in unknown}
                )
        return super().to_internal_value(data)


class IdField(serializers.UUIDField):
    """A UUID, stored as its string form so the document stays plain JSON."""

    def to_internal_value(self, data):
        return str(super().to_internal_value(data))


class HttpUrlField(serializers.CharField):
    """http(s) only: the page renders these as links and media sources, so
    `javascript:` and other schemes must never get through."""

    def __init__(self, **kwargs):
        kwargs.setdefault("max_length", 2000)
        super().__init__(**kwargs)
        self.validators.append(
            URLValidator(schemes=["http", "https"], message="Enter an http(s) URL.")
        )


def type_field(name):
    return serializers.ChoiceField(choices=[name])


class Tagged(serializers.Field):
    """An object validated by the serializer its `type` key picks from
    `types`."""

    def __init__(self, types, **kwargs):
        self.types = types
        super().__init__(**kwargs)

    def to_internal_value(self, data):
        if not isinstance(data, dict):
            raise serializers.ValidationError("Expected an object.")
        kind = data.get("type")
        serializer_class = self.types.get(kind) if isinstance(kind, str) else None
        if serializer_class is None:
            raise serializers.ValidationError(
                {"type": [f"Unknown type {kind!r}; expected one of: {', '.join(self.types)}."]}
            )
        serializer = serializer_class(data=data)
        if not serializer.is_valid():
            raise serializers.ValidationError(serializer.errors)
        return serializer.validated_data

    def to_representation(self, value):
        return value


# ---- Tile backgrounds ----


class SolidBackgroundSerializer(StrictSerializer):
    type = type_field("solid")
    # Rendered into an inline style, so only a plain hex color is allowed.
    color = serializers.CharField(
        validators=[RegexValidator(r"^#[0-9a-fA-F]{6}$", "Enter a #rrggbb color.")]
    )


class ImageBackgroundSerializer(StrictSerializer):
    type = type_field("image")
    url = HttpUrlField()


class VideoBackgroundSerializer(StrictSerializer):
    type = type_field("video")
    src = HttpUrlField()
    poster = HttpUrlField()


BACKGROUND_TYPES = {
    "solid": SolidBackgroundSerializer,
    "image": ImageBackgroundSerializer,
    "video": VideoBackgroundSerializer,
}


# ---- Tiles (items of a links section) ----


class LinkTileSerializer(StrictSerializer):
    id = IdField()
    type = type_field("link")
    label = serializers.CharField(max_length=80)
    url = HttpUrlField()
    background = Tagged(BACKGROUND_TYPES)


TILE_TYPES = {
    "link": LinkTileSerializer,
}


# ---- Sections ----


class SocialItemSerializer(StrictSerializer):
    id = IdField()
    network = serializers.ChoiceField(choices=NETWORKS)
    url = HttpUrlField()


class HeroSectionSerializer(StrictSerializer):
    id = IdField()
    type = type_field("hero")
    displayName = serializers.CharField(max_length=80, allow_blank=True)
    bio = serializers.CharField(max_length=300, allow_blank=True)
    # Blank shows the hero's fallback background instead of an image.
    imageUrl = HttpUrlField(allow_blank=True)


class SocialsSectionSerializer(StrictSerializer):
    id = IdField()
    type = type_field("socials")
    items = serializers.ListField(child=SocialItemSerializer(), max_length=MAX_SOCIALS)


class LinksSectionSerializer(StrictSerializer):
    id = IdField()
    type = type_field("links")
    items = serializers.ListField(child=Tagged(TILE_TYPES), max_length=MAX_LINK_TILES)


SECTION_TYPES = {
    "hero": HeroSectionSerializer,
    "socials": SocialsSectionSerializer,
    "links": LinksSectionSerializer,
}


# ---- Document ----


class LayoutV1Serializer(StrictSerializer):
    version = serializers.IntegerField(min_value=VERSION, max_value=VERSION)
    sections = serializers.ListField(child=Tagged(SECTION_TYPES), max_length=MAX_SECTIONS)

    def validate(self, attrs):
        sections = attrs["sections"]

        ids = [section["id"] for section in sections]
        for section in sections:
            ids.extend(item["id"] for item in section.get("items", []))
        if len(ids) != len(set(ids)):
            raise serializers.ValidationError({"sections": ["Ids must be unique."]})

        if sum(section["type"] == "hero" for section in sections) > 1:
            raise serializers.ValidationError({"sections": ["A page has at most one hero."]})

        return attrs
