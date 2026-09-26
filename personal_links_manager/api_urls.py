from django.urls import path

from .api_views import BlockCreateAPIView, PageDetailAPIView

urlpatterns = [
    path("pages/<str:handle>/", PageDetailAPIView.as_view(), name="api_page_detail"),
    path("pages/<str:handle>/blocks/", BlockCreateAPIView.as_view(), name="api_block_create"),
]
