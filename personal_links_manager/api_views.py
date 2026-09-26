from django.shortcuts import get_object_or_404
from rest_framework import generics, mixins
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


class BlockDetailAPIView(mixins.UpdateModelMixin, mixins.DestroyModelMixin, generics.GenericAPIView):
    serializer_class = BlockSerializer
    permission_classes = [IsAuthenticated, IsPageOwner]
    lookup_url_kwarg = "block_id"

    def get_queryset(self):
        return Block.objects.filter(page__handle=self.kwargs["handle"])

    def patch(self, request, *args, **kwargs):
        return self.partial_update(request, *args, **kwargs)

    def delete(self, request, *args, **kwargs):
        return self.destroy(request, *args, **kwargs)


class BlockReorderAPIView(APIView):
    permission_classes = [IsAuthenticated, IsPageOwner]

    def post(self, request, handle):
        page = get_object_or_404(LinkPage, handle=handle)
        self.check_object_permissions(request, page)

        block_ids = request.data.get("block_ids", [])
        blocks_by_id = {block.id: block for block in page.blocks.all()}

        if set(block_ids) != set(blocks_by_id):
            raise ValidationError(
                {"block_ids": "Must include exactly the page's current block ids."}
            )

        for position, block_id in enumerate(block_ids):
            block = blocks_by_id[block_id]
            if block.position != position:
                block.position = position
                block.save(update_fields=["position"])

        return Response(LinkPageSerializer(page).data)
