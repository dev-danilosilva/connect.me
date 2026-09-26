from django.urls import path

from . import views
from .api_views import HandleAvailabilityAPIView

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
]
