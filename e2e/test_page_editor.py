import re

from playwright.sync_api import expect

from personal_links_manager.models import LinkPage
from personal_links_manager.tests import media_samples
from personal_links_manager.tests.layouts import sample_layout


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


def test_page_editor_preview_shows_the_draft_layout(
    page, live_server, demo_user, demo_page_with_layout
):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page_with_layout.handle}/edit/")

    link_page = page.locator(".preview-frame .lp-page")
    expect(link_page.locator(".lp-hero .lp-name")).to_have_text("Ada Lovelace")
    expect(link_page.locator(".lp-hero .lp-bio")).to_be_visible()
    expect(link_page.locator(".lp-hero .lp-hero-image")).to_have_attribute("src", re.compile("^https://"))
    expect(link_page.locator(".lp-social")).to_have_count(4)


def test_link_page_links_are_tiles_with_every_background_kind(
    page, live_server, demo_user, demo_page_with_layout
):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page_with_layout.handle}/edit/")

    tiles = page.locator(".preview-frame .lp-page .lp-links .lp-tile")
    expect(tiles).to_have_count(5)
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

    # Solid tiles paint the tile itself with their color.
    expect(page.locator(".lp-tile--solid").first).to_have_css(
        "background-color", "rgb(76, 29, 149)"
    )


def test_link_page_styles_come_only_from_its_theme_tokens(
    page, live_server, demo_user, demo_page_with_layout
):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page_with_layout.handle}/edit/")

    # Setting a --lp-* token on the root restyles the page, which is how a
    # page style model will be applied.
    link_page = page.locator(".lp-page")
    link_page.evaluate("el => el.style.setProperty('--lp-tile-text-color', 'rgb(255, 0, 0)')")
    expect(link_page.locator(".lp-tile-label").first).to_have_css("color", "rgb(255, 0, 0)")

    # Text color comes from the token, not from the editor's inherited color.
    link_page.evaluate("el => el.style.setProperty('--lp-text-color', 'rgb(0, 128, 0)')")
    expect(link_page).to_have_css("color", "rgb(0, 128, 0)")


def test_page_editor_fits_the_viewport(page, live_server, demo_user, demo_page_with_layout):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    for width, height in [(1280, 720), (390, 844)]:
        page.set_viewport_size({"width": width, "height": height})
        page.goto(f"{live_server.url}/dashboard/pages/{demo_page_with_layout.handle}/edit/")
        expect(page.locator(".preview-frame .lp-page")).to_be_visible()

        # The document never scrolls; the panes scroll on their own instead.
        scroll_size = page.evaluate(
            "[document.documentElement.scrollWidth, document.documentElement.scrollHeight]"
        )
        assert scroll_size == [width, height]

        # The link page, and so its background, spans the frame's whole
        # scrollable content, not just the first screenful.
        page_height, content_height = page.evaluate(
            "[document.querySelector('.preview-frame .lp-page').offsetHeight,"
            " document.querySelector('.preview-frame').scrollHeight]"
        )
        assert page_height == content_height



def login(page, live_server, user):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")


def test_a_new_pages_preview_shows_its_title_as_the_name(page, live_server, demo_user, demo_page):
    login(page, live_server, demo_user)
    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")

    link_page = page.locator(".preview-frame .lp-page")
    expect(link_page.locator(".lp-hero .lp-name")).to_have_text(demo_page.title)
    # No hero image yet, so the hero shows its fallback background.
    expect(link_page.locator(".lp-hero-image")).to_have_count(0)
    expect(link_page.locator(".lp-tile")).to_have_count(0)


def test_preview_renders_sections_in_the_layouts_order(page, live_server, demo_user):
    document = sample_layout()
    hero, socials, links = document["sections"]
    document["sections"] = [hero, links, socials]
    ordered = LinkPage.objects.create(owner=demo_user, handle="ordered", draft_layout=document)

    login(page, live_server, demo_user)
    page.goto(f"{live_server.url}/dashboard/pages/{ordered.handle}/edit/")

    sections = page.locator(".preview-frame .lp-page > .lp-section")
    expect(sections).to_have_count(2)
    expect(sections.nth(0)).to_have_class(re.compile("lp-section--links"))
    expect(sections.nth(1)).to_have_class(re.compile("lp-section--socials"))


def open_editor(page, live_server, user, link_page):
    login(page, live_server, user)
    page.goto(f"{live_server.url}/dashboard/pages/{link_page.handle}/edit/")
    expect(page.locator(".editor-sections")).to_be_visible()


def test_editing_the_name_updates_the_preview_and_saves_the_draft(
    page, live_server, demo_user, demo_page
):
    open_editor(page, live_server, demo_user, demo_page)
    status = page.locator(".editor-status")
    save = page.locator("button.editor-action", has_text="Save")
    expect(status).to_have_text("Saved · not published yet")
    expect(save).to_be_disabled()

    page.get_by_label("Name").fill("Grace Hopper")

    expect(page.locator(".preview-frame .lp-name")).to_have_text("Grace Hopper")
    expect(status).to_have_text("Unsaved changes")
    save.click()
    expect(status).to_have_text("Saved · not published yet")
    expect(save).to_be_disabled()

    demo_page.refresh_from_db()
    assert demo_page.draft_layout["sections"][0]["displayName"] == "Grace Hopper"
    page.reload()
    expect(page.locator(".preview-frame .lp-name")).to_have_text("Grace Hopper")


