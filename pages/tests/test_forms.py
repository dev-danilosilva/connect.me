import pytest

from accounts.models import User
from pages.forms import CreatePageForm
from pages.models import LinkPage
from pages.utils import RESERVED_HANDLES

pytestmark = pytest.mark.django_db


def test_empty_handle_gives_specific_message():
    form = CreatePageForm(data={"handle": ""})
    assert not form.is_valid()
    assert form.errors["handle"] == ["Enter a handle first."]


@pytest.mark.parametrize(
    "bad_handle", ["My Handle", "my_handle", "my.handle", "my handle", "MYHANDLE"]
)
def test_invalid_format_gives_specific_message(bad_handle):
    form = CreatePageForm(data={"handle": bad_handle})
    assert not form.is_valid()
    assert form.errors["handle"] == [
        "Only lowercase letters, numbers, and hyphens are allowed."
    ]


@pytest.mark.parametrize("reserved", sorted(RESERVED_HANDLES))
def test_reserved_handles_are_rejected_as_taken(reserved):
    form = CreatePageForm(data={"handle": reserved})
    assert not form.is_valid()
    assert form.errors["handle"] == ["This handle is already taken."]


def test_already_taken_handle_is_rejected():
    owner = User.objects.create_user(email="owner@example.com", password="password123")
    LinkPage.objects.create(owner=owner, handle="my-page")

    form = CreatePageForm(data={"handle": "my-page"})
    assert not form.is_valid()
    assert form.errors["handle"] == ["This handle is already taken."]


def test_available_handle_is_valid():
    form = CreatePageForm(data={"handle": "a-fresh-handle"})
    assert form.is_valid()
    assert form.cleaned_data["handle"] == "a-fresh-handle"
