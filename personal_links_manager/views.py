from django.contrib.auth.decorators import login_required
from django.http import Http404
from django.middleware.csrf import get_token
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.http import require_POST

from .forms import CreatePageForm
from .models import LinkPage


def home(request):
    return render(request, "personal_links_manager/home.html")


@login_required
def dashboard(request):
    context = {
        "pages": request.user.pages.all(),
        "create_form": CreatePageForm(),
        "open_create_modal": False,
    }
    return render(request, "personal_links_manager/dashboard.html", context)


@login_required
@require_POST
def create_page(request):
    form = CreatePageForm(request.POST)
    if form.is_valid():
        page = form.save(commit=False)
        page.owner = request.user
        page.save()
        return redirect("page_editor", handle=page.handle)

    context = {
        "pages": request.user.pages.all(),
        "create_form": form,
        "open_create_modal": True,
    }
    return render(request, "personal_links_manager/dashboard.html", context)


@login_required
def page_editor(request, handle):
    page = get_object_or_404(LinkPage, handle=handle)
    if page.owner != request.user:
        raise Http404
    context = {
        "elm_flags": {
            "pageId": page.id,
            "handle": page.handle,
            "title": page.title,
            "username": request.user.display_name or request.user.email,
            "csrfToken": get_token(request),
            "apiBase": "/api/",
        },
    }
    return render(request, "personal_links_manager/page_editor.html", context)
