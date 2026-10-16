import os

# pytest-playwright's sync API keeps an asyncio event loop alive on the main
# thread, which trips Django's SynchronousOnlyOperation false-positive check
# during live_server's database setup. This is the standard workaround for
# that known pytest-playwright/pytest-django interaction.
os.environ.setdefault("DJANGO_ALLOW_ASYNC_UNSAFE", "true")

import pytest

from accounts.models import User
from personal_links_manager.models import LinkPage
from personal_links_manager.tests.layouts import sample_layout


@pytest.fixture(scope="session", autouse=True)
def elm_bundle():
    """The Elm bundle isn't committed, so build it if it's missing or older
    than its sources (e.g. on a fresh clone, or without `runserver` running).
    Uses debug mode to match what `runserver` produces."""
    from frontend import elm

    if elm.bundle_is_stale():
        ok, output = elm.compile_elm(debug=True)
        if not ok:
            pytest.exit(f"Elm compile failed:\n{output}", returncode=1)


@pytest.fixture
def demo_user(transactional_db):
    return User.objects.create_user(
        email="test@example.com", password="password123", display_name="Tes Tuser"
    )


@pytest.fixture
def demo_page(demo_user):
    return LinkPage.objects.create(owner=demo_user, handle="existing-page")


@pytest.fixture
def demo_page_with_layout(demo_user):
    """A page whose draft has the sample content: a hero, four socials and
    five link tiles."""
    return LinkPage.objects.create(
        owner=demo_user, handle="ada", title="Ada", draft_layout=sample_layout()
    )
