from django.contrib import admin

from .models import LinkPage


@admin.register(LinkPage)
class LinkPageAdmin(admin.ModelAdmin):
    list_display = ["handle", "title", "owner", "created_at"]
    search_fields = ["handle", "title", "owner__email"]
    list_filter = ["created_at"]
