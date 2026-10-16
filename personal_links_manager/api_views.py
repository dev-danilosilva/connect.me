from django.db.models import Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import serializers, status
from rest_framework.parsers import MultiPartParser
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response
from rest_framework.views import APIView

from . import layout, media
from .forms import CreatePageForm
from .models import LinkPage, MediaAsset
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


class MediaUploadSerializer(serializers.Serializer):
    kind = serializers.ChoiceField(choices=media.KINDS)
    file = serializers.FileField(allow_empty_file=True)


class MediaUploadAPIView(APIView):
    """Stores an uploaded video or image and returns its URL, which the
    editor uses in a layout like any pasted link."""

    parser_classes = [MultiPartParser]

    def post(self, request):
        serializer = MediaUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        kind = serializer.validated_data["kind"]
        upload = serializer.validated_data["file"]

        def reject(message):
            return Response({"file": [message]}, status=status.HTTP_400_BAD_REQUEST)

        detected = media.detect(upload.read(media.HEAD_BYTES))
        upload.seek(0)
        if detected is None or detected.kind != kind:
            return reject(media.TYPE_MESSAGES[kind])
        if upload.size > media.MAX_BYTES[kind]:
            return reject(media.SIZE_MESSAGES[kind])
        used = request.user.media_assets.aggregate(total=Sum("size_bytes"))["total"] or 0
        if used + upload.size > media.QUOTA_BYTES:
            return reject(media.QUOTA_MESSAGE)

        asset = MediaAsset(
            owner=request.user,
            kind=kind,
            content_type=detected.content_type,
            size_bytes=upload.size,
        )
        asset.file.save(f"{asset.id}.{detected.ext}", upload, save=False)
        asset.save()
        return Response(
            {
                "id": str(asset.id),
                "kind": asset.kind,
                "url": request.build_absolute_uri(asset.file.url),
            },
            status=status.HTTP_201_CREATED,
        )
