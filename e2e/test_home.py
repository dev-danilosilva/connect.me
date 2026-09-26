import re

TILE_TITLES = [
    "Design",
    "Organize",
    "Custom URL",
    "Analytics",
    "Share anywhere",
    "Free forever",
]


def test_home_renders_hero_and_all_tiles(page, live_server):
    page.goto(live_server.url + "/")

    assert page.locator("h1.tile-hero-title").inner_text() == "Every link. One page."
    for title in TILE_TITLES:
        assert page.locator(f"h2.tile-title:text-is('{title}')").count() == 1


def test_get_started_buttons_link_to_register(page, live_server):
    page.goto(live_server.url + "/")

    hrefs = page.eval_on_selector_all(
        "a:text-is('Get started')", "els => els.map(e => e.getAttribute('href'))"
    )
    assert hrefs
    assert all(re.match(r"^/register/?$", href) for href in hrefs)
