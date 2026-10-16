import importlib

import pytest
from django.apps import apps as django_apps
from django.core.exceptions import ValidationError
from django.db import IntegrityError

from accounts.models import User
from personal_links_manager import layout
from personal_links_manager.models import LinkPage
from personal_links_manager.utils import humanize_handle

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


def test_new_page_gets_a_valid_default_draft_layout(owner):
    page = LinkPage.objects.create(owner=owner, handle="my-cool-page")

    assert layout.validate(page.draft_layout) == page.draft_layout
    assert page.draft_layout["sections"][0]["displayName"] == "My Cool Page"
    assert page.published_layout is None
    assert page.published_at is None


def test_saving_keeps_an_existing_draft_layout(owner):
    page = LinkPage.objects.create(owner=owner, handle="my-cool-page")
    draft = page.draft_layout

    page.title = "Renamed"
    page.save()

    page.refresh_from_db()
    assert page.draft_layout == draft


def test_migration_backfills_a_draft_layout_for_existing_pages(owner):
    page = LinkPage.objects.create(owner=owner, handle="old-page")
    LinkPage.objects.filter(pk=page.pk).update(draft_layout={})

    migration = importlib.import_module("personal_links_manager.migrations.0004_page_layout")
    migration.backfill_draft_layouts(django_apps, None)

    page.refresh_from_db()
    assert layout.validate(page.draft_layout) == page.draft_layout
    assert page.draft_layout["sections"][0]["displayName"] == "Old Page"
