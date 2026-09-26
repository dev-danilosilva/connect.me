from playwright.sync_api import expect


def login(page, live_server):
    page.goto(live_server.url + "/login/")
    page.fill("#login-email", "test@example.com")
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")


def test_anonymous_visit_redirects_to_login(page, live_server):
    page.goto(live_server.url + "/dashboard/")
    page.wait_for_url("**/login/**")


def test_create_page_flow_end_to_end(page, live_server, demo_user):
    login(page, live_server)

    page.click("button.dashboard-create-btn")
    page.wait_for_selector("#create-page-modal:not([hidden])")

    # Check-availability button starts disabled until a handle is typed
    # (mirrors Page.Dashboard.elm's `Attr.disabled (String.isEmpty model.handleInput)`).
    assert page.locator("#check-handle-btn").is_disabled()

    # Bad format (uppercase + space)
    page.fill("#create-page-handle", "My Handle")
    page.click("#check-handle-btn")
    expect(page.locator("#handle-status")).to_have_text(
        "Only lowercase letters, numbers, and hyphens are allowed."
    )

    # Reserved word
    page.fill("#create-page-handle", "")
    page.fill("#create-page-handle", "admin")
    page.click("#check-handle-btn")
    expect(page.locator("#handle-status")).to_have_text("This handle is already taken.")

    # Valid + available
    page.fill("#create-page-handle", "")
    page.fill("#create-page-handle", "brand-new-page")
    page.click("#check-handle-btn")
    expect(page.locator("#handle-status")).to_have_text("This handle is available.")
    expect(page.locator("#create-page-submit")).to_be_enabled()

    page.click("#create-page-submit")
    page.wait_for_url("**/dashboard/")

    expect(page.locator("text=mylinks.app/brand-new-page")).to_have_count(1)
    expect(page.locator("h2.page-card-title:text-is('Brand New Page')")).to_have_count(1)

    # Persists across reload
    page.reload()
    expect(page.locator("text=mylinks.app/brand-new-page")).to_have_count(1)


def test_logout_clears_session(page, live_server, demo_user):
    login(page, live_server)

    page.click("button.dashboard-sidebar-avatar")
    page.wait_for_url(live_server.url + "/")

    page.goto(live_server.url + "/dashboard/")
    page.wait_for_url("**/login/**")
