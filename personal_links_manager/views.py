from django.contrib.admin.views.decorators import staff_member_required
from django.contrib.auth.decorators import login_required
from django.http import JsonResponse
from django.shortcuts import redirect, render
from django.views.decorators.http import require_POST

from .forms import CreatePageForm
from .stats import compute_dashboard_stats


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
        return redirect("dashboard")

    context = {
        "pages": request.user.pages.all(),
        "create_form": form,
        "open_create_modal": True,
    }
    return render(request, "personal_links_manager/dashboard.html", context)


@staff_member_required
def admin_dashboard_data(request):
    return JsonResponse(compute_dashboard_stats())
