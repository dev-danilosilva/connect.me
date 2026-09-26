from django.urls import path

from . import views

urlpatterns = [
    path("", views.home, name="home"),
    path("dashboard/", views.dashboard, name="dashboard"),
    path("dashboard/pages/create/", views.create_page, name="create_page"),
    path(
        "dashboard/handle-check/",
        views.check_handle_availability,
        name="check_handle_availability",
    ),
]
