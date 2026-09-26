from django.conf import settings
from django.core.validators import RegexValidator
from django.db import models

from .utils import HANDLE_RE, humanize_handle


class LinkPage(models.Model):
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="pages"
    )
    handle = models.CharField(
        max_length=63,
        unique=True,
        validators=[
            RegexValidator(
                HANDLE_RE, "Only lowercase letters, numbers, and hyphens are allowed."
            )
        ],
    )
    title = models.CharField(max_length=150, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]

    def __str__(self):
        return self.handle

    def save(self, *args, **kwargs):
        if not self.title:
            self.title = humanize_handle(self.handle)
        super().save(*args, **kwargs)