def test_adding_a_link_needs_a_label_and_a_full_url(page, live_server, demo_user, demo_page):
    open_editor(page, live_server, demo_user, demo_page)
    save = page.locator("button.editor-action", has_text="Save")

    page.get_by_role("button", name="Add link").click()
    expect(page.locator(".preview-frame .lp-tile")).to_have_count(1)
    expect(save).to_be_disabled()

    item = page.locator(".editor-item-open")
    item.get_by_label("Label").fill("My blog")
    item.get_by_label("URL").fill("blog.example.com")
    expect(item.locator(".editor-field-problem")).to_have_text("Start the URL with https://")
    expect(save).to_be_disabled()

    item.get_by_label("URL").fill("https://blog.example.com")
    expect(item.locator(".editor-field-problem")).to_have_count(0)
    expect(page.locator(".preview-frame .lp-tile-label")).to_have_text("My blog")
    save.click()
    expect(page.locator(".editor-status")).to_have_text("Saved · not published yet")

    demo_page.refresh_from_db()
    links = demo_page.draft_layout["sections"][2]["items"]
    assert [(tile["label"], tile["url"]) for tile in links] == [("My blog", "https://blog.example.com")]


def test_publish_saves_unsaved_changes_first(page, live_server, demo_user, demo_page_with_layout):
    open_editor(page, live_server, demo_user, demo_page_with_layout)

    page.get_by_label("Bio").fill("Countess of Lovelace.")
    page.locator("button.editor-action", has_text="Publish").click()

    expect(page.locator(".editor-status")).to_have_text("Published")
    expect(page.locator("button.editor-action", has_text="Publish")).to_be_disabled()
    demo_page_with_layout.refresh_from_db()
    assert demo_page_with_layout.published_layout == demo_page_with_layout.draft_layout
    assert demo_page_with_layout.published_layout["sections"][0]["bio"] == "Countess of Lovelace."


def test_sections_and_links_reorder_and_remove(page, live_server, demo_user, demo_page_with_layout):
    open_editor(page, live_server, demo_user, demo_page_with_layout)
    preview = page.locator(".preview-frame .lp-page")

    page.get_by_role("button", name="Move Links up").click()
    sections = preview.locator("> .lp-section")
    expect(sections.nth(0)).to_have_class(re.compile("lp-section--links"))

    page.get_by_role("button", name="Move Read my latest essay up").click()
    expect(preview.locator(".lp-tile-label").first).to_have_text("Read my latest essay")

    page.get_by_role("button", name="Remove Newsletter").click()
    expect(preview.locator(".lp-tile")).to_have_count(4)

    page.locator("button.editor-action", has_text="Save").click()
    expect(page.locator(".editor-status")).to_have_text("Saved · not published yet")
    demo_page_with_layout.refresh_from_db()
    sections = demo_page_with_layout.draft_layout["sections"]
    assert [s["type"] for s in sections] == ["hero", "links", "socials"]
    assert [t["label"] for t in sections[1]["items"]] == [
        "Read my latest essay",
        "Watch my talk",
        "Book a call",
        "Gallery",
    ]


def test_changing_a_tile_background(page, live_server, demo_user, demo_page_with_layout):
    open_editor(page, live_server, demo_user, demo_page_with_layout)

    page.locator(".editor-item-toggle", has_text="Book a call").click()
    item = page.locator(".editor-item-open")
    item.get_by_role("button", name="Image").click()
    expect(item.get_by_label("Image URL")).to_be_visible()
    item.get_by_label("Image URL").fill("https://picsum.photos/seed/call/600/600")

    tile = page.locator(".preview-frame .lp-tile", has_text="Book a call")
    expect(tile).to_have_class(re.compile("lp-tile--image"))
    expect(tile.locator("img")).to_have_attribute("src", "https://picsum.photos/seed/call/600/600")


def choose_file(page, button, name, mime_type, data):
    with page.expect_file_chooser() as chooser:
        button.click()
    chooser.value.set_files(files=[{"name": name, "mimeType": mime_type, "buffer": data}])


def test_uploading_a_video_and_poster_sets_the_tile_background(
    page, live_server, demo_user, demo_page_with_layout, settings, tmp_path
):
    settings.MEDIA_ROOT = tmp_path
    open_editor(page, live_server, demo_user, demo_page_with_layout)
    page.locator(".editor-item-toggle", has_text="Watch my talk").click()
    item = page.locator(".editor-item-open")

    choose_file(page, item.get_by_role("button", name="Upload a video file"), "talk.mp4", "video/mp4", media_samples.MP4)
    expect(item.get_by_label("Video URL")).to_have_value(re.compile(r"/media/[0-9a-f-]{36}\.mp4$"))
    choose_file(page, item.get_by_role("button", name="Upload a poster image"), "poster.png", "image/png", media_samples.PNG)
    expect(item.get_by_label("Poster image URL")).to_have_value(re.compile(r"/media/[0-9a-f-]{36}\.png$"))

    # The bytes are only a signature, so check the attributes, not playback.
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

    choose_file(page, item.get_by_role("button", name="Upload a video file"), "photo.mp4", "video/mp4", media_samples.HEIC)

    expect(item.locator(".editor-field-problem")).to_have_text("Upload an MP4 or WebM video.")
