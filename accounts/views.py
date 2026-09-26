from django.contrib.auth import login as auth_login
from django.shortcuts import redirect, render

from .forms import LoginForm, RegisterForm


def login_view(request):
    if request.user.is_authenticated:
        return redirect("dashboard")

    if request.method == "POST":
        form = LoginForm(request.POST, request=request)
        if form.is_valid():
            auth_login(request, form.user_cache)
            return redirect("dashboard")
    else:
        form = LoginForm(request=request)

    return render(request, "accounts/login.html", {"form": form})


def register_view(request):
    if request.user.is_authenticated:
        return redirect("dashboard")

    if request.method == "POST":
        form = RegisterForm(request.POST)
        if form.is_valid():
            form.save()
            # Matches Main.elm's GotRegisterResult (Ok _) handling: redirect
            # to login rather than auto-authenticating the new account.
            return redirect("login")
    else:
        form = RegisterForm()

    return render(request, "accounts/register.html", {"form": form})
