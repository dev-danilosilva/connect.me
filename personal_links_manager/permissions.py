from rest_framework.permissions import BasePermission


class IsPageOwner(BasePermission):
    """`obj` is either a LinkPage (has .owner) or something with a .page (e.g. Block)."""

    def has_object_permission(self, request, view, obj):
        page = obj if hasattr(obj, "owner") else obj.page
        return page.owner == request.user
