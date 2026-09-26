import pytest
from django.urls import reverse

from accounts.forms import GENERIC_LOGIN_ERROR, GENERIC_REGISTER_ERROR
from accounts.models import User

pytestmark = pytest.mark.django_db


@pytest.fixture
def existing_user():
    return User.objects.create_user(
        email="test@example.com", password="password123", display_name="Tes Tuser"
    )


def test_get_login_page_renders_form(client):
    response = client.get(reverse("login"))
    assert response.status_code == 200
    assert "form" in response.context


def test_successful_login_creates_session_and_redirects_to_dashboard(client, existing_user):
    response = client.post(
        reverse("login"), {"email": "test@example.com", "password": "password123"}
    )
    assert response.status_code == 302
    assert response.url == reverse("dashboard")
    assert "_auth_user_id" in client.session


def test_wrong_password_returns_200_with_generic_error(client, existing_user):
    response = client.post(
        reverse("login"), {"email": "test@example.com", "password": "wrong-password"}
    )
    assert response.status_code == 200
    assert GENERIC_LOGIN_ERROR in response.content.decode()
    assert "_auth_user_id" not in client.session


def test_unknown_email_returns_200_with_same_generic_error(client, existing_user):
    response = client.post(
        reverse("login"), {"email": "nobody@example.com", "password": "password123"}
    )
    assert response.status_code == 200
    assert GENERIC_LOGIN_ERROR in response.content.decode()
    assert "_auth_user_id" not in client.session


def test_already_authenticated_user_visiting_login_redirects_to_dashboard(client, existing_user):
    client.force_login(existing_user)
    response = client.get(reverse("login"))
    assert response.status_code == 302
    assert response.url == reverse("dashboard")


def test_logout_requires_post(client, existing_user):
    client.force_login(existing_user)
    response = client.get(reverse("logout"))
    assert response.status_code == 405


def test_logout_clears_session_and_redirects_home(client, existing_user):
    client.force_login(existing_user)
    response = client.post(reverse("logout"))
    assert response.status_code == 302
    assert response.url == "/"
    assert "_auth_user_id" not in client.session


def test_get_register_page_renders_form(client):
    response = client.get(reverse("register"))
    assert response.status_code == 200
    assert "form" in response.context


def test_successful_registration_creates_user_and_redirects_to_login_without_auto_login(client):
    response = client.post(
        reverse("register"),
        {
            "display_name": "Jane Doe",
            "email": "jane@example.com",
            "password": "correct-horse-battery",
        },
    )
    assert response.status_code == 302
    assert response.url == reverse("login")
    assert User.objects.filter(email="jane@example.com").exists()
    assert "_auth_user_id" not in client.session


def test_registration_with_taken_email_returns_200_with_generic_error(client, existing_user):
    response = client.post(
        reverse("register"),
        {
            "display_name": "Someone Else",
            "email": "test@example.com",
            "password": "correct-horse-battery",
        },
    )
    assert response.status_code == 200
    assert GENERIC_REGISTER_ERROR in response.content.decode()
    assert User.objects.filter(email="test@example.com").count() == 1


def test_registration_with_weak_password_returns_200_with_generic_error(client):
    response = client.post(
        reverse("register"),
        {"display_name": "Jane Doe", "email": "jane@example.com", "password": "password123"},
    )
    assert response.status_code == 200
    assert GENERIC_REGISTER_ERROR in response.content.decode()
    assert not User.objects.filter(email="jane@example.com").exists()


def test_already_authenticated_user_visiting_register_redirects_to_dashboard(
    client, existing_user
):
    client.force_login(existing_user)
    response = client.get(reverse("register"))
    assert response.status_code == 302
    assert response.url == reverse("dashboard")
