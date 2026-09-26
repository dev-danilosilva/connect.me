def test_successful_login_redirects_to_dashboard(page, live_server, demo_user):
    page.goto(live_server.url + "/login/")
    page.fill("#login-email", "test@example.com")
    page.fill("#login-password", "password123")
    page.click("#login-submit")

    page.wait_for_url("**/dashboard/")
    assert "Welcome back, Tes Tuser" in page.content()


def test_wrong_password_shows_generic_error(page, live_server, demo_user):
    page.goto(live_server.url + "/login/")
    page.fill("#login-email", "test@example.com")
    page.fill("#login-password", "wrong-password")
    page.click("#login-submit")

    assert page.locator(".handle-status-taken").inner_text().strip() == "Invalid email or password."


def test_unknown_email_shows_identical_generic_error(page, live_server):
    page.goto(live_server.url + "/login/")
    page.fill("#login-email", "nobody@example.com")
    page.fill("#login-password", "password123")
    page.click("#login-submit")

    assert page.locator(".handle-status-taken").inner_text().strip() == "Invalid email or password."


def test_password_show_hide_toggle(page, live_server):
    page.goto(live_server.url + "/login/")
    password_input = page.locator("#login-password")
    assert password_input.get_attribute("type") == "password"

    page.click("[data-password-toggle='login-password']")
    assert password_input.get_attribute("type") == "text"

    page.click("[data-password-toggle='login-password']")
    assert password_input.get_attribute("type") == "password"
