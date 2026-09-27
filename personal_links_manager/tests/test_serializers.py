import pytest

from accounts.models import User
from personal_links_manager.models import Block, LinkPage
from personal_links_manager.serializers import BlockSerializer

pytestmark = pytest.mark.django_db


@pytest.fixture
def owner():
    return User.objects.create_user(email="owner@example.com", password="password123")


@pytest.fixture
def page(owner):
    return LinkPage.objects.create(owner=owner, handle="serializer-page")


def test_link_block_accepts_valid_data():
    serializer = BlockSerializer(
        data={"block_type": "link", "data": {"label": "My site", "url": "https://example.com"}}
    )
    assert serializer.is_valid(), serializer.errors


def test_link_block_rejects_missing_url():
    serializer = BlockSerializer(data={"block_type": "link", "data": {"label": "My site"}})
    assert not serializer.is_valid()
    assert "data" in serializer.errors


def test_header_block_accepts_valid_data():
    serializer = BlockSerializer(
        data={
            "block_type": "header",
            "data": {"display_name": "Jane", "bio": "Hi", "avatar_url": ""},
        }
    )
    assert serializer.is_valid(), serializer.errors


def test_social_icons_block_accepts_a_list_of_icons():
    serializer = BlockSerializer(
        data={
            "block_type": "social_icons",
            "data": {"icons": [{"platform": "twitter", "url": "https://twitter.com/x"}]},
        }
    )
    assert serializer.is_valid(), serializer.errors


def test_social_icons_block_accepts_an_empty_list():
    serializer = BlockSerializer(data={"block_type": "social_icons", "data": {"icons": []}})
    assert serializer.is_valid(), serializer.errors


def test_block_type_cannot_be_changed_on_update(page):
    block = Block.objects.create(
        page=page,
        block_type="link",
        position=0,
        data={"label": "My site", "url": "https://example.com"},
    )
    serializer = BlockSerializer(
        instance=block, data={"block_type": "header"}, partial=True
    )
    assert not serializer.is_valid()
    assert "block_type" in serializer.errors
