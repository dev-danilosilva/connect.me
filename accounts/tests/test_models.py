import pytest
from django.db import IntegrityError

from accounts.models import User

pytestmark = pytest.mark.django_db


def test_create_user_sets_hashed_password_and_display_name():
    user = User.objects.create_user(
        email="jane@example.com", password="s3cret-pass", display_name="Jane Doe"
    )
    assert user.email == "jane@example.com"
    assert user.display_name == "Jane Doe"
    assert user.password != "s3cret-pass"
    assert user.check_password("s3cret-pass")
    assert user.is_staff is False
    assert user.is_superuser is False


def test_create_user_normalizes_email_domain():
    user = User.objects.create_user(email="jane@EXAMPLE.COM", password="s3cret-pass")
    assert user.email == "jane@example.com"


def test_create_user_without_email_raises():
    with pytest.raises(ValueError):
        User.objects.create_user(email="", password="s3cret-pass")


def test_create_superuser_sets_staff_and_superuser_flags():
    admin = User.objects.create_superuser(email="admin@example.com", password="s3cret-pass")
    assert admin.is_staff is True
    assert admin.is_superuser is True


def test_create_superuser_rejects_is_staff_false():
    with pytest.raises(ValueError):
        User.objects.create_superuser(
            email="admin@example.com", password="s3cret-pass", is_staff=False
        )


def test_email_is_unique():
    User.objects.create_user(email="dup@example.com", password="s3cret-pass")
    with pytest.raises(IntegrityError):
        User.objects.create_user(email="dup@example.com", password="another-pass")


def test_str_returns_email():
    user = User.objects.create_user(email="jane@example.com", password="s3cret-pass")
    assert str(user) == "jane@example.com"
