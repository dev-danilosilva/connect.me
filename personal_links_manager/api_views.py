from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.exceptions import ValidationError
from rest_framework.generics import RetrieveAPIView
from rest_framework.permissions import IsAdminUser, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .forms import CreatePageForm
from .models import Block, LinkPage
from .permissions import IsPageOwner
from .serializers import BlockSerializer, LinkPageSerializer
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


class PageDetailAPIView(RetrieveAPIView):
    serializer_class = LinkPageSerializer
    permission_classes = [IsAuthenticated, IsPageOwner]
    lookup_field = "handle"
    lookup_url_kwarg = "handle"
    queryset = LinkPage.objects.all()


class BlockCreateAPIView(generics.CreateAPIView):
    serializer_class = BlockSerializer
    permission_classes = [IsAuthenticated, IsPageOwner]

    def get_page(self):
        page = get_object_or_404(LinkPage, handle=self.kwargs["handle"])
        self.check_object_permissions(self.request, page)
        return page

    def perform_create(self, serializer):
        page = self.get_page()
        block_type = serializer.validated_data["block_type"]
        has_header = page.blocks.filter(block_type=Block.BlockType.HEADER).exists()
        if block_type == Block.BlockType.HEADER and has_header:
            raise ValidationError({"block_type": "This page already has a header block."})
        serializer.save(page=page, position=page.blocks.count())
