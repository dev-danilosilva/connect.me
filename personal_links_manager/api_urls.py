from django.urls import path

from .api_views import PageDetailAPIView

urlpatterns = [
    path("pages/<str:handle>/", PageDetailAPIView.as_view(), name="api_page_detail"),
]
