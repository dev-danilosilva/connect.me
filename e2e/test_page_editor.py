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


