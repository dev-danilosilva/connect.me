import pytest
from django.test import RequestFactory

from accounts.forms import GENERIC_LOGIN_ERROR, GENERIC_REGISTER_ERROR, LoginForm, RegisterForm
from accounts.models import User

pytestmark = pytest.mark.django_db


@pytest.fixture
def existing_user():
    return User.objects.create_user(
        email="test@example.com", password="password123", display_name="Tes Tuser"
    )


@pytest.fixture
def request_factory():
    return RequestFactory()


def test_valid_credentials_authenticate(existing_user, request_factory):
    request = request_factory.post("/login/")
    form = LoginForm(
        data={"email": "test@example.com", "password": "password123"}, request=request
    )
    assert form.is_valid()
    assert form.user_cache == existing_user


def test_wrong_password_gives_generic_error(existing_user, request_factory):
    request = request_factory.post("/login/")
    form = LoginForm(
        data={"email": "test@example.com", "password": "wrong-password"}, request=request
    )
    assert not form.is_valid()
    assert form.non_field_errors() == [GENERIC_LOGIN_ERROR]
    assert form.user_cache is None


def test_unknown_email_gives_identical_generic_error(existing_user, request_factory):
    request = request_factory.post("/login/")
    form = LoginForm(
        data={"email": "nobody@example.com", "password": "password123"}, request=request
    )
    assert not form.is_valid()
    assert form.non_field_errors() == [GENERIC_LOGIN_ERROR]


def test_wrong_password_and_unknown_email_produce_the_same_message(
    existing_user, request_factory
):
    request = request_factory.post("/login/")
    wrong_password = LoginForm(
        data={"email": "test@example.com", "password": "wrong-password"}, request=request
    )
    unknown_email = LoginForm(
        data={"email": "nobody@example.com", "password": "password123"}, request=request
    )
    wrong_password.is_valid()
    unknown_email.is_valid()
    assert wrong_password.non_field_errors() == unknown_email.non_field_errors()


def test_register_form_valid_creates_no_user_until_saved():
    form = RegisterForm(
        data={
            "display_name": "Jane Doe",
            "email": "jane@example.com",
            "password": "correct-horse-battery",
        }
    )
    assert form.is_valid()
    assert not User.objects.filter(email="jane@example.com").exists()

    user = form.save()
    assert user.email == "jane@example.com"
    assert user.display_name == "Jane Doe"
    assert user.check_password("correct-horse-battery")


def test_register_form_rejects_duplicate_email_case_insensitively(existing_user):
    form = RegisterForm(
        data={
            "display_name": "Someone Else",
            "email": "TEST@example.com",
            "password": "correct-horse-battery",
        }
    )
    assert not form.is_valid()
    assert form.non_field_errors() == [GENERIC_REGISTER_ERROR]


def test_register_form_rejects_weak_password():
    form = RegisterForm(
        data={
            "display_name": "Jane Doe",
            "email": "jane@example.com",
            "password": "password123",  # too common
        }
    )
    assert not form.is_valid()
    assert form.non_field_errors() == [GENERIC_REGISTER_ERROR]


def test_register_form_requires_all_fields():
    form = RegisterForm(data={"display_name": "", "email": "", "password": ""})
    assert not form.is_valid()
    assert "display_name" in form.errors
    assert "email" in form.errors
    assert "password" in form.errors
