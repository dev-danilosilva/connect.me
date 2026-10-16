from django.urls import path

from . import views
from .api_views import (
    DraftLayoutAPIView,
    HandleAvailabilityAPIView,
    MediaUploadAPIView,
    PublishLayoutAPIView,
)

urlpatterns = [
    path("", views.home, name="home"),
    path("dashboard/", views.dashboard, name="dashboard"),
    path("dashboard/pages/create/", views.create_page, name="create_page"),
    path("dashboard/pages/<str:handle>/edit/", views.page_editor, name="page_editor"),
    path(
        "dashboard/handle-check/",
        HandleAvailabilityAPIView.as_view(),
        name="check_handle_availability",
    ),
    path("api/pages/<str:handle>/draft/", DraftLayoutAPIView.as_view(), name="api_page_draft"),
    path(
        "api/pages/<str:handle>/publish/",
        PublishLayoutAPIView.as_view(),
        name="api_page_publish",
    ),
    path("api/media/", MediaUploadAPIView.as_view(), name="api_media"),
]
