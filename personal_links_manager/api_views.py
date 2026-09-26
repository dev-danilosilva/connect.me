from rest_framework.generics import RetrieveAPIView
from rest_framework.permissions import IsAdminUser, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .forms import CreatePageForm
from .models import LinkPage
from .permissions import IsPageOwner
from .serializers import LinkPageSerializer
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
