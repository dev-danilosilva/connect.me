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


def test_create_block_appends_at_end_of_page(client, owner, page):
    Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "First", "url": "https://a.example"},
    )
    client.force_login(owner)

    response = client.post(
        reverse("api_block_create", args=[page.handle]),
        {"block_type": "link", "data": {"label": "Second", "url": "https://b.example"}},
        content_type="application/json",
    )

    assert response.status_code == 201
    assert response.json()["position"] == 1


def test_create_block_rejects_a_second_header_block(client, owner, page):
    Block.objects.create(
        page=page, block_type=Block.BlockType.HEADER, position=0,
        data={"display_name": "Jane"},
    )
    client.force_login(owner)

    response = client.post(
        reverse("api_block_create", args=[page.handle]),
        {"block_type": "header", "data": {"display_name": "Jane Again"}},
        content_type="application/json",
    )

    assert response.status_code == 400


def test_create_block_rejects_non_owner(client, page):
    other = User.objects.create_user(email="other2@example.com", password="password123")
    client.force_login(other)

    response = client.post(
        reverse("api_block_create", args=[page.handle]),
        {"block_type": "link", "data": {"label": "Nope", "url": "https://x.example"}},
        content_type="application/json",
    )

    assert response.status_code == 403


def test_patch_block_updates_data(client, owner, page):
    block = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "Old", "url": "https://old.example"},
    )
    client.force_login(owner)

    response = client.patch(
        reverse("api_block_detail", args=[page.handle, block.id]),
        {"data": {"label": "New", "url": "https://new.example"}},
        content_type="application/json",
    )

    assert response.status_code == 200
    block.refresh_from_db()
    assert block.data == {"label": "New", "url": "https://new.example"}


def test_delete_block_removes_it(client, owner, page):
    block = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "Bye", "url": "https://bye.example"},
    )
    client.force_login(owner)

    response = client.delete(reverse("api_block_detail", args=[page.handle, block.id]))

    assert response.status_code == 204
    assert not Block.objects.filter(id=block.id).exists()


def test_patch_block_rejects_non_owner(client, page):
    block = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "X", "url": "https://x.example"},
    )
    other = User.objects.create_user(email="other3@example.com", password="password123")
    client.force_login(other)

    response = client.patch(
        reverse("api_block_detail", args=[page.handle, block.id]),
        {"data": {"label": "Hacked", "url": "https://hacked.example"}},
        content_type="application/json",
    )

    assert response.status_code == 403


def test_reorder_updates_block_positions(client, owner, page):
    first = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "A", "url": "https://a.example"},
    )
    second = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=1,
        data={"label": "B", "url": "https://b.example"},
    )
    client.force_login(owner)

    response = client.post(
        reverse("api_block_reorder", args=[page.handle]),
        {"block_ids": [second.id, first.id]},
        content_type="application/json",
    )

    assert response.status_code == 200
    first.refresh_from_db()
    second.refresh_from_db()
    assert second.position == 0
    assert first.position == 1


def test_reorder_rejects_mismatched_block_ids(client, owner, page):
    Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "A", "url": "https://a.example"},
    )
    client.force_login(owner)

    response = client.post(
        reverse("api_block_reorder", args=[page.handle]),
        {"block_ids": [9999]},
        content_type="application/json",
    )

    assert response.status_code == 400
