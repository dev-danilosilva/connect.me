from django.contrib.auth import authenticate
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django import forms

from .models import User

GENERIC_LOGIN_ERROR = "Invalid email or password."
GENERIC_REGISTER_ERROR = "Something went wrong creating your account. Please try again."


class LoginForm(forms.Form):
    email = forms.EmailField()
    password = forms.CharField(widget=forms.PasswordInput)

    def __init__(self, *args, request=None, **kwargs):
        self.request = request
        self.user_cache = None
        super().__init__(*args, **kwargs)

    def clean(self):
        cleaned_data = super().clean()
        email = cleaned_data.get("email")
        password = cleaned_data.get("password")

        if email and password:
            # Wrong email and wrong password both fail through this single
            # call/branch, so the error message never reveals which one it was.
            user = authenticate(self.request, username=email, password=password)
            if user is None:
                raise forms.ValidationError(GENERIC_LOGIN_ERROR, code="invalid_login")
            self.user_cache = user

        return cleaned_data


class RegisterForm(forms.Form):
    display_name = forms.CharField(max_length=150, label="Name")
    email = forms.EmailField()
    password = forms.CharField(widget=forms.PasswordInput)

    def clean(self):
        cleaned_data = super().clean()
        email = cleaned_data.get("email")
        password = cleaned_data.get("password")

        # Kept generic (non-field) so a failed attempt never confirms
        # whether an email is already registered.
        if email and User.objects.filter(email__iexact=email).exists():
            raise forms.ValidationError(GENERIC_REGISTER_ERROR, code="registration_failed")

        # Password strength failures don't leak account-existence info,
        # so these can safely be specific about which rule failed.
        if password:
            try:
                validate_password(password)
            except DjangoValidationError as exc:
                self.add_error("password", exc)

        return cleaned_data

    def save(self):
        return User.objects.create_user(
            email=self.cleaned_data["email"],
            password=self.cleaned_data["password"],
            display_name=self.cleaned_data["display_name"],
        )
