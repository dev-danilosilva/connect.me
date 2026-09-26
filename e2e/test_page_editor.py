from playwright.sync_api import expect


def test_page_editor_loads_and_shows_the_page_title(page, live_server, demo_user, demo_page):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")

    # Task 11 replaced the placeholder "Loading {title}..." view with the real
    # preview/controls shell, which doesn't render the page title in the body.
    # The title still flows through the Django template into <title>.
    expect(page).to_have_title(f"Edit {demo_page.title} · SharedLink")


def test_page_editor_shows_existing_blocks_and_switches_device_width(
    page, live_server, demo_user, demo_page
):
    from personal_links_manager.models import Block

    Block.objects.create(
        page=demo_page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "My cool link", "url": "https://example.com"},
    )

    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")

    expect(page.locator(".preview-block-link")).to_contain_text("My cool link")

    page.click("button:text-is('Tablet')")
    expect(page.locator(".preview-frame")).to_have_css("width", "768px")


def test_adding_a_link_block_shows_up_in_the_preview(page, live_server, demo_user, demo_page):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")
    page.click("button:text-is('Add Link')")

    expect(page.locator(".preview-block-link")).to_contain_text("New link")


def test_add_header_button_disables_once_a_header_exists(
    page, live_server, demo_user, demo_page
):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")
    page.click("button:text-is('Add Header')")

    expect(page.locator("button:text-is('Add Header')")).to_be_disabled()


def test_editing_a_link_label_updates_the_preview_without_reload(
    page, live_server, demo_user, demo_page
):
    from personal_links_manager.models import Block

    Block.objects.create(
        page=demo_page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "Original", "url": "https://example.com"},
    )

    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")
    page.fill(".block-editor input >> nth=0", "Updated label")

    expect(page.locator(".preview-block-link")).to_contain_text("Updated label")

    # Give the 500ms debounce time to fire, then reload and confirm it persisted.
    page.wait_for_timeout(700)
    page.reload()
    expect(page.locator(".preview-block-link")).to_contain_text("Updated label")
