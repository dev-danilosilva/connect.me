import pytest
from django.core.exceptions import ValidationError
from django.db import IntegrityError

from accounts.models import User
from pages.models import LinkPage
from pages.utils import humanize_handle

pytestmark = pytest.mark.django_db


@pytest.fixture
def owner():
    return User.objects.create_user(email="owner@example.com", password="password123")


@pytest.mark.parametrize(
    "handle,expected",
    [
        ("my-cool-page", "My Cool Page"),
        ("portfolio", "Portfolio"),
        ("a-b-c", "A B C"),
        ("--leading", "Leading"),
    ],
)
def test_humanize_handle(handle, expected):
    assert humanize_handle(handle) == expected


def test_title_is_auto_derived_from_handle_on_save(owner):
    page = LinkPage.objects.create(owner=owner, handle="my-cool-page")
    assert page.title == "My Cool Page"


def test_explicit_title_is_not_overwritten(owner):
    page = LinkPage.objects.create(owner=owner, handle="my-cool-page", title="Custom Title")
    assert page.title == "Custom Title"


def test_handle_uniqueness_across_different_owners(owner):
    other = User.objects.create_user(email="other@example.com", password="password123")
    LinkPage.objects.create(owner=owner, handle="taken-handle")
    with pytest.raises(IntegrityError):
        LinkPage.objects.create(owner=other, handle="taken-handle")


@pytest.mark.parametrize(
    "bad_handle",
    ["My-Handle", "my handle", "my_handle", "my.handle", ""],
)
def test_handle_regex_rejects_invalid_formats(owner, bad_handle):
    page = LinkPage(owner=owner, handle=bad_handle)
    with pytest.raises(ValidationError):
        page.full_clean()
