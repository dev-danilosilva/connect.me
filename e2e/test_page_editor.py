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


def test_deleting_a_block_removes_it_from_the_preview(page, live_server, demo_user, demo_page):
    from personal_links_manager.models import Block

    Block.objects.create(
        page=demo_page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "Delete me", "url": "https://example.com"},
    )

    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")
    page.click(".delete-block-button")

    expect(page.locator(".preview-block-link")).to_have_count(0)


def test_full_editor_flow_edit_switch_device_reorder_and_persist(
    page, live_server, demo_user, demo_page
):
    from personal_links_manager.models import Block

    Block.objects.create(
        page=demo_page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "New link", "url": "https://example.com"},
    )
    Block.objects.create(
        page=demo_page, block_type=Block.BlockType.LINK, position=1,
        data={"label": "New link", "url": "https://example.com"},
    )

    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")
    expect(page.locator(".preview-block-link")).to_have_count(2)

    # Edit the first block's label; preview updates without reload.
    page.fill(".block-editor input >> nth=0", "First link")
    expect(page.locator(".preview-block-link").first).to_contain_text("First link")

    # Switch device size.
    page.click("button:text-is('Phone')")
    expect(page.locator(".preview-frame")).to_have_css("width", "390px")

    # Reorder: move the second block up above the first.
    page.locator(".block-editor").nth(1).locator("[class*='fa-arrow-up']").click()

    # Reload and confirm both the edit and the reorder persisted.
    page.wait_for_timeout(700)
    page.reload()
    expect(page.locator(".preview-block-link").nth(1)).to_contain_text("First link")
