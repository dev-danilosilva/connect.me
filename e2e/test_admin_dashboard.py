from playwright.sync_api import expect


def test_anonymous_visit_redirects_to_reskinned_login(page, live_server):
    page.goto(live_server.url + "/admin/")
    page.wait_for_url("**/admin/login/**")
    expect(page.locator(".admin-login-card")).to_be_visible()


def test_staff_login_shows_dashboard_kpis_and_chart(page, live_server, demo_user, demo_page):
    demo_user.is_staff = True
    demo_user.is_superuser = True
    demo_user.save()

    page.goto(live_server.url + "/admin/login/")
    page.fill("#id_username", demo_user.email)
    page.fill("#id_password", "password123")
    page.click("input[type=submit]")
    page.wait_for_url("**/admin/**")

    expect(page.locator("[data-stat='total_users']")).to_have_text("1", timeout=5000)
    expect(page.locator("[data-stat='total_pages']")).to_have_text("1")
    expect(page.locator("#admin-dashboard-chart")).to_be_visible()
    # Confirms Chart.js actually constructed a chart against the canvas
    # (Chart.getChart returns undefined if none is registered for it).
    page.wait_for_function(
        "!!Chart.getChart(document.getElementById('admin-dashboard-chart'))"
    )

    # The standard app-list navigation is preserved below the dashboard.
    expect(page.locator("a:text-is('Link pages')")).to_be_visible()


def test_changelist_page_still_fully_functional(page, live_server, demo_user, demo_page):
    demo_user.is_staff = True
    demo_user.is_superuser = True
    demo_user.save()

    page.goto(live_server.url + "/admin/login/")
    page.fill("#id_username", demo_user.email)
    page.fill("#id_password", "password123")
    page.click("input[type=submit]")
    page.wait_for_url("**/admin/**")

    page.goto(live_server.url + "/admin/personal_links_manager/linkpage/")
    expect(page.locator("#result_list")).to_be_visible()
    expect(page.locator(f"text={demo_page.handle}")).to_be_visible()
