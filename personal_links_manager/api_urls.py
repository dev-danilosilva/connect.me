from django.urls import path

from .api_views import BlockCreateAPIView, BlockDetailAPIView, BlockReorderAPIView, PageDetailAPIView

urlpatterns = [
    path("pages/<str:handle>/", PageDetailAPIView.as_view(), name="api_page_detail"),
    path("pages/<str:handle>/blocks/", BlockCreateAPIView.as_view(), name="api_block_create"),
    path(
        "pages/<str:handle>/blocks/<int:block_id>/",
        BlockDetailAPIView.as_view(),
        name="api_block_detail",
    ),
    path(
        "pages/<str:handle>/blocks/reorder/",
        BlockReorderAPIView.as_view(),
        name="api_block_reorder",
    ),
]
