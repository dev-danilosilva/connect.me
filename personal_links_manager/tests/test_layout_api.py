import pytest
from django.urls import reverse

from accounts.models import User
from personal_links_manager.models import LinkPage

from .layouts import sample_layout

pytestmark = pytest.mark.django_db


@pytest.fixture
def user():
    return User.objects.create_user(email="owner@example.com", password="password123")


@pytest.fixture
def page(user):
    return LinkPage.objects.create(owner=user, handle="my-page")


def draft_url(page):
    return reverse("api_page_draft", args=[page.handle])


def publish_url(page):
    return reverse("api_page_publish", args=[page.handle])


def test_get_returns_the_draft(client, user, page):
    client.force_login(user)

    response = client.get(draft_url(page))

    assert response.status_code == 200
    assert response.json() == page.draft_layout


def test_put_validates_and_saves_the_draft(client, user, page):
    client.force_login(user)
    document = sample_layout()

    response = client.put(draft_url(page), document, content_type="application/json")

    assert response.status_code == 200
    assert response.json() == document
    page.refresh_from_db()
    assert page.draft_layout == document


def test_put_rejects_an_invalid_draft_and_keeps_the_old_one(client, user, page):
    client.force_login(user)
    old_draft = page.draft_layout
    document = sample_layout()
    document["sections"][2]["items"][0]["url"] = "javascript:alert(1)"

    response = client.put(draft_url(page), document, content_type="application/json")

    assert response.status_code == 400
    assert "sections" in response.json()
    page.refresh_from_db()
    assert page.draft_layout == old_draft


def test_put_rejects_an_unsupported_version(client, user, page):
    client.force_login(user)
    document = sample_layout()
    document["version"] = 2

    response = client.put(draft_url(page), document, content_type="application/json")

    assert response.status_code == 400
    assert "version" in response.json()


def test_publish_copies_the_draft(client, user, page):
    client.force_login(user)
    client.put(draft_url(page), sample_layout(), content_type="application/json")

    response = client.post(publish_url(page))

    assert response.status_code == 200
    page.refresh_from_db()
    assert page.published_layout == page.draft_layout
    assert page.published_at is not None
    assert response.json()["publishedAt"]


def test_editing_the_draft_after_publishing_leaves_the_published_layout(client, user, page):
    client.force_login(user)
    client.post(publish_url(page))
    page.refresh_from_db()
    published = page.published_layout

    client.put(draft_url(page), sample_layout(), content_type="application/json")

    page.refresh_from_db()
    assert page.published_layout == published
    assert page.draft_layout != published


def test_another_users_page_is_not_found(client, page):
    other = User.objects.create_user(email="other@example.com", password="password123")
    client.force_login(other)

    assert client.get(draft_url(page)).status_code == 404
    assert (
        client.put(draft_url(page), sample_layout(), content_type="application/json").status_code
        == 404
    )
    assert client.post(publish_url(page)).status_code == 404


def test_anonymous_requests_are_forbidden(client, page):
    assert client.get(draft_url(page)).status_code == 403
    assert client.post(publish_url(page)).status_code == 403
