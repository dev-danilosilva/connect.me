from django.contrib.auth.decorators import login_required
from django.http import Http404
from django.middleware.csrf import get_token
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.http import require_POST

from .forms import CreatePageForm
from .models import LinkPage
from .stats import mock_daily_visits


def home(request):
    return render(request, "personal_links_manager/home.html")


def visits_chart_flags(pages):
    return {
        "pages": [
            {"handle": page.handle, "title": page.title, "visits": mock_daily_visits(page)}
            for page in pages
        ],
    }


@login_required
def dashboard(request):
    pages = request.user.pages.all()
    context = {
        "pages": pages,
        "create_form": CreatePageForm(),
        "open_create_modal": False,
        "visits_chart_flags": visits_chart_flags(pages),
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

    pages = request.user.pages.all()
    context = {
        "pages": pages,
        "create_form": form,
        "open_create_modal": True,
        "visits_chart_flags": visits_chart_flags(pages),
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
            "draftLayout": page.draft_layout,
        },
    }
    return render(request, "personal_links_manager/page_editor.html", context)
