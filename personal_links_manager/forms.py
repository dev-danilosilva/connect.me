from django import forms

from .models import LinkPage
from .utils import HANDLE_RE, RESERVED_HANDLES


class CreatePageForm(forms.ModelForm):
    handle = forms.CharField(required=False)

    class Meta:
        model = LinkPage
        fields = ["handle"]

    def clean_handle(self):
        handle = self.cleaned_data.get("handle", "")

        if not handle:
            raise forms.ValidationError("Enter a handle first.")

        if not HANDLE_RE.match(handle):
            raise forms.ValidationError(
                "Only lowercase letters, numbers, and hyphens are allowed."
            )

        taken = handle in RESERVED_HANDLES or LinkPage.objects.filter(handle=handle).exists()
        if taken:
            raise forms.ValidationError("This handle is already taken.")

        return handle
