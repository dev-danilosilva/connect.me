"""
URL configuration for linktree_project project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.1/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import include, path

from pages.views import admin_dashboard_data

admin.site.site_header = "SharedLink admin"
admin.site.site_title = "SharedLink admin"
admin.site.index_title = "Dashboard"

urlpatterns = [
    # Must come before admin.site.urls, which would otherwise swallow
    # /admin/dashboard-data/ trying to resolve it as an app label.
    path('admin/dashboard-data/', admin_dashboard_data, name='admin_dashboard_data'),
    path('admin/', admin.site.urls),
    path('', include('pages.urls')),
    path('', include('accounts.urls')),
]
