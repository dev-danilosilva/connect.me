import pytest
from django.urls import reverse

from accounts.models import User
from personal_links_manager.models import Block, LinkPage

pytestmark = pytest.mark.django_db


@pytest.fixture
def owner():
    return User.objects.create_user(email="owner@example.com", password="password123")


@pytest.fixture
def page(owner):
    return LinkPage.objects.create(owner=owner, handle="api-page")


def test_page_detail_returns_page_and_blocks(client, owner, page):
    Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "Site", "url": "https://example.com"},
    )
    client.force_login(owner)

    response = client.get(reverse("api_page_detail", args=[page.handle]))

    assert response.status_code == 200
    data = response.json()
    assert data["handle"] == "api-page"
    assert len(data["blocks"]) == 1
    assert data["blocks"][0]["data"] == {"label": "Site", "url": "https://example.com"}


def test_page_detail_rejects_non_owner(client, page):
    other = User.objects.create_user(email="other@example.com", password="password123")
    client.force_login(other)

    response = client.get(reverse("api_page_detail", args=[page.handle]))

    assert response.status_code == 403


def test_page_detail_rejects_anonymous(client, page):
    response = client.get(reverse("api_page_detail", args=[page.handle]))
    assert response.status_code == 403
