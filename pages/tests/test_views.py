import json

import pytest
from django.urls import reverse

from accounts.models import User
from pages.models import LinkPage

pytestmark = pytest.mark.django_db


@pytest.fixture
def user():
    return User.objects.create_user(
        email="test@example.com", password="password123", display_name="Tes Tuser"
    )


def test_home_page_is_public(client):
    response = client.get(reverse("home"))
    assert response.status_code == 200
    assert "Every link. One page." in response.content.decode()


def test_dashboard_redirects_anonymous_to_login(client):
    response = client.get(reverse("dashboard"))
    assert response.status_code == 302
    assert response.url.startswith(reverse("login"))


def test_dashboard_shows_display_name_and_only_owned_pages(client, user):
    other = User.objects.create_user(email="other@example.com", password="password123")
    LinkPage.objects.create(owner=user, handle="mine")
    LinkPage.objects.create(owner=other, handle="not-mine")

    client.force_login(user)
    response = client.get(reverse("dashboard"))

    content = response.content.decode()
    assert "Welcome back, Tes Tuser" in content
    assert "mylinks.app/mine" in content
    assert "mylinks.app/not-mine" not in content


def test_create_page_persists_scoped_to_owner(client, user):
    client.force_login(user)
    response = client.post(reverse("create_page"), {"handle": "my-new-page"})

    assert response.status_code == 302
    page = LinkPage.objects.get(handle="my-new-page")
    assert page.owner == user
    assert page.title == "My New Page"


def test_create_page_rejects_duplicate_handle(client, user):
    LinkPage.objects.create(owner=user, handle="taken")
    client.force_login(user)

    response = client.post(reverse("create_page"), {"handle": "taken"})

    assert response.status_code == 200
    assert LinkPage.objects.filter(handle="taken").count() == 1


def test_create_page_rejects_reserved_handle(client, user):
    client.force_login(user)
    response = client.post(reverse("create_page"), {"handle": "admin"})

    assert response.status_code == 200
    assert not LinkPage.objects.filter(handle="admin").exists()


def test_create_page_requires_login(client):
    response = client.post(reverse("create_page"), {"handle": "some-page"})
    assert response.status_code == 302
    assert response.url.startswith(reverse("login"))


def test_check_handle_availability_available(client, user):
    client.force_login(user)
    response = client.get(reverse("check_handle_availability"), {"handle": "fresh-handle"})
    data = json.loads(response.content)
    assert data == {"status": "available", "message": "This handle is available."}


def test_check_handle_availability_taken(client, user):
    LinkPage.objects.create(owner=user, handle="taken")
    client.force_login(user)
    response = client.get(reverse("check_handle_availability"), {"handle": "taken"})
    data = json.loads(response.content)
    assert data == {"status": "taken", "message": "This handle is already taken."}


def test_check_handle_availability_invalid_format(client, user):
    client.force_login(user)
    response = client.get(reverse("check_handle_availability"), {"handle": "Bad Handle"})
    data = json.loads(response.content)
    assert data["status"] == "invalid"


def test_check_handle_availability_requires_login(client):
    response = client.get(reverse("check_handle_availability"), {"handle": "anything"})
    assert response.status_code == 302


def test_admin_dashboard_data_redirects_anonymous_to_admin_login(client):
    response = client.get(reverse("admin_dashboard_data"))
    assert response.status_code == 302
    assert response.url.startswith("/admin/login/")


def test_admin_dashboard_data_redirects_non_staff_user_to_admin_login(client, user):
    client.force_login(user)
    response = client.get(reverse("admin_dashboard_data"))
    assert response.status_code == 302
    assert response.url.startswith("/admin/login/")


def test_admin_dashboard_data_returns_stats_for_staff_user(client, user):
    other = User.objects.create_user(email="other@example.com", password="password123")
    LinkPage.objects.create(owner=user, handle="mine")
    LinkPage.objects.create(owner=other, handle="also-mine")

    staff = User.objects.create_user(
        email="staff@example.com", password="password123", is_staff=True
    )
    client.force_login(staff)

    response = client.get(reverse("admin_dashboard_data"))

    assert response.status_code == 200
    data = response.json()
    # user, other, staff -> 3 users; 2 link pages created above.
    assert data["total_users"] == 3
    assert data["total_pages"] == 2
