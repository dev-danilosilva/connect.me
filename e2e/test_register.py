from playwright.sync_api import expect


def test_successful_registration_redirects_to_login(page, live_server):
    page.goto(live_server.url + "/register/")
    page.fill("#register-name", "Jane Doe")
    page.fill("#register-email", "jane@example.com")
    page.fill("#register-password", "correct-horse-battery")
    page.click("button:text-is('Register')")

    page.wait_for_url("**/login/**")

    # Does not auto-login: the new account can log in explicitly.
    page.fill("#login-email", "jane@example.com")
    page.fill("#login-password", "correct-horse-battery")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")
    expect(page.locator("h1.dashboard-title")).to_contain_text("Welcome back, Jane Doe")


def test_registration_with_taken_email_shows_generic_error(page, live_server, demo_user):
    page.goto(live_server.url + "/register/")
    page.fill("#register-name", "Someone Else")
    page.fill("#register-email", "test@example.com")
    page.fill("#register-password", "correct-horse-battery")
    page.click("button:text-is('Register')")

    expect(page.locator(".handle-status-taken")).to_contain_text(
        "Something went wrong creating your account."
    )


def test_registration_with_weak_password_shows_specific_error(page, live_server):
    page.goto(live_server.url + "/register/")
    page.fill("#register-name", "Jane Doe")
    page.fill("#register-email", "jane@example.com")
    page.fill("#register-password", "password123")
    page.click("button:text-is('Register')")

    expect(page.locator(".handle-status-taken")).to_contain_text(
        "This password is too common."
    )


def test_login_page_links_to_register_and_back(page, live_server):
    page.goto(live_server.url + "/login/")
    page.click("a:text-is('Register')")
    page.wait_for_url("**/register/**")

    page.click("a:text-is('Login')")
    page.wait_for_url("**/login/**")
