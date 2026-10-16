from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response
from rest_framework.views import APIView

from . import layout
from .forms import CreatePageForm
from .models import LinkPage
from .stats import compute_dashboard_stats


class HandleAvailabilityAPIView(APIView):
    def get(self, request):
        handle = request.query_params.get("handle", "")
        form = CreatePageForm(data={"handle": handle})

        if form.is_valid():
            return Response({"status": "available", "message": "This handle is available."})

        message = form.errors["handle"][0]
        status = "taken" if message == "This handle is already taken." else "invalid"
        return Response({"status": status, "message": message})


class AdminDashboardDataAPIView(APIView):
    permission_classes = [IsAdminUser]

    def get(self, request):
        return Response(compute_dashboard_stats())


def get_owned_page(request, handle):
    # 404, not 403, for someone else's page, like the page_editor view.
    return get_object_or_404(LinkPage, handle=handle, owner=request.user)


class DraftLayoutAPIView(APIView):
    """The page's draft layout, the document the editor works on."""

    def get(self, request, handle):
        return Response(get_owned_page(request, handle).draft_layout)

    def put(self, request, handle):
        page = get_owned_page(request, handle)
        page.draft_layout = layout.validate(request.data)
        page.save(update_fields=["draft_layout"])
        return Response(page.draft_layout)


class PublishLayoutAPIView(APIView):
    """Makes the current draft what visitors see."""

    def post(self, request, handle):
        page = get_owned_page(request, handle)
        page.published_layout = page.draft_layout
        page.published_at = timezone.now()
        page.save(update_fields=["published_layout", "published_at"])
        return Response({"publishedAt": page.published_at})
