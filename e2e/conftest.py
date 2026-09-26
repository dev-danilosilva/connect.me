import os

# pytest-playwright's sync API keeps an asyncio event loop alive on the main
# thread, which trips Django's SynchronousOnlyOperation false-positive check
# during live_server's database setup. This is the standard workaround for
# that known pytest-playwright/pytest-django interaction.
os.environ.setdefault("DJANGO_ALLOW_ASYNC_UNSAFE", "true")

import pytest

from accounts.models import User
from personal_links_manager.models import LinkPage


@pytest.fixture
def demo_user(transactional_db):
    return User.objects.create_user(
        email="test@example.com", password="password123", display_name="Tes Tuser"
    )


@pytest.fixture
def demo_page(demo_user):
    return LinkPage.objects.create(owner=demo_user, handle="existing-page")
