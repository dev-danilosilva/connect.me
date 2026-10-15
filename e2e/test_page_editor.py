import re

from playwright.sync_api import expect


def test_page_editor_loads_and_shows_the_page_title(page, live_server, demo_user, demo_page):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")

    # The title flows through the Django template into <title>; the Elm
    # app itself no longer fetches or renders any page content.
    expect(page).to_have_title(f"Edit {demo_page.title} · SharedLink")


def test_page_editor_device_switcher_resizes_the_preview_frame(
    page, live_server, demo_user, demo_page
):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")

    page.click("button:text-is('Tablet')")
    expect(page.locator(".preview-frame")).to_have_css("width", "768px")

    page.click("button:text-is('Phone')")
    expect(page.locator(".preview-frame")).to_have_css("width", "390px")


def test_page_editor_preview_shows_the_dummy_link_page(page, live_server, demo_user, demo_page):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")

    link_page = page.locator(".preview-frame .lp-page")
    expect(link_page.locator(".lp-hero .lp-name")).to_have_text("Ada Lovelace")
    expect(link_page.locator(".lp-hero .lp-bio")).to_be_visible()
    expect(link_page.locator(".lp-hero .lp-hero-image")).to_have_attribute("src", re.compile("^https://"))
    expect(link_page.locator(".lp-social")).to_have_count(4)


def test_link_page_links_are_tiles_with_every_background_kind(page, live_server, demo_user, demo_page):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")

    tiles = page.locator(".preview-frame .lp-page .lp-links .lp-tile")
    expect(tiles).to_have_count(6)
    for tile in tiles.all():
        expect(tile.locator(".lp-tile-label")).not_to_be_empty()

    # Two columns of square tiles.
    first, second = tiles.nth(0).bounding_box(), tiles.nth(1).bounding_box()
    assert first["y"] == second["y"] and second["x"] > first["x"]
    assert abs(first["width"] - first["height"]) < 1

    # Image tiles: a decorative cover image behind the label.
    image = page.locator(".lp-tile--image .lp-tile-media").first
    expect(image).to_have_attribute("src", re.compile("^https://"))
    expect(image).to_have_attribute("alt", "")

    # Video tiles autoplay, which phones only allow when muted.
    video = page.locator(".lp-tile--video video.lp-tile-media")
    expect(video).to_have_count(1)
    expect(video).to_have_attribute("autoplay", "")
    expect(video).to_have_attribute("playsinline", "")
    expect(video).to_have_attribute("loop", "")
    assert video.evaluate("el => el.muted") is True

    # Solid and gradient tiles paint the tile itself.
    expect(page.locator(".lp-tile--solid").first).to_have_css(
        "background-color", re.compile(r"^rgb\(")
    )
    expect(page.locator(".lp-tile--gradient").first).to_have_css(
        "background-image", re.compile("^linear-gradient")
    )


def test_link_page_styles_come_only_from_its_theme_tokens(page, live_server, demo_user, demo_page):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")

    # Setting a --lp-* token on the root restyles the page, which is how a
    # page style model will be applied.
    link_page = page.locator(".lp-page")
    link_page.evaluate("el => el.style.setProperty('--lp-tile-text-color', 'rgb(255, 0, 0)')")
    expect(link_page.locator(".lp-tile-label").first).to_have_css("color", "rgb(255, 0, 0)")

    # Text color comes from the token, not from the editor's inherited color.
    link_page.evaluate("el => el.style.setProperty('--lp-text-color', 'rgb(0, 128, 0)')")
    expect(link_page).to_have_css("color", "rgb(0, 128, 0)")
