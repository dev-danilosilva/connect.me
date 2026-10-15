from playwright.sync_api import expect

from personal_links_manager.models import LinkPage


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
    page.wait_for_url("**/dashboard/pages/brand-new-page/edit/")

    # Navigate back to the dashboard to confirm the page was actually persisted
    # and shows up there (not just that we landed on the editor).
    page.goto(live_server.url + "/dashboard/")
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


def test_visits_chart_shows_hover_tooltip_and_toggles(page, live_server, demo_user):
    LinkPage.objects.create(owner=demo_user, handle="portfolio")
    LinkPage.objects.create(owner=demo_user, handle="side-project")
    login(page, live_server)

    panel = page.locator(".visits-panel")
    expect(panel.locator(".visits-title")).to_have_text("Page visits")
    expect(panel.locator(".visits-legend-item")).to_have_count(2)
    expect(panel.locator(".visits-total")).to_contain_text("in the last 30 days")

    box = panel.locator(".visits-chart svg").first.bounding_box()
    page.mouse.move(box["x"] + box["width"] * 0.6, box["y"] + box["height"] / 2)
    tooltip = panel.locator(".visits-tooltip")
    expect(tooltip).to_be_visible()
    expect(tooltip.locator(".visits-tooltip-row")).to_have_count(3)  # 2 pages + total

    panel.locator(".visits-legend-item", has_text="Side Project").click()
    expect(panel.locator(".visits-legend-item", has_text="Side Project")).to_have_attribute(
        "aria-pressed", "false"
    )

    panel.locator(".visits-range-btn", has_text="7d").click()
    expect(panel.locator(".visits-total")).to_contain_text("in the last 7 days")


def test_visits_chart_empty_state_without_pages(page, live_server, demo_user):
    login(page, live_server)
    expect(page.locator(".visits-empty")).to_have_text("Create a page to start tracking its visits.")
