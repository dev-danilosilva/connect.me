from rest_framework.response import Response
from rest_framework.views import APIView

from .forms import CreatePageForm


class HandleAvailabilityAPIView(APIView):
    def get(self, request):
        handle = request.query_params.get("handle", "")
        form = CreatePageForm(data={"handle": handle})

        if form.is_valid():
            return Response({"status": "available", "message": "This handle is available."})

        message = form.errors["handle"][0]
        status = "taken" if message == "This handle is already taken." else "invalid"
        return Response({"status": status, "message": message})
