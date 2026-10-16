"""Sample v1 layout documents, shared by the unit and e2e tests."""

import uuid


def new_id():
    return str(uuid.uuid4())


def hero_section(display_name="Ada Lovelace"):
    return {
        "id": new_id(),
        "type": "hero",
        "displayName": display_name,
        "bio": "Mathematician · writing about the Analytical Engine and the poetry of numbers.",
        "imageUrl": "https://picsum.photos/seed/lovelace/1200/900",
    }


def socials_section():
    return {
        "id": new_id(),
        "type": "socials",
        "items": [
            {"id": new_id(), "network": network, "url": f"https://{network}.com/"}
            for network in ["instagram", "youtube", "github", "linkedin"]
        ],
    }


def link_tile(label, background, url="https://example.com/"):
    return {"id": new_id(), "type": "link", "label": label, "url": url, "background": background}


def links_section():
    return {
        "id": new_id(),
        "type": "links",
        "items": [
            link_tile(
                "Watch my talk",
                {
                    "type": "video",
                    "src": "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4",
                    "poster": "https://picsum.photos/seed/lovelace-talk/600/600",
                },
            ),
            link_tile(
                "Read my latest essay",
                {"type": "image", "url": "https://picsum.photos/seed/lovelace-essay/600/600"},
            ),
            link_tile("Book a call", {"type": "solid", "color": "#4c1d95"}),
            link_tile(
                "Gallery",
                {"type": "image", "url": "https://picsum.photos/seed/lovelace-gallery/600/600"},
            ),
            link_tile("Newsletter", {"type": "solid", "color": "#0f766e"}),
        ],
    }


def sample_layout():
    """Ada Lovelace's page: a hero, four socials and five link tiles."""
    return {"version": 1, "sections": [hero_section(), socials_section(), links_section()]}
