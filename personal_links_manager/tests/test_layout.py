import pytest
from rest_framework.exceptions import ValidationError

from personal_links_manager import layout
from personal_links_manager.layout import v1
from personal_links_manager.models import LinkPage

from .layouts import hero_section, link_tile, links_section, sample_layout, socials_section


def links(document):
    return next(s for s in document["sections"] if s["type"] == "links")


def test_a_valid_document_round_trips():
    document = sample_layout()
    assert layout.validate(document) == document


def test_sections_may_come_in_any_order_and_repeat_except_the_hero():
    document = {
        "version": 1,
        "sections": [links_section(), socials_section(), hero_section(), links_section()],
    }
    assert layout.validate(document) == document


def test_a_page_may_have_no_sections():
    assert layout.validate({"version": 1, "sections": []})["sections"] == []


@pytest.mark.parametrize("version", [None, 0, 2, "1", True])
def test_unsupported_versions_are_rejected(version):
    document = sample_layout()
    document["version"] = version
    with pytest.raises(ValidationError) as error:
        layout.validate(document)
    assert "version" in error.value.detail


def test_a_missing_version_is_rejected():
    document = sample_layout()
    del document["version"]
    with pytest.raises(ValidationError):
        layout.validate(document)


def test_unknown_keys_are_rejected_at_every_level():
    for target in ["document", "section", "tile", "background"]:
        document = sample_layout()
        tile = links(document)["items"][0]
        node = {
            "document": document,
            "section": document["sections"][0],
            "tile": tile,
            "background": tile["background"],
        }[target]
        node["theme"] = "dark"
        with pytest.raises(ValidationError):
            layout.validate(document)


def test_missing_keys_are_rejected():
    document = sample_layout()
    del document["sections"][0]["bio"]
    with pytest.raises(ValidationError):
        layout.validate(document)


def test_unknown_section_type_is_rejected():
    document = sample_layout()
    document["sections"].append({"id": layout.new_id(), "type": "gallery", "items": []})
    with pytest.raises(ValidationError):
        layout.validate(document)


def test_unknown_tile_type_is_rejected():
    document = sample_layout()
    links(document)["items"].append(
        {"id": layout.new_id(), "type": "spotify", "url": "https://open.spotify.com/track/1"}
    )
    with pytest.raises(ValidationError):
        layout.validate(document)


def test_gradient_backgrounds_are_not_part_of_v1():
    document = sample_layout()
    links(document)["items"].append(
        link_tile("Notes", {"type": "gradient", "value": "linear-gradient(#000, #fff)"})
    )
    with pytest.raises(ValidationError):
        layout.validate(document)


@pytest.mark.parametrize(
    "url", ["javascript:alert(1)", "data:text/html,hi", "ftp://example.com/", "example.com", ""]
)
def test_link_urls_must_be_http(url):
    document = sample_layout()
    links(document)["items"][0]["url"] = url
    with pytest.raises(ValidationError):
        layout.validate(document)


def test_the_hero_image_may_be_blank_but_not_another_scheme():
    document = sample_layout()
    document["sections"][0]["imageUrl"] = ""
    layout.validate(document)

    document["sections"][0]["imageUrl"] = "javascript:alert(1)"
    with pytest.raises(ValidationError):
        layout.validate(document)


@pytest.mark.parametrize("color", ["red", "#fff", "#4c1d95; background: url(x)", "rgb(0,0,0)"])
def test_solid_colors_must_be_hex(color):
    document = sample_layout()
    links(document)["items"].append(link_tile("Call", {"type": "solid", "color": color}))
    with pytest.raises(ValidationError):
        layout.validate(document)


def test_unknown_social_networks_are_rejected():
    document = sample_layout()
    document["sections"][1]["items"][0]["network"] = "myspace"
    with pytest.raises(ValidationError):
        layout.validate(document)


def test_ids_must_be_uuids():
    document = sample_layout()
    document["sections"][0]["id"] = "hero"
    with pytest.raises(ValidationError):
        layout.validate(document)


def test_ids_must_be_unique_across_sections_and_items():
    document = sample_layout()
    links(document)["items"][1]["id"] = document["sections"][0]["id"]
    with pytest.raises(ValidationError) as error:
        layout.validate(document)
    assert "unique" in str(error.value.detail)


def test_a_page_has_at_most_one_hero():
    document = sample_layout()
    document["sections"].append(hero_section())
    with pytest.raises(ValidationError) as error:
        layout.validate(document)
    assert "hero" in str(error.value.detail)


def test_lists_are_capped():
    document = sample_layout()
    links(document)["items"] = [
        link_tile(f"Link {n}", {"type": "solid", "color": "#000000"})
        for n in range(v1.MAX_LINK_TILES + 1)
    ]
    with pytest.raises(ValidationError):
        layout.validate(document)

    document = {"version": 1, "sections": [links_section() for _ in range(v1.MAX_SECTIONS + 1)]}
    with pytest.raises(ValidationError):
        layout.validate(document)


def test_labels_are_capped():
    document = sample_layout()
    links(document)["items"][0]["label"] = "x" * 81
    with pytest.raises(ValidationError):
        layout.validate(document)


def test_upgrade_leaves_a_current_document_unchanged():
    document = sample_layout()
    assert layout.upgrade(document) == document


def test_default_layout_is_valid_and_uses_the_page_title():
    document = layout.default_layout(LinkPage(handle="my-page", title="My Page"))
    assert layout.validate(document) == document
    assert [s["type"] for s in document["sections"]] == ["hero", "socials", "links"]
    assert document["sections"][0]["displayName"] == "My Page"
