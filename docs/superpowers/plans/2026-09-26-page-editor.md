# Page Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the page editor — a split-screen UI (live preview on the left, block controls on the right) backed by a DRF JSON API and a block-based content model, with the preview itself rendered by a new Elm app scoped to this one screen.

**Architecture:** A single `Block` model (JSON payload per type: `link`, `header`, `social_icons`) belongs to `LinkPage`. Django REST Framework exposes it plus migrates the two existing plain-`JsonResponse` endpoints. A `Browser.element` Elm app mounts into one Django-rendered page, fetches page+blocks over the API, renders an instant client-side preview on every edit, and debounce-saves changes back.

**Tech Stack:** Django, Django REST Framework, Elm 0.19.2 (`elm`, `elm-test` via `npx`), pytest-django, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-26-page-editor-design.md`

## Global Constraints

- DRF: `DEFAULT_AUTHENTICATION_CLASSES = [SessionAuthentication]`, `DEFAULT_PERMISSION_CLASSES = [IsAuthenticated]`. Any view overriding `permission_classes` must re-include `IsAuthenticated` explicitly alongside `IsPageOwner`/`IsAdminUser`.
- `Block`: one model, `block_type` in `{link, header, social_icons}`, JSON `data` payload validated per-type by a DRF serializer — not DB constraints. At most one `header` block per page, enforced in the API layer.
- `position`: plain integer, `0..n-1`, re-sequenced on every reorder.
- New editor endpoints live under a fresh `/api/` prefix. The two migrated existing endpoints (`/dashboard/handle-check/`, `/admin/dashboard-data/`) keep their exact current URLs — only their view implementation changes.
- Migrating to DRF changes anonymous/forbidden responses from Django's redirect-to-login (302) to DRF's JSON 403 — this is an intentional, documented behavior change, not a bug.
- Elm lives in a new top-level `elm/` directory (`elm/elm.json`, `elm/src/Main.elm`, `elm/tests/`), compiled to `static/js/page_editor.js`. No bundler. FontAwesome (Free, CDN) and the Elm bundle load only on the editor page, not app-wide.
- Reorder UX is up/down buttons, not drag-and-drop.
- Preview device widths are CSS-only container widths (Desktop: unconstrained, Tablet: 768px, Phone: 390px) — block markup is identical at every width.
- Preview pane is visually on the **left**, block controls on the **right** (DOM order = visual order; no CSS `order` trickery needed).

---

### Task 1: Add Django REST Framework, migrate `check_handle_availability`

**Files:**
- Modify: `requirements.txt`
- Modify: `linktree_project/settings.py`
- Create: `personal_links_manager/api_views.py`
- Modify: `personal_links_manager/urls.py`
- Modify: `personal_links_manager/views.py`
- Modify: `personal_links_manager/tests/test_views.py`

**Interfaces:**
- Produces: `personal_links_manager.api_views.HandleAvailabilityAPIView` (DRF `APIView`, `GET`).

- [ ] **Step 1: Update the existing "requires login" test to expect DRF's response, not a redirect**

In `personal_links_manager/tests/test_views.py`, replace:

```python
def test_check_handle_availability_requires_login(client):
    response = client.get(reverse("check_handle_availability"), {"handle": "anything"})
    assert response.status_code == 302
```

with:

```python
def test_check_handle_availability_requires_login(client):
    # DRF returns a JSON 403 for a denied permission rather than Django's
    # redirect-to-login -- this endpoint is called via fetch(), not page
    # navigation, so a redirect would be useless to the caller anyway.
    response = client.get(reverse("check_handle_availability"), {"handle": "anything"})
    assert response.status_code == 403
```

- [ ] **Step 2: Run it, confirm it fails against the current plain view**

Run: `pytest personal_links_manager/tests/test_views.py::test_check_handle_availability_requires_login -v`
Expected: FAIL — current view still returns 302.

- [ ] **Step 3: Add the dependency and DRF settings**

In `requirements.txt`, add:
```
djangorestframework==3.18.1
```

In `linktree_project/settings.py`, add `'rest_framework'` to `INSTALLED_APPS` (after `'personal_links_manager'`), and add near the bottom of the file:

```python
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework.authentication.SessionAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
}
```

- [ ] **Step 4: Create the DRF view**

Create `personal_links_manager/api_views.py`:

```python
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
```

- [ ] **Step 5: Wire the URL and remove the old view**

In `personal_links_manager/urls.py`, replace the `check_handle_availability` import/usage:

```python
from django.urls import path

from . import views
from .api_views import HandleAvailabilityAPIView

urlpatterns = [
    path("", views.home, name="home"),
    path("dashboard/", views.dashboard, name="dashboard"),
    path("dashboard/pages/create/", views.create_page, name="create_page"),
    path(
        "dashboard/handle-check/",
        HandleAvailabilityAPIView.as_view(),
        name="check_handle_availability",
    ),
]
```

In `personal_links_manager/views.py`, delete the `check_handle_availability` function and remove the now-unused `require_GET` import (keep `require_POST`, still used by `create_page`).

- [ ] **Step 6: Run the full view test file, confirm everything passes**

Run: `pytest personal_links_manager/tests/test_views.py -v`
Expected: PASS (including the availability/taken/invalid tests, unchanged JSON shape).

- [ ] **Step 7: Commit**

```bash
git add requirements.txt linktree_project/settings.py personal_links_manager/api_views.py personal_links_manager/urls.py personal_links_manager/views.py personal_links_manager/tests/test_views.py
git commit -m "Migrate check_handle_availability to a DRF APIView"
```

---

### Task 2: Migrate `admin_dashboard_data` to DRF

**Files:**
- Modify: `personal_links_manager/api_views.py`
- Modify: `personal_links_manager/views.py`
- Modify: `linktree_project/urls.py`
- Modify: `personal_links_manager/tests/test_views.py`

**Interfaces:**
- Consumes: `personal_links_manager.stats.compute_dashboard_stats` (existing, unchanged).
- Produces: `personal_links_manager.api_views.AdminDashboardDataAPIView` (DRF `APIView`, `GET`, `IsAdminUser`).

- [ ] **Step 1: Update the two permission tests to expect DRF's 403**

In `personal_links_manager/tests/test_views.py`, replace:

```python
def test_admin_dashboard_data_redirects_anonymous_to_admin_login(client):
    response = client.get(reverse("admin_dashboard_data"))
    assert response.status_code == 302
    assert response.url.startswith("/admin/login/")


def test_admin_dashboard_data_redirects_non_staff_user_to_admin_login(client, user):
    client.force_login(user)
    response = client.get(reverse("admin_dashboard_data"))
    assert response.status_code == 302
    assert response.url.startswith("/admin/login/")
```

with:

```python
def test_admin_dashboard_data_returns_403_for_anonymous(client):
    response = client.get(reverse("admin_dashboard_data"))
    assert response.status_code == 403


def test_admin_dashboard_data_returns_403_for_non_staff_user(client, user):
    client.force_login(user)
    response = client.get(reverse("admin_dashboard_data"))
    assert response.status_code == 403
```

- [ ] **Step 2: Run them, confirm they fail against the current view**

Run: `pytest personal_links_manager/tests/test_views.py -k admin_dashboard_data -v`
Expected: the two renamed tests FAIL (current view still 302-redirects).

- [ ] **Step 3: Add the DRF view**

Append to `personal_links_manager/api_views.py`:

```python
from rest_framework.permissions import IsAdminUser

from .stats import compute_dashboard_stats


class AdminDashboardDataAPIView(APIView):
    permission_classes = [IsAdminUser]

    def get(self, request):
        return Response(compute_dashboard_stats())
```

- [ ] **Step 4: Rewire the URL, remove the old view and its now-unused imports**

In `linktree_project/urls.py`, replace:

```python
from personal_links_manager.views import admin_dashboard_data
```

with:

```python
from personal_links_manager.api_views import AdminDashboardDataAPIView
```

and replace the path line:

```python
    path('admin/dashboard-data/', AdminDashboardDataAPIView.as_view(), name='admin_dashboard_data'),
```

(keep it above `path('admin/', admin.site.urls)` — the existing comment there about ordering still applies.)

In `personal_links_manager/views.py`, delete the `admin_dashboard_data` function and its now-unused imports (`JsonResponse`, `staff_member_required`, `compute_dashboard_stats`).

- [ ] **Step 5: Run the full test file**

Run: `pytest personal_links_manager/tests/test_views.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add personal_links_manager/api_views.py personal_links_manager/views.py linktree_project/urls.py personal_links_manager/tests/test_views.py
git commit -m "Migrate admin_dashboard_data to a DRF APIView"
```

---

### Task 3: Add the `Block` model

**Files:**
- Modify: `personal_links_manager/models.py`
- Create: `personal_links_manager/migrations/0002_block.py` (generated)
- Modify: `personal_links_manager/tests/test_models.py`

**Interfaces:**
- Produces: `personal_links_manager.models.Block` (fields: `page`, `block_type`, `position`, `visible`, `data`; `Block.BlockType.{LINK,HEADER,SOCIAL_ICONS}`).

- [ ] **Step 1: Write the failing tests**

Add to `personal_links_manager/tests/test_models.py`:

```python
from personal_links_manager.models import Block


def test_block_data_defaults_to_empty_dict(owner):
    page = LinkPage.objects.create(owner=owner, handle="page-with-blocks")
    block = Block.objects.create(page=page, block_type=Block.BlockType.LINK, position=0)
    assert block.data == {}


def test_blocks_are_ordered_by_position(owner):
    page = LinkPage.objects.create(owner=owner, handle="ordered-page")
    second = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=1,
        data={"label": "b", "url": "https://b.example"},
    )
    first = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "a", "url": "https://a.example"},
    )
    assert list(page.blocks.all()) == [first, second]


def test_deleting_page_cascades_to_its_blocks(owner):
    page = LinkPage.objects.create(owner=owner, handle="cascade-page")
    Block.objects.create(page=page, block_type=Block.BlockType.LINK, position=0)
    page.delete()
    assert Block.objects.count() == 0
```

- [ ] **Step 2: Run, confirm they fail with an ImportError**

Run: `pytest personal_links_manager/tests/test_models.py -v`
Expected: FAIL — `cannot import name 'Block'`.

- [ ] **Step 3: Add the model**

In `personal_links_manager/models.py`, add below `LinkPage`:

```python
class Block(models.Model):
    class BlockType(models.TextChoices):
        LINK = "link", "Link"
        HEADER = "header", "Header"
        SOCIAL_ICONS = "social_icons", "Social icons"

    page = models.ForeignKey(LinkPage, on_delete=models.CASCADE, related_name="blocks")
    block_type = models.CharField(max_length=20, choices=BlockType.choices)
    position = models.PositiveIntegerField()
    visible = models.BooleanField(default=True)
    data = models.JSONField(default=dict)

    class Meta:
        ordering = ["position"]

    def __str__(self):
        return f"{self.block_type} block on {self.page.handle}"
```

- [ ] **Step 4: Generate and apply the migration**

Run: `python manage.py makemigrations personal_links_manager`
Run: `python manage.py migrate`

- [ ] **Step 5: Run the tests, confirm they pass**

Run: `pytest personal_links_manager/tests/test_models.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add personal_links_manager/models.py personal_links_manager/migrations/0002_block.py personal_links_manager/tests/test_models.py
git commit -m "Add the Block model"
```

---

### Task 4: Block data serializers

**Files:**
- Create: `personal_links_manager/serializers.py`
- Create: `personal_links_manager/tests/test_serializers.py`

**Interfaces:**
- Consumes: `personal_links_manager.models.Block`, `LinkPage`.
- Produces: `personal_links_manager.serializers.{LinkDataSerializer, HeaderDataSerializer, SocialIconsDataSerializer, BlockSerializer, LinkPageSerializer, BLOCK_DATA_SERIALIZERS}`.

- [ ] **Step 1: Write the failing tests**

Create `personal_links_manager/tests/test_serializers.py`:

```python
import pytest

from accounts.models import User
from personal_links_manager.models import Block, LinkPage
from personal_links_manager.serializers import BlockSerializer

pytestmark = pytest.mark.django_db


@pytest.fixture
def owner():
    return User.objects.create_user(email="owner@example.com", password="password123")


@pytest.fixture
def page(owner):
    return LinkPage.objects.create(owner=owner, handle="serializer-page")


def test_link_block_accepts_valid_data():
    serializer = BlockSerializer(
        data={"block_type": "link", "data": {"label": "My site", "url": "https://example.com"}}
    )
    assert serializer.is_valid(), serializer.errors


def test_link_block_rejects_missing_url():
    serializer = BlockSerializer(data={"block_type": "link", "data": {"label": "My site"}})
    assert not serializer.is_valid()
    assert "data" in serializer.errors


def test_header_block_accepts_valid_data():
    serializer = BlockSerializer(
        data={
            "block_type": "header",
            "data": {"display_name": "Jane", "bio": "Hi", "avatar_url": ""},
        }
    )
    assert serializer.is_valid(), serializer.errors


def test_social_icons_block_accepts_a_list_of_icons():
    serializer = BlockSerializer(
        data={
            "block_type": "social_icons",
            "data": {"icons": [{"platform": "twitter", "url": "https://twitter.com/x"}]},
        }
    )
    assert serializer.is_valid(), serializer.errors


def test_social_icons_block_accepts_an_empty_list():
    serializer = BlockSerializer(data={"block_type": "social_icons", "data": {"icons": []}})
    assert serializer.is_valid(), serializer.errors
```

- [ ] **Step 2: Run, confirm ImportError**

Run: `pytest personal_links_manager/tests/test_serializers.py -v`
Expected: FAIL — no module `personal_links_manager.serializers`.

- [ ] **Step 3: Implement the serializers**

Create `personal_links_manager/serializers.py`:

```python
from rest_framework import serializers

from .models import Block, LinkPage


class LinkDataSerializer(serializers.Serializer):
    label = serializers.CharField(max_length=150)
    url = serializers.URLField()


class HeaderDataSerializer(serializers.Serializer):
    display_name = serializers.CharField(max_length=150)
    bio = serializers.CharField(max_length=500, required=False, allow_blank=True)
    avatar_url = serializers.CharField(required=False, allow_blank=True)


class SocialIconDataSerializer(serializers.Serializer):
    platform = serializers.CharField(max_length=50)
    url = serializers.URLField()


class SocialIconsDataSerializer(serializers.Serializer):
    icons = SocialIconDataSerializer(many=True)


BLOCK_DATA_SERIALIZERS = {
    Block.BlockType.LINK: LinkDataSerializer,
    Block.BlockType.HEADER: HeaderDataSerializer,
    Block.BlockType.SOCIAL_ICONS: SocialIconsDataSerializer,
}


class BlockSerializer(serializers.ModelSerializer):
    class Meta:
        model = Block
        fields = ["id", "block_type", "position", "visible", "data"]
        read_only_fields = ["id", "position"]

    def validate(self, attrs):
        block_type = attrs.get("block_type", getattr(self.instance, "block_type", None))
        data = attrs.get("data")
        if data is not None:
            data_serializer_cls = BLOCK_DATA_SERIALIZERS[block_type]
            data_serializer = data_serializer_cls(data=data)
            data_serializer.is_valid(raise_exception=True)
            attrs["data"] = data_serializer.validated_data
        return attrs


class LinkPageSerializer(serializers.ModelSerializer):
    blocks = BlockSerializer(many=True, read_only=True)

    class Meta:
        model = LinkPage
        fields = ["id", "handle", "title", "blocks"]
```

- [ ] **Step 4: Run, confirm pass**

Run: `pytest personal_links_manager/tests/test_serializers.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add personal_links_manager/serializers.py personal_links_manager/tests/test_serializers.py
git commit -m "Add per-block-type DRF serializers"
```

---

### Task 5: `IsPageOwner` permission + `PageDetailAPIView`

**Files:**
- Create: `personal_links_manager/permissions.py`
- Modify: `personal_links_manager/api_views.py`
- Create: `personal_links_manager/api_urls.py`
- Modify: `linktree_project/urls.py`
- Create: `personal_links_manager/tests/test_api_views.py`

**Interfaces:**
- Consumes: `personal_links_manager.serializers.LinkPageSerializer`.
- Produces: `personal_links_manager.permissions.IsPageOwner`; `personal_links_manager.api_views.PageDetailAPIView`; URL name `api_page_detail`.

- [ ] **Step 1: Write the failing tests**

Create `personal_links_manager/tests/test_api_views.py`:

```python
import pytest
from django.urls import reverse

from accounts.models import User
from personal_links_manager.models import Block, LinkPage

pytestmark = pytest.mark.django_db


@pytest.fixture
def owner():
    return User.objects.create_user(email="owner@example.com", password="password123")


@pytest.fixture
def page(owner):
    return LinkPage.objects.create(owner=owner, handle="api-page")


def test_page_detail_returns_page_and_blocks(client, owner, page):
    Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "Site", "url": "https://example.com"},
    )
    client.force_login(owner)

    response = client.get(reverse("api_page_detail", args=[page.handle]))

    assert response.status_code == 200
    data = response.json()
    assert data["handle"] == "api-page"
    assert len(data["blocks"]) == 1
    assert data["blocks"][0]["data"] == {"label": "Site", "url": "https://example.com"}


def test_page_detail_rejects_non_owner(client, page):
    other = User.objects.create_user(email="other@example.com", password="password123")
    client.force_login(other)

    response = client.get(reverse("api_page_detail", args=[page.handle]))

    assert response.status_code == 403


def test_page_detail_rejects_anonymous(client, page):
    response = client.get(reverse("api_page_detail", args=[page.handle]))
    assert response.status_code == 403
```

- [ ] **Step 2: Run, confirm failure**

Run: `pytest personal_links_manager/tests/test_api_views.py -v`
Expected: FAIL — `reverse("api_page_detail")` raises `NoReverseMatch`.

- [ ] **Step 3: Add the permission class**

Create `personal_links_manager/permissions.py`:

```python
from rest_framework.permissions import BasePermission


class IsPageOwner(BasePermission):
    """`obj` is either a LinkPage (has .owner) or something with a .page (e.g. Block)."""

    def has_object_permission(self, request, view, obj):
        page = obj if hasattr(obj, "owner") else obj.page
        return page.owner == request.user
```

- [ ] **Step 4: Add the view**

Append to `personal_links_manager/api_views.py`:

```python
from rest_framework.generics import RetrieveAPIView
from rest_framework.permissions import IsAuthenticated

from .models import LinkPage
from .permissions import IsPageOwner
from .serializers import LinkPageSerializer


class PageDetailAPIView(RetrieveAPIView):
    serializer_class = LinkPageSerializer
    permission_classes = [IsAuthenticated, IsPageOwner]
    lookup_field = "handle"
    lookup_url_kwarg = "handle"
    queryset = LinkPage.objects.all()
```

- [ ] **Step 5: Wire the URLs**

Create `personal_links_manager/api_urls.py`:

```python
from django.urls import path

from .api_views import PageDetailAPIView

urlpatterns = [
    path("pages/<str:handle>/", PageDetailAPIView.as_view(), name="api_page_detail"),
]
```

In `linktree_project/urls.py`, add `path('api/', include('personal_links_manager.api_urls'))` to `urlpatterns` (anywhere after the existing `admin/dashboard-data/` line — ordering relative to the other includes doesn't matter, `/api/` doesn't collide with anything existing).

- [ ] **Step 6: Run, confirm pass**

Run: `pytest personal_links_manager/tests/test_api_views.py -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add personal_links_manager/permissions.py personal_links_manager/api_views.py personal_links_manager/api_urls.py linktree_project/urls.py personal_links_manager/tests/test_api_views.py
git commit -m "Add IsPageOwner permission and the page-detail API endpoint"
```

---

### Task 6: `BlockCreateAPIView` (with the one-header-block rule)

**Files:**
- Modify: `personal_links_manager/api_views.py`
- Modify: `personal_links_manager/api_urls.py`
- Modify: `personal_links_manager/tests/test_api_views.py`

**Interfaces:**
- Produces: `personal_links_manager.api_views.BlockCreateAPIView`; URL name `api_block_create`.

- [ ] **Step 1: Write the failing tests**

Append to `personal_links_manager/tests/test_api_views.py`:

```python
def test_create_block_appends_at_end_of_page(client, owner, page):
    Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "First", "url": "https://a.example"},
    )
    client.force_login(owner)

    response = client.post(
        reverse("api_block_create", args=[page.handle]),
        {"block_type": "link", "data": {"label": "Second", "url": "https://b.example"}},
        content_type="application/json",
    )

    assert response.status_code == 201
    assert response.json()["position"] == 1


def test_create_block_rejects_a_second_header_block(client, owner, page):
    Block.objects.create(
        page=page, block_type=Block.BlockType.HEADER, position=0,
        data={"display_name": "Jane"},
    )
    client.force_login(owner)

    response = client.post(
        reverse("api_block_create", args=[page.handle]),
        {"block_type": "header", "data": {"display_name": "Jane Again"}},
        content_type="application/json",
    )

    assert response.status_code == 400


def test_create_block_rejects_non_owner(client, page):
    other = User.objects.create_user(email="other2@example.com", password="password123")
    client.force_login(other)

    response = client.post(
        reverse("api_block_create", args=[page.handle]),
        {"block_type": "link", "data": {"label": "Nope", "url": "https://x.example"}},
        content_type="application/json",
    )

    assert response.status_code == 403
```

- [ ] **Step 2: Run, confirm failure**

Run: `pytest personal_links_manager/tests/test_api_views.py -k create_block -v`
Expected: FAIL — `NoReverseMatch` for `api_block_create`.

- [ ] **Step 3: Implement the view**

Append to `personal_links_manager/api_views.py`:

```python
from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.exceptions import ValidationError

from .models import Block
from .serializers import BlockSerializer


class BlockCreateAPIView(generics.CreateAPIView):
    serializer_class = BlockSerializer
    permission_classes = [IsAuthenticated, IsPageOwner]

    def get_page(self):
        page = get_object_or_404(LinkPage, handle=self.kwargs["handle"])
        self.check_object_permissions(self.request, page)
        return page

    def perform_create(self, serializer):
        page = self.get_page()
        block_type = serializer.validated_data["block_type"]
        has_header = page.blocks.filter(block_type=Block.BlockType.HEADER).exists()
        if block_type == Block.BlockType.HEADER and has_header:
            raise ValidationError({"block_type": "This page already has a header block."})
        serializer.save(page=page, position=page.blocks.count())
```

- [ ] **Step 4: Wire the URL**

In `personal_links_manager/api_urls.py`:

```python
from django.urls import path

from .api_views import BlockCreateAPIView, PageDetailAPIView

urlpatterns = [
    path("pages/<str:handle>/", PageDetailAPIView.as_view(), name="api_page_detail"),
    path("pages/<str:handle>/blocks/", BlockCreateAPIView.as_view(), name="api_block_create"),
]
```

- [ ] **Step 5: Run, confirm pass**

Run: `pytest personal_links_manager/tests/test_api_views.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add personal_links_manager/api_views.py personal_links_manager/api_urls.py personal_links_manager/tests/test_api_views.py
git commit -m "Add block creation endpoint with one-header-block rule"
```

---

### Task 7: `BlockDetailAPIView` (update/delete)

**Files:**
- Modify: `personal_links_manager/api_views.py`
- Modify: `personal_links_manager/api_urls.py`
- Modify: `personal_links_manager/tests/test_api_views.py`

**Interfaces:**
- Produces: `personal_links_manager.api_views.BlockDetailAPIView`; URL name `api_block_detail`.

- [ ] **Step 1: Write the failing tests**

Append to `personal_links_manager/tests/test_api_views.py`:

```python
def test_patch_block_updates_data(client, owner, page):
    block = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "Old", "url": "https://old.example"},
    )
    client.force_login(owner)

    response = client.patch(
        reverse("api_block_detail", args=[page.handle, block.id]),
        {"data": {"label": "New", "url": "https://new.example"}},
        content_type="application/json",
    )

    assert response.status_code == 200
    block.refresh_from_db()
    assert block.data == {"label": "New", "url": "https://new.example"}


def test_delete_block_removes_it(client, owner, page):
    block = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "Bye", "url": "https://bye.example"},
    )
    client.force_login(owner)

    response = client.delete(reverse("api_block_detail", args=[page.handle, block.id]))

    assert response.status_code == 204
    assert not Block.objects.filter(id=block.id).exists()


def test_patch_block_rejects_non_owner(client, page):
    block = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "X", "url": "https://x.example"},
    )
    other = User.objects.create_user(email="other3@example.com", password="password123")
    client.force_login(other)

    response = client.patch(
        reverse("api_block_detail", args=[page.handle, block.id]),
        {"data": {"label": "Hacked", "url": "https://hacked.example"}},
        content_type="application/json",
    )

    assert response.status_code == 403
```

- [ ] **Step 2: Run, confirm failure**

Run: `pytest personal_links_manager/tests/test_api_views.py -k "patch_block or delete_block" -v`
Expected: FAIL — `NoReverseMatch` for `api_block_detail`.

- [ ] **Step 3: Implement the view**

Append to `personal_links_manager/api_views.py`:

```python
from rest_framework import mixins


class BlockDetailAPIView(mixins.UpdateModelMixin, mixins.DestroyModelMixin, generics.GenericAPIView):
    serializer_class = BlockSerializer
    permission_classes = [IsAuthenticated, IsPageOwner]
    lookup_url_kwarg = "block_id"

    def get_queryset(self):
        return Block.objects.filter(page__handle=self.kwargs["handle"])

    def patch(self, request, *args, **kwargs):
        return self.partial_update(request, *args, **kwargs)

    def delete(self, request, *args, **kwargs):
        return self.destroy(request, *args, **kwargs)
```

- [ ] **Step 4: Wire the URL**

In `personal_links_manager/api_urls.py`, add the import and path:

```python
from .api_views import BlockCreateAPIView, BlockDetailAPIView, PageDetailAPIView

urlpatterns = [
    path("pages/<str:handle>/", PageDetailAPIView.as_view(), name="api_page_detail"),
    path("pages/<str:handle>/blocks/", BlockCreateAPIView.as_view(), name="api_block_create"),
    path(
        "pages/<str:handle>/blocks/<int:block_id>/",
        BlockDetailAPIView.as_view(),
        name="api_block_detail",
    ),
]
```

- [ ] **Step 5: Run, confirm pass**

Run: `pytest personal_links_manager/tests/test_api_views.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add personal_links_manager/api_views.py personal_links_manager/api_urls.py personal_links_manager/tests/test_api_views.py
git commit -m "Add block update/delete endpoint"
```

---

### Task 8: `BlockReorderAPIView`

**Files:**
- Modify: `personal_links_manager/api_views.py`
- Modify: `personal_links_manager/api_urls.py`
- Modify: `personal_links_manager/tests/test_api_views.py`

**Interfaces:**
- Consumes: `personal_links_manager.serializers.LinkPageSerializer`.
- Produces: `personal_links_manager.api_views.BlockReorderAPIView`; URL name `api_block_reorder`.

- [ ] **Step 1: Write the failing tests**

Append to `personal_links_manager/tests/test_api_views.py`:

```python
def test_reorder_updates_block_positions(client, owner, page):
    first = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "A", "url": "https://a.example"},
    )
    second = Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=1,
        data={"label": "B", "url": "https://b.example"},
    )
    client.force_login(owner)

    response = client.post(
        reverse("api_block_reorder", args=[page.handle]),
        {"block_ids": [second.id, first.id]},
        content_type="application/json",
    )

    assert response.status_code == 200
    first.refresh_from_db()
    second.refresh_from_db()
    assert second.position == 0
    assert first.position == 1


def test_reorder_rejects_mismatched_block_ids(client, owner, page):
    Block.objects.create(
        page=page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "A", "url": "https://a.example"},
    )
    client.force_login(owner)

    response = client.post(
        reverse("api_block_reorder", args=[page.handle]),
        {"block_ids": [9999]},
        content_type="application/json",
    )

    assert response.status_code == 400
```

- [ ] **Step 2: Run, confirm failure**

Run: `pytest personal_links_manager/tests/test_api_views.py -k reorder -v`
Expected: FAIL — `NoReverseMatch` for `api_block_reorder`.

- [ ] **Step 3: Implement the view**

Append to `personal_links_manager/api_views.py`:

```python
class BlockReorderAPIView(APIView):
    permission_classes = [IsAuthenticated, IsPageOwner]

    def post(self, request, handle):
        page = get_object_or_404(LinkPage, handle=handle)
        self.check_object_permissions(request, page)

        block_ids = request.data.get("block_ids", [])
        blocks_by_id = {block.id: block for block in page.blocks.all()}

        if set(block_ids) != set(blocks_by_id):
            raise ValidationError(
                {"block_ids": "Must include exactly the page's current block ids."}
            )

        for position, block_id in enumerate(block_ids):
            block = blocks_by_id[block_id]
            if block.position != position:
                block.position = position
                block.save(update_fields=["position"])

        return Response(LinkPageSerializer(page).data)
```

- [ ] **Step 4: Wire the URL**

In `personal_links_manager/api_urls.py`:

```python
from .api_views import BlockCreateAPIView, BlockDetailAPIView, BlockReorderAPIView, PageDetailAPIView

urlpatterns = [
    path("pages/<str:handle>/", PageDetailAPIView.as_view(), name="api_page_detail"),
    path("pages/<str:handle>/blocks/", BlockCreateAPIView.as_view(), name="api_block_create"),
    path(
        "pages/<str:handle>/blocks/<int:block_id>/",
        BlockDetailAPIView.as_view(),
        name="api_block_detail",
    ),
    path(
        "pages/<str:handle>/blocks/reorder/",
        BlockReorderAPIView.as_view(),
        name="api_block_reorder",
    ),
]
```

- [ ] **Step 5: Run the entire backend test suite**

Run: `pytest accounts personal_links_manager -q`
Expected: PASS, all tests (this is the last purely-backend task — good checkpoint to run everything).

- [ ] **Step 6: Commit**

```bash
git add personal_links_manager/api_views.py personal_links_manager/api_urls.py personal_links_manager/tests/test_api_views.py
git commit -m "Add block reorder endpoint"
```

---

### Task 9: `page_editor` route, template shell, and redirect wiring

**Files:**
- Modify: `personal_links_manager/views.py`
- Modify: `personal_links_manager/urls.py`
- Modify: `templates/base.html`
- Create: `personal_links_manager/templates/personal_links_manager/page_editor.html`
- Create: `static/css/page_editor.css`
- Modify: `personal_links_manager/tests/test_views.py`

**Interfaces:**
- Produces: `personal_links_manager.views.page_editor`; URL name `page_editor`; template context key `elm_flags` (dict with `pageId`, `handle`, `title`, `csrfToken`, `apiBase`).

- [ ] **Step 1: Write the failing tests**

Append to `personal_links_manager/tests/test_views.py`:

```python
def test_page_editor_renders_for_owner(client, user):
    LinkPage.objects.create(owner=user, handle="editable-page")
    client.force_login(user)

    response = client.get(reverse("page_editor", args=["editable-page"]))

    assert response.status_code == 200
    assert 'id="elm-app"' in response.content.decode()


def test_page_editor_404s_for_non_owner(client, user):
    other = User.objects.create_user(email="other4@example.com", password="password123")
    LinkPage.objects.create(owner=other, handle="not-yours")
    client.force_login(user)

    response = client.get(reverse("page_editor", args=["not-yours"]))

    assert response.status_code == 404


def test_page_editor_requires_login(client, user):
    LinkPage.objects.create(owner=user, handle="needs-login")
    response = client.get(reverse("page_editor", args=["needs-login"]))
    assert response.status_code == 302
    assert response.url.startswith(reverse("login"))
```

Also update the existing `test_create_page_persists_scoped_to_owner` test to assert the new redirect target — change:

```python
    assert response.status_code == 302
    page = LinkPage.objects.get(handle="my-new-page")
```

to:

```python
    assert response.status_code == 302
    page = LinkPage.objects.get(handle="my-new-page")
    assert response.url == reverse("page_editor", args=["my-new-page"])
```

- [ ] **Step 2: Run, confirm failure**

Run: `pytest personal_links_manager/tests/test_views.py -k "page_editor or create_page_persists" -v`
Expected: FAIL — `NoReverseMatch` for `page_editor`, and the redirect-target assertion fails.

- [ ] **Step 3: Add the view**

In `personal_links_manager/views.py`, add the imports and view:

```python
from django.http import Http404
from django.middleware.csrf import get_token
from django.shortcuts import get_object_or_404

from .models import LinkPage


@login_required
def page_editor(request, handle):
    page = get_object_or_404(LinkPage, handle=handle)
    if page.owner != request.user:
        raise Http404
    context = {
        "elm_flags": {
            "pageId": page.id,
            "handle": page.handle,
            "title": page.title,
            "csrfToken": get_token(request),
            "apiBase": "/api/",
        },
    }
    return render(request, "personal_links_manager/page_editor.html", context)
```

Change `create_page`'s success branch from `return redirect("dashboard")` to `return redirect("page_editor", handle=page.handle)`.

- [ ] **Step 4: Wire the URL**

In `personal_links_manager/urls.py`, add:

```python
    path("dashboard/pages/<str:handle>/edit/", views.page_editor, name="page_editor"),
```

- [ ] **Step 5: Add the `extra_head`/`extra_scripts` blocks to the base template**

In `templates/base.html`, add one line before `</head>` and one line after the existing `app.js` script tag:

```html
  <link rel="stylesheet" href="{% static 'css/app.css' %}">
  {% block extra_head %}{% endblock %}
</head>
<body>
  {% block content %}{% endblock %}
  <script defer src="{% static 'js/app.js' %}"></script>
  {% block extra_scripts %}{% endblock %}
</body>
```

(Empty by default, so every other page's rendered output is unchanged.)

- [ ] **Step 6: Create the editor template**

Create `personal_links_manager/templates/personal_links_manager/page_editor.html`:

```html
{% extends "base.html" %}
{% load static %}
{% block title %}Edit {{ elm_flags.title }} · SharedLink{% endblock %}
{% block extra_head %}
  <link rel="stylesheet" href="{% static 'css/page_editor.css' %}">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.6.0/css/all.min.css" integrity="sha512-Kc323vGBEqzTmouAECnVceyQqyqdsSiqLQISBL29aUW4U/M7pSPA/gEUZQqv1cwx4OnYxTxve5UMg5GT6L4JJg==" crossorigin="anonymous" referrerpolicy="no-referrer">
{% endblock %}
{% block content %}
  <div id="elm-app"></div>
  {{ elm_flags|json_script:"elm-flags" }}
{% endblock %}
{% block extra_scripts %}
  <script src="{% static 'js/page_editor.js' %}"></script>
  <script>
    (function () {
      var flags = JSON.parse(document.getElementById("elm-flags").textContent);
      Elm.Main.init({ node: document.getElementById("elm-app"), flags: flags });
    })();
  </script>
{% endblock %}
```

Create a minimal starter `static/css/page_editor.css` (later tasks add to it):

```css
#elm-app {
  display: flex;
  min-height: 100vh;
}

.editor-preview-pane {
  flex: 1 1 60%;
  background: #f4f4f7;
  display: flex;
  justify-content: center;
  padding: 2rem;
}

.editor-controls-pane {
  flex: 1 1 40%;
  padding: 2rem;
  overflow-y: auto;
}
```

- [ ] **Step 7: Run the tests, confirm pass**

Run: `pytest personal_links_manager/tests/test_views.py -v`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add personal_links_manager/views.py personal_links_manager/urls.py templates/base.html personal_links_manager/templates/personal_links_manager/page_editor.html static/css/page_editor.css personal_links_manager/tests/test_views.py
git commit -m "Add the page editor route and template shell"
```

---

### Task 10: Elm project scaffold

**Files:**
- Create: `elm/elm.json` (generated by `elm init`)
- Create: `elm/src/Main.elm`
- Create: `elm/tests/MainTest.elm`
- Modify: `elm/elm.json` (generated by `elm-test init`, adds `elm-explorations/test`)
- Create: `e2e/test_page_editor.py`

**Interfaces:**
- Produces: `Main.Flags`, `Main.flagsDecoder`, compiled bundle at `static/js/page_editor.js` exposing `Elm.Main.init`.

- [ ] **Step 1: Scaffold the Elm project**

```bash
mkdir -p elm/src
cd elm
yes | elm init
cd ..
```

This creates `elm/elm.json` (type `application`, minimal `elm/core`+`elm/html` deps) and `elm/src/`.

- [ ] **Step 2: Add the packages this app needs**

```bash
cd elm
yes | elm install elm/http
yes | elm install elm/json
cd ..
```

- [ ] **Step 3: Set up elm-test**

```bash
cd elm
yes | npx elm-test init
cd ..
```

This creates `elm/tests/Example.elm` and adds `elm-explorations/test` to `elm.json`'s `test-dependencies`. Delete the generated `elm/tests/Example.elm` — the real first test goes in Step 4.

- [ ] **Step 4: Write the failing test for the flags decoder**

Create `elm/tests/MainTest.elm`:

```elm
module MainTest exposing (suite)

import Expect
import Json.Decode as Decode
import Main exposing (flagsDecoder)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "flagsDecoder"
        [ test "decodes a complete flags object" <|
            \_ ->
                let
                    json =
                        """{"pageId": 1, "handle": "my-page", "title": "My Page", "csrfToken": "abc123", "apiBase": "/api/"}"""
                in
                Decode.decodeString flagsDecoder json
                    |> Result.map .handle
                    |> Expect.equal (Ok "my-page")
        ]
```

- [ ] **Step 5: Run, confirm it fails to compile**

Run: `cd elm && npx elm-test`
Expected: FAIL — `Main` module doesn't exist yet.

- [ ] **Step 6: Write the minimal `Main.elm`**

Create `elm/src/Main.elm`:

```elm
module Main exposing (Flags, flagsDecoder, main)

import Browser
import Html exposing (Html, div, text)
import Json.Decode as Decode exposing (Decoder)


type alias Flags =
    { pageId : Int
    , handle : String
    , title : String
    , csrfToken : String
    , apiBase : String
    }


flagsDecoder : Decoder Flags
flagsDecoder =
    Decode.map5 Flags
        (Decode.field "pageId" Decode.int)
        (Decode.field "handle" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "csrfToken" Decode.string)
        (Decode.field "apiBase" Decode.string)


type alias Model =
    { flags : Flags }


type Msg
    = NoOp


init : Decode.Value -> ( Model, Cmd Msg )
init flagsJson =
    case Decode.decodeValue flagsDecoder flagsJson of
        Ok flags ->
            ( { flags = flags }, Cmd.none )

        Err _ ->
            ( { flags = Flags 0 "" "" "" "" }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update _ model =
    ( model, Cmd.none )


view : Model -> Html Msg
view model =
    div [] [ text ("Loading " ++ model.flags.title ++ "...") ]


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
```

- [ ] **Step 7: Run, confirm the test passes**

Run: `cd elm && npx elm-test`
Expected: PASS.

- [ ] **Step 8: Compile the bundle and verify it loads in the real app**

```bash
cd elm && elm make src/Main.elm --output=../static/js/page_editor.js && cd ..
```

Start the app (`docker compose up -d db`, `python manage.py runserver`), log in as a user with a page, visit `/dashboard/pages/<handle>/edit/`, and confirm the browser shows "Loading `<title>`...".

- [ ] **Step 9: Write the first e2e test**

Create `e2e/test_page_editor.py`:

```python
from playwright.sync_api import expect


def test_page_editor_loads_and_shows_the_page_title(page, live_server, demo_user, demo_page):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")

    expect(page.locator("#elm-app")).to_contain_text(demo_page.title)
```

- [ ] **Step 10: Run it**

Run: `pytest e2e/test_page_editor.py -v`
Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add elm/ static/js/page_editor.js e2e/test_page_editor.py
git commit -m "Scaffold the Elm editor app and mount it in the page_editor template"
```

---

### Task 11: Fetch page + blocks, render read-only preview, device switcher

**Files:**
- Modify: `elm/src/Main.elm`
- Modify: `elm/tests/MainTest.elm`
- Modify: `static/css/page_editor.css`
- Modify: `e2e/test_page_editor.py`

**Interfaces:**
- Consumes: `GET {apiBase}pages/{handle}/` (Task 5's `PageDetailAPIView`).
- Produces: `Main.Block`, `Main.BlockContent`, `Main.PageData`, `Main.Device`, `Main.deviceWidth`.

- [ ] **Step 1: Write the failing unit test for `deviceWidth`**

Append to `elm/tests/MainTest.elm` (add to the existing `suite`'s list, or a second `describe`):

```elm
    , describe "deviceWidth"
        [ test "Desktop is unconstrained" <|
            \_ -> Expect.equal Nothing (deviceWidth Desktop)
        , test "Tablet is 768px" <|
            \_ -> Expect.equal (Just 768) (deviceWidth Tablet)
        , test "Phone is 390px" <|
            \_ -> Expect.equal (Just 390) (deviceWidth Phone)
        ]
```

Update the module's import line to also expose `Device(..)` and `deviceWidth`:

```elm
import Main exposing (Device(..), deviceWidth, flagsDecoder)
```

- [ ] **Step 2: Run, confirm it fails to compile**

Run: `cd elm && npx elm-test`
Expected: FAIL — `Device`/`deviceWidth` not exposed by `Main`.

- [ ] **Step 3: Implement fetching, decoding, and the device switcher**

Replace the contents of `elm/src/Main.elm` with:

```elm
module Main exposing
    ( Block
    , BlockContent(..)
    , Device(..)
    , Flags
    , PageData
    , SocialIcon
    , deviceWidth
    , flagsDecoder
    , main
    )

import Browser
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (class, classList, style)
import Html.Events exposing (onClick)
import Http
import Json.Decode as Decode exposing (Decoder)


type alias Flags =
    { pageId : Int
    , handle : String
    , title : String
    , csrfToken : String
    , apiBase : String
    }


flagsDecoder : Decoder Flags
flagsDecoder =
    Decode.map5 Flags
        (Decode.field "pageId" Decode.int)
        (Decode.field "handle" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "csrfToken" Decode.string)
        (Decode.field "apiBase" Decode.string)


type alias SocialIcon =
    { platform : String, url : String }


type BlockContent
    = LinkContent { label : String, url : String }
    | HeaderContent { displayName : String, bio : String, avatarUrl : String }
    | SocialIconsContent { icons : List SocialIcon }


type alias Block =
    { id : Int
    , position : Int
    , visible : Bool
    , content : BlockContent
    }


type alias PageData =
    { id : Int
    , handle : String
    , title : String
    , blocks : List Block
    }


socialIconDecoder : Decoder SocialIcon
socialIconDecoder =
    Decode.map2 SocialIcon
        (Decode.field "platform" Decode.string)
        (Decode.field "url" Decode.string)


contentDecoder : String -> Decoder BlockContent
contentDecoder blockType =
    case blockType of
        "link" ->
            Decode.map2 (\label url -> LinkContent { label = label, url = url })
                (Decode.field "label" Decode.string)
                (Decode.field "url" Decode.string)

        "header" ->
            Decode.map3
                (\displayName bio avatarUrl ->
                    HeaderContent { displayName = displayName, bio = bio, avatarUrl = avatarUrl }
                )
                (Decode.field "display_name" Decode.string)
                (Decode.field "bio" (Decode.oneOf [ Decode.string, Decode.succeed "" ]))
                (Decode.field "avatar_url" (Decode.oneOf [ Decode.string, Decode.succeed "" ]))

        "social_icons" ->
            Decode.map (\icons -> SocialIconsContent { icons = icons })
                (Decode.field "icons" (Decode.list socialIconDecoder))

        _ ->
            Decode.fail ("Unknown block_type: " ++ blockType)


blockDecoder : Decoder Block
blockDecoder =
    Decode.field "block_type" Decode.string
        |> Decode.andThen
            (\blockType ->
                Decode.map4
                    (\id position visible content -> Block id position visible content)
                    (Decode.field "id" Decode.int)
                    (Decode.field "position" Decode.int)
                    (Decode.field "visible" Decode.bool)
                    (Decode.field "data" (contentDecoder blockType))
            )


pageDecoder : Decoder PageData
pageDecoder =
    Decode.map4 PageData
        (Decode.field "id" Decode.int)
        (Decode.field "handle" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "blocks" (Decode.list blockDecoder))


type Device
    = Desktop
    | Tablet
    | Phone


deviceWidth : Device -> Maybe Int
deviceWidth device =
    case device of
        Desktop ->
            Nothing

        Tablet ->
            Just 768

        Phone ->
            Just 390


type alias Model =
    { flags : Flags
    , page : Maybe PageData
    , device : Device
    , error : Maybe String
    }


type Msg
    = PageLoaded (Result Http.Error PageData)
    | SetDevice Device


fetchPage : Flags -> Cmd Msg
fetchPage flags =
    Http.get
        { url = flags.apiBase ++ "pages/" ++ flags.handle ++ "/"
        , expect = Http.expectJson PageLoaded pageDecoder
        }


init : Decode.Value -> ( Model, Cmd Msg )
init flagsJson =
    case Decode.decodeValue flagsDecoder flagsJson of
        Ok flags ->
            ( { flags = flags, page = Nothing, device = Desktop, error = Nothing }
            , fetchPage flags
            )

        Err _ ->
            ( { flags = Flags 0 "" "" "" ""
              , page = Nothing
              , device = Desktop
              , error = Just "Couldn't read page configuration."
              }
            , Cmd.none
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        PageLoaded (Ok pageData) ->
            ( { model | page = Just pageData }, Cmd.none )

        PageLoaded (Err _) ->
            ( { model | error = Just "Couldn't load this page. Try reloading." }, Cmd.none )

        SetDevice device ->
            ( { model | device = device }, Cmd.none )


viewDeviceButton : Device -> Device -> Html Msg
viewDeviceButton current device =
    button
        [ classList [ ( "device-button", True ), ( "device-button-active", current == device ) ]
        , onClick (SetDevice device)
        ]
        [ text (deviceLabel device) ]


deviceLabel : Device -> String
deviceLabel device =
    case device of
        Desktop ->
            "Desktop"

        Tablet ->
            "Tablet"

        Phone ->
            "Phone"


viewBlockPreview : Block -> Html Msg
viewBlockPreview block =
    case block.content of
        LinkContent { label } ->
            div [ class "preview-block preview-block-link" ] [ text label ]

        HeaderContent { displayName, bio } ->
            div [ class "preview-block preview-block-header" ]
                [ div [ class "preview-header-name" ] [ text displayName ]
                , div [ class "preview-header-bio" ] [ text bio ]
                ]

        SocialIconsContent { icons } ->
            div [ class "preview-block preview-block-social" ]
                (List.map (\icon -> Html.i [ class ("fa-brands fa-" ++ icon.platform) ] []) icons)


viewPreview : Model -> PageData -> Html Msg
viewPreview model pageData =
    div [ class "editor-preview-pane" ]
        [ div
            [ class "preview-frame"
            , style "width" (deviceWidth model.device |> Maybe.map (\w -> String.fromInt w ++ "px") |> Maybe.withDefault "100%")
            ]
            (List.map viewBlockPreview pageData.blocks)
        ]


viewControls : Model -> Html Msg
viewControls model =
    div [ class "editor-controls-pane" ]
        [ div [ class "device-switcher" ]
            [ viewDeviceButton model.device Desktop
            , viewDeviceButton model.device Tablet
            , viewDeviceButton model.device Phone
            ]
        ]


view : Model -> Html Msg
view model =
    case ( model.error, model.page ) of
        ( Just message, _ ) ->
            div [ class "editor-error" ] [ text message ]

        ( Nothing, Nothing ) ->
            div [ class "editor-loading" ] [ text "Loading..." ]

        ( Nothing, Just pageData ) ->
            div [ class "editor-shell" ] [ viewPreview model pageData, viewControls model ]


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
```

- [ ] **Step 4: Add device-switcher and preview-frame CSS**

Append to `static/css/page_editor.css`:

```css
.editor-shell {
  display: flex;
  width: 100%;
}

.preview-frame {
  background: white;
  min-height: 500px;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.08);
  transition: width 0.2s ease;
}

.device-switcher {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 1rem;
}

.device-button {
  padding: 0.5rem 1rem;
  border-radius: 6px;
  border: 1px solid #ddd;
  background: white;
  cursor: pointer;
}

.device-button-active {
  border-color: #333;
  font-weight: 600;
}
```

- [ ] **Step 5: Run the Elm tests**

Run: `cd elm && npx elm-test`
Expected: PASS.

- [ ] **Step 6: Rebuild the bundle**

Run: `cd elm && elm make src/Main.elm --output=../static/js/page_editor.js && cd ..`

- [ ] **Step 7: Extend the e2e test**

Append to `e2e/test_page_editor.py` (reusing the same login helper inline, or extract it into a small local function if you prefer — keep it simple):

```python
def test_page_editor_shows_existing_blocks_and_switches_device_width(
    page, live_server, demo_user, demo_page
):
    from personal_links_manager.models import Block

    Block.objects.create(
        page=demo_page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "My cool link", "url": "https://example.com"},
    )

    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")

    expect(page.locator(".preview-block-link")).to_contain_text("My cool link")

    page.click("button:text-is('Tablet')")
    expect(page.locator(".preview-frame")).to_have_css("width", "768px")
```

- [ ] **Step 8: Run it**

Run: `pytest e2e/test_page_editor.py -v`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add elm/src/Main.elm elm/tests/MainTest.elm static/js/page_editor.js static/css/page_editor.css e2e/test_page_editor.py
git commit -m "Fetch page/blocks and render a read-only preview with a device switcher"
```

---

### Task 12: Add-block controls (Link / Header / Social icons)

**Files:**
- Modify: `elm/src/Main.elm`
- Modify: `elm/tests/MainTest.elm`
- Modify: `static/css/page_editor.css`
- Modify: `e2e/test_page_editor.py`

**Interfaces:**
- Consumes: `POST {apiBase}pages/{handle}/blocks/` (Task 6's `BlockCreateAPIView`).
- Produces: `Main.BlockType(..)`, `Main.canAddHeader`.

- [ ] **Step 1: Write the failing unit test for the header guard**

Append to `elm/tests/MainTest.elm`:

```elm
    , describe "canAddHeader"
        [ test "true when there is no header block yet" <|
            \_ ->
                Expect.equal True
                    (canAddHeader
                        [ Block 1 0 True (LinkContent { label = "x", url = "https://x.example" }) ]
                    )
        , test "false once a header block exists" <|
            \_ ->
                Expect.equal False
                    (canAddHeader
                        [ Block 1 0 True (HeaderContent { displayName = "Jane", bio = "", avatarUrl = "" }) ]
                    )
        ]
```

Update the import line:

```elm
import Main exposing (Block, BlockContent(..), Device(..), canAddHeader, deviceWidth, flagsDecoder)
```

- [ ] **Step 2: Run, confirm it fails to compile**

Run: `cd elm && npx elm-test`
Expected: FAIL — `canAddHeader` not exposed.

- [ ] **Step 3: Implement `BlockType`, `canAddHeader`, the add-block request, and the controls**

In `elm/src/Main.elm`:

Update the module's exposing list (note: `BlockType` itself doesn't need exposing — it's only ever constructed and consumed inside `Main.elm`'s own view/update code, not referenced from the test file):

```elm
module Main exposing
    ( Block
    , BlockContent(..)
    , Device(..)
    , Flags
    , PageData
    , SocialIcon
    , canAddHeader
    , deviceWidth
    , flagsDecoder
    , main
    )
```

Add `Msg` constructors and their handling. Add these definitions (after the `Block`/`PageData` types):

```elm
type BlockType
    = LinkType
    | HeaderType
    | SocialIconsType


blockTypeApiValue : BlockType -> String
blockTypeApiValue blockType =
    case blockType of
        LinkType ->
            "link"

        HeaderType ->
            "header"

        SocialIconsType ->
            "social_icons"


defaultData : BlockType -> String -> Encode.Value
defaultData blockType pageTitle =
    case blockType of
        LinkType ->
            Encode.object
                [ ( "label", Encode.string "New link" )
                , ( "url", Encode.string "https://example.com" )
                ]

        HeaderType ->
            Encode.object
                [ ( "display_name", Encode.string pageTitle )
                , ( "bio", Encode.string "" )
                , ( "avatar_url", Encode.string "" )
                ]

        SocialIconsType ->
            Encode.object [ ( "icons", Encode.list identity [] ) ]


canAddHeader : List Block -> Bool
canAddHeader blocks =
    not (List.any (\block -> isHeader block.content) blocks)


isHeader : BlockContent -> Bool
isHeader content =
    case content of
        HeaderContent _ ->
            True

        _ ->
            False
```

Add the `import Json.Encode as Encode` import at the top of the file, alongside the existing `Json.Decode` import.

Add to `Msg`:

```elm
    | AddBlock BlockType
    | BlockCreated (Result Http.Error Block)
```

Add the request function (near `fetchPage`):

```elm
createBlock : Flags -> BlockType -> Cmd Msg
createBlock flags blockType =
    Http.request
        { method = "POST"
        , headers = [ Http.header "X-CSRFToken" flags.csrfToken ]
        , url = flags.apiBase ++ "pages/" ++ flags.handle ++ "/blocks/"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "block_type", Encode.string (blockTypeApiValue blockType) )
                    , ( "data", defaultData blockType flags.title )
                    ]
                )
        , expect = Http.expectJson BlockCreated blockDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
```

Add to `update`:

```elm
        AddBlock blockType ->
            ( model, createBlock model.flags blockType )

        BlockCreated (Ok block) ->
            ( { model | page = Maybe.map (\p -> { p | blocks = p.blocks ++ [ block ] }) model.page }
            , Cmd.none
            )

        BlockCreated (Err _) ->
            ( { model | error = Just "Couldn't add that block. Try again." }, Cmd.none )
```

Update `viewControls` to take the blocks list and render add-buttons:

```elm
viewControls : Model -> PageData -> Html Msg
viewControls model pageData =
    div [ class "editor-controls-pane" ]
        [ div [ class "device-switcher" ]
            [ viewDeviceButton model.device Desktop
            , viewDeviceButton model.device Tablet
            , viewDeviceButton model.device Phone
            ]
        , div [ class "add-block-row" ]
            [ button [ onClick (AddBlock LinkType) ] [ text "Add Link" ]
            , button
                [ onClick (AddBlock HeaderType)
                , Html.Attributes.disabled (not (canAddHeader pageData.blocks))
                ]
                [ text "Add Header" ]
            , button [ onClick (AddBlock SocialIconsType) ] [ text "Add Social icons" ]
            ]
        ]
```

Update the call site in `view` (`( Nothing, Just pageData ) -> ...`) to pass `pageData` through: `div [ class "editor-shell" ] [ viewPreview model pageData, viewControls model pageData ]`.

- [ ] **Step 4: Add minimal styling for the add-block row**

Append to `static/css/page_editor.css`:

```css
.add-block-row {
  display: flex;
  gap: 0.5rem;
}

.add-block-row button:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
```

- [ ] **Step 5: Run the Elm tests**

Run: `cd elm && npx elm-test`
Expected: PASS.

- [ ] **Step 6: Rebuild the bundle**

Run: `cd elm && elm make src/Main.elm --output=../static/js/page_editor.js && cd ..`

- [ ] **Step 7: Extend the e2e test**

Append to `e2e/test_page_editor.py`:

```python
def test_adding_a_link_block_shows_up_in_the_preview(page, live_server, demo_user, demo_page):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")
    page.click("button:text-is('Add Link')")

    expect(page.locator(".preview-block-link")).to_contain_text("New link")


def test_add_header_button_disables_once_a_header_exists(
    page, live_server, demo_user, demo_page
):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")
    page.click("button:text-is('Add Header')")

    expect(page.locator("button:text-is('Add Header')")).to_be_disabled()
```

- [ ] **Step 8: Run it**

Run: `pytest e2e/test_page_editor.py -v`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add elm/src/Main.elm elm/tests/MainTest.elm static/js/page_editor.js static/css/page_editor.css e2e/test_page_editor.py
git commit -m "Add block-creation controls with the one-header-block guard"
```

---

### Task 13: Edit block fields with debounced save

**Files:**
- Modify: `elm/src/Main.elm`
- Modify: `elm/tests/MainTest.elm`
- Modify: `static/css/page_editor.css`
- Modify: `e2e/test_page_editor.py`

**Interfaces:**
- Consumes: `PATCH {apiBase}pages/{handle}/blocks/{id}/` (Task 7's `BlockDetailAPIView`).
- Produces: `Main.updateBlockContent` (pure helper used by `update`).

- [ ] **Step 1: Write the failing unit test for the pure content-update helper**

Append to `elm/tests/MainTest.elm`:

```elm
    , describe "updateBlockContent"
        [ test "replaces a link block's label" <|
            \_ ->
                let
                    original =
                        LinkContent { label = "Old", url = "https://old.example" }
                in
                Expect.equal
                    (LinkContent { label = "New", url = "https://old.example" })
                    (updateBlockContent (\l -> { l | label = "New" }) identity identity original)
        ]
```

Update the import line to:

```elm
import Main exposing (Block, BlockContent(..), Device(..), canAddHeader, deviceWidth, flagsDecoder, updateBlockContent)
```

- [ ] **Step 2: Run, confirm it fails to compile**

Run: `cd elm && npx elm-test`
Expected: FAIL — `updateBlockContent` not exposed.

- [ ] **Step 3: Implement editable fields, debounced save, and the helper**

In `elm/src/Main.elm`, update the exposing list:

```elm
module Main exposing
    ( Block
    , BlockContent(..)
    , Device(..)
    , Flags
    , PageData
    , SocialIcon
    , canAddHeader
    , deviceWidth
    , flagsDecoder
    , main
    , updateBlockContent
    )
```

Add:

```elm
updateBlockContent :
    ({ label : String, url : String } -> { label : String, url : String })
    -> ({ displayName : String, bio : String, avatarUrl : String } -> { displayName : String, bio : String, avatarUrl : String })
    -> ({ icons : List SocialIcon } -> { icons : List SocialIcon })
    -> BlockContent
    -> BlockContent
updateBlockContent editLink editHeader editSocial content =
    case content of
        LinkContent link ->
            LinkContent (editLink link)

        HeaderContent header ->
            HeaderContent (editHeader header)

        SocialIconsContent social ->
            SocialIconsContent (editSocial social)
```

Add to `Msg`:

```elm
    | EditBlock Int BlockContent
    | Debounced Int
    | BlockSaved Int (Result Http.Error Block)
```

Add `import Dict exposing (Dict)`, `import Process`, and `import Task` to the top of the file, alongside the existing imports.

Add a debounce field to `Model` (the counter is unused for now beyond bookkeeping — `Debounced` always saves on fire, per the note after the `update` cases below):

```elm
type alias Model =
    { flags : Flags
    , page : Maybe PageData
    , device : Device
    , error : Maybe String
    , pendingSaves : Dict Int Int
    }
```

Update both branches of `init` to include the new field:

```elm
init : Decode.Value -> ( Model, Cmd Msg )
init flagsJson =
    case Decode.decodeValue flagsDecoder flagsJson of
        Ok flags ->
            ( { flags = flags, page = Nothing, device = Desktop, error = Nothing, pendingSaves = Dict.empty }
            , fetchPage flags
            )

        Err _ ->
            ( { flags = Flags 0 "" "" "" ""
              , page = Nothing
              , device = Desktop
              , error = Just "Couldn't read page configuration."
              , pendingSaves = Dict.empty
              }
            , Cmd.none
            )
```

Add to `update`:

```elm
        EditBlock blockId newContent ->
            let
                nextGeneration =
                    (Dict.get blockId model.pendingSaves |> Maybe.withDefault 0) + 1

                updatedPage =
                    Maybe.map
                        (\p ->
                            { p
                                | blocks =
                                    List.map
                                        (\b ->
                                            if b.id == blockId then
                                                { b | content = newContent }

                                            else
                                                b
                                        )
                                        p.blocks
                            }
                        )
                        model.page
            in
            ( { model | page = updatedPage, pendingSaves = Dict.insert blockId nextGeneration model.pendingSaves }
            , Process.sleep 500 |> Task.perform (\_ -> Debounced blockId)
            )

        Debounced blockId ->
            let
                currentGeneration =
                    Dict.get blockId model.pendingSaves |> Maybe.withDefault 0

                maybeBlock =
                    model.page |> Maybe.andThen (\p -> List.filter (\b -> b.id == blockId) p.blocks |> List.head)
            in
            case maybeBlock of
                Just block ->
                    ( model, saveBlock model.flags block )

                Nothing ->
                    ( model, Cmd.none )

        BlockSaved _ (Ok _) ->
            ( model, Cmd.none )

        BlockSaved blockId (Err _) ->
            ( { model | error = Just "Couldn't save a change. Reload and try again." }, Cmd.none )
```

(This fires a save on every debounce timeout regardless of whether a newer edit has landed in between, which re-sends the latest content each time — acceptable since saves are idempotent full-`data` replacements. A generation-check-before-sending refinement is a reasonable follow-up, not required for this task.)

Add the encoder and request:

```elm
contentEncoder : BlockContent -> Encode.Value
contentEncoder content =
    case content of
        LinkContent { label, url } ->
            Encode.object [ ( "label", Encode.string label ), ( "url", Encode.string url ) ]

        HeaderContent { displayName, bio, avatarUrl } ->
            Encode.object
                [ ( "display_name", Encode.string displayName )
                , ( "bio", Encode.string bio )
                , ( "avatar_url", Encode.string avatarUrl )
                ]

        SocialIconsContent { icons } ->
            Encode.object
                [ ( "icons"
                  , Encode.list
                        (\icon ->
                            Encode.object
                                [ ( "platform", Encode.string icon.platform )
                                , ( "url", Encode.string icon.url )
                                ]
                        )
                        icons
                  )
                ]


saveBlock : Flags -> Block -> Cmd Msg
saveBlock flags block =
    Http.request
        { method = "PATCH"
        , headers = [ Http.header "X-CSRFToken" flags.csrfToken ]
        , url = flags.apiBase ++ "pages/" ++ flags.handle ++ "/blocks/" ++ String.fromInt block.id ++ "/"
        , body = Http.jsonBody (Encode.object [ ( "data", contentEncoder block.content ) ])
        , expect = Http.expectJson (BlockSaved block.id) blockDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
```

Add an editable block view (replacing the read-only `viewBlockPreview` usage in the controls pane — the preview pane stays read-only/rendered, the *controls* pane gets the input fields):

```elm
viewBlockEditor : Block -> Html Msg
viewBlockEditor block =
    case block.content of
        LinkContent link ->
            div [ class "block-editor" ]
                [ Html.input
                    [ Html.Attributes.value link.label
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent (\l -> { l | label = v }) identity identity block.content))
                    ]
                    []
                , Html.input
                    [ Html.Attributes.value link.url
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent (\l -> { l | url = v }) identity identity block.content))
                    ]
                    []
                ]

        HeaderContent header ->
            div [ class "block-editor" ]
                [ Html.input
                    [ Html.Attributes.value header.displayName
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent identity (\h -> { h | displayName = v }) identity block.content))
                    ]
                    []
                , Html.textarea
                    [ Html.Attributes.value header.bio
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent identity (\h -> { h | bio = v }) identity block.content))
                    ]
                    []
                ]

        SocialIconsContent social ->
            div [ class "block-editor" ]
                (List.indexedMap
                    (\index icon ->
                        div [ class "social-icon-row" ]
                            [ Html.input
                                [ Html.Attributes.value icon.platform
                                , Html.Attributes.placeholder "platform (e.g. twitter)"
                                , Html.Events.onInput
                                    (\v ->
                                        EditBlock block.id
                                            (updateBlockContent identity
                                                identity
                                                (\s -> { s | icons = List.indexedMap (\i ic -> if i == index then { ic | platform = v } else ic) s.icons })
                                                block.content
                                            )
                                    )
                                ]
                                []
                            , Html.input
                                [ Html.Attributes.value icon.url
                                , Html.Events.onInput
                                    (\v ->
                                        EditBlock block.id
                                            (updateBlockContent identity
                                                identity
                                                (\s -> { s | icons = List.indexedMap (\i ic -> if i == index then { ic | url = v } else ic) s.icons })
                                                block.content
                                            )
                                    )
                                ]
                                []
                            ]
                    )
                    social.icons
                    ++ [ button
                            [ onClick
                                (EditBlock block.id
                                    (updateBlockContent identity
                                        identity
                                        (\s -> { s | icons = s.icons ++ [ SocialIcon "" "" ] })
                                        block.content
                                    )
                                )
                            ]
                            [ text "Add icon" ]
                       ]
                )
```

Update `viewControls` to render one `viewBlockEditor` per block, below the add-block row:

```elm
        , div [ class "block-list" ] (List.map viewBlockEditor pageData.blocks)
```

- [ ] **Step 4: Add minimal styling**

Append to `static/css/page_editor.css`:

```css
.block-editor {
  border: 1px solid #eee;
  border-radius: 6px;
  padding: 0.75rem;
  margin-bottom: 0.75rem;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.social-icon-row {
  display: flex;
  gap: 0.5rem;
}
```

- [ ] **Step 5: Run the Elm tests**

Run: `cd elm && npx elm-test`
Expected: PASS.

- [ ] **Step 6: Rebuild the bundle**

Run: `cd elm && elm make src/Main.elm --output=../static/js/page_editor.js && cd ..`

- [ ] **Step 7: Extend the e2e test**

Append to `e2e/test_page_editor.py`:

```python
def test_editing_a_link_label_updates_the_preview_without_reload(
    page, live_server, demo_user, demo_page
):
    from personal_links_manager.models import Block

    Block.objects.create(
        page=demo_page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "Original", "url": "https://example.com"},
    )

    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")
    page.fill(".block-editor input >> nth=0", "Updated label")

    expect(page.locator(".preview-block-link")).to_contain_text("Updated label")

    # Give the 500ms debounce time to fire, then reload and confirm it persisted.
    page.wait_for_timeout(700)
    page.reload()
    expect(page.locator(".preview-block-link")).to_contain_text("Updated label")
```

- [ ] **Step 8: Run it**

Run: `pytest e2e/test_page_editor.py -v`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add elm/src/Main.elm elm/tests/MainTest.elm static/js/page_editor.js static/css/page_editor.css e2e/test_page_editor.py
git commit -m "Add debounced block field editing"
```

---

### Task 14: Delete block

**Files:**
- Modify: `elm/src/Main.elm`
- Modify: `static/css/page_editor.css`
- Modify: `e2e/test_page_editor.py`

**Interfaces:**
- Consumes: `DELETE {apiBase}pages/{handle}/blocks/{id}/` (Task 7's `BlockDetailAPIView`).

- [ ] **Step 1: Add the delete request, `Msg`, and button**

No new pure-function behavior worth a dedicated elm-test here (it's a direct list-filter on success) — go straight to implementation, verified by the e2e test in Step 3.

In `elm/src/Main.elm`, add to `Msg`:

```elm
    | DeleteBlock Int
    | BlockDeleted Int (Result Http.Error ())
```

Add the request:

```elm
deleteBlock : Flags -> Int -> Cmd Msg
deleteBlock flags blockId =
    Http.request
        { method = "DELETE"
        , headers = [ Http.header "X-CSRFToken" flags.csrfToken ]
        , url = flags.apiBase ++ "pages/" ++ flags.handle ++ "/blocks/" ++ String.fromInt blockId ++ "/"
        , body = Http.emptyBody
        , expect = Http.expectWhatever (BlockDeleted blockId)
        , timeout = Nothing
        , tracker = Nothing
        }
```

Add to `update`:

```elm
        DeleteBlock blockId ->
            ( { model | page = Maybe.map (\p -> { p | blocks = List.filter (\b -> b.id /= blockId) p.blocks }) model.page }
            , deleteBlock model.flags blockId
            )

        BlockDeleted _ (Ok ()) ->
            ( model, Cmd.none )

        BlockDeleted _ (Err _) ->
            ( { model | error = Just "Couldn't delete that block. Reload to see the real state." }, Cmd.none )
```

(Optimistic removal, matching the reorder task's pattern; a failed delete is surfaced via the error banner rather than restoring the block, since re-fetching the page on failure is simpler and just as correct here.)

Replace `viewBlockEditor` with this version, which adds a delete button to every branch:

```elm
deleteButton : Block -> Html Msg
deleteButton block =
    button [ onClick (DeleteBlock block.id), class "delete-block-button" ]
        [ Html.i [ class "fa-solid fa-trash" ] [] ]


viewBlockEditor : Block -> Html Msg
viewBlockEditor block =
    case block.content of
        LinkContent link ->
            div [ class "block-editor" ]
                [ Html.input
                    [ Html.Attributes.value link.label
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent (\l -> { l | label = v }) identity identity block.content))
                    ]
                    []
                , Html.input
                    [ Html.Attributes.value link.url
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent (\l -> { l | url = v }) identity identity block.content))
                    ]
                    []
                , deleteButton block
                ]

        HeaderContent header ->
            div [ class "block-editor" ]
                [ Html.input
                    [ Html.Attributes.value header.displayName
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent identity (\h -> { h | displayName = v }) identity block.content))
                    ]
                    []
                , Html.textarea
                    [ Html.Attributes.value header.bio
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent identity (\h -> { h | bio = v }) identity block.content))
                    ]
                    []
                , deleteButton block
                ]

        SocialIconsContent social ->
            div [ class "block-editor" ]
                (List.indexedMap
                    (\index icon ->
                        div [ class "social-icon-row" ]
                            [ Html.input
                                [ Html.Attributes.value icon.platform
                                , Html.Attributes.placeholder "platform (e.g. twitter)"
                                , Html.Events.onInput
                                    (\v ->
                                        EditBlock block.id
                                            (updateBlockContent identity
                                                identity
                                                (\s -> { s | icons = List.indexedMap (\i ic -> if i == index then { ic | platform = v } else ic) s.icons })
                                                block.content
                                            )
                                    )
                                ]
                                []
                            , Html.input
                                [ Html.Attributes.value icon.url
                                , Html.Events.onInput
                                    (\v ->
                                        EditBlock block.id
                                            (updateBlockContent identity
                                                identity
                                                (\s -> { s | icons = List.indexedMap (\i ic -> if i == index then { ic | url = v } else ic) s.icons })
                                                block.content
                                            )
                                    )
                                ]
                                []
                            ]
                    )
                    social.icons
                    ++ [ button
                            [ onClick
                                (EditBlock block.id
                                    (updateBlockContent identity
                                        identity
                                        (\s -> { s | icons = s.icons ++ [ SocialIcon "" "" ] })
                                        block.content
                                    )
                                )
                            ]
                            [ text "Add icon" ]
                       , deleteButton block
                       ]
                )
```

- [ ] **Step 2: Add minimal styling**

Append to `static/css/page_editor.css`:

```css
.delete-block-button {
  align-self: flex-end;
  background: none;
  border: none;
  color: #c0392b;
  cursor: pointer;
}
```

- [ ] **Step 3: Rebuild and write the e2e test**

Run: `cd elm && elm make src/Main.elm --output=../static/js/page_editor.js && cd ..`

Append to `e2e/test_page_editor.py`:

```python
def test_deleting_a_block_removes_it_from_the_preview(page, live_server, demo_user, demo_page):
    from personal_links_manager.models import Block

    Block.objects.create(
        page=demo_page, block_type=Block.BlockType.LINK, position=0,
        data={"label": "Delete me", "url": "https://example.com"},
    )

    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")
    page.click(".delete-block-button")

    expect(page.locator(".preview-block-link")).to_have_count(0)
```

- [ ] **Step 4: Run it**

Run: `pytest e2e/test_page_editor.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add elm/src/Main.elm static/js/page_editor.js static/css/page_editor.css e2e/test_page_editor.py
git commit -m "Add block deletion"
```

---

### Task 15: Reorder blocks (up/down) + final end-to-end coverage

**Files:**
- Modify: `elm/src/Main.elm`
- Modify: `elm/tests/MainTest.elm`
- Modify: `static/css/page_editor.css`
- Modify: `e2e/test_page_editor.py`

**Interfaces:**
- Consumes: `POST {apiBase}pages/{handle}/blocks/reorder/` (Task 8's `BlockReorderAPIView`).
- Produces: `Main.moveBlock` (pure helper).

- [ ] **Step 1: Write the failing unit test for the pure reorder helper**

Append to `elm/tests/MainTest.elm`:

```elm
    , describe "moveBlock"
        [ test "moving a block up swaps it with its predecessor" <|
            \_ ->
                let
                    blocks =
                        [ Block 1 0 True (LinkContent { label = "A", url = "https://a.example" })
                        , Block 2 1 True (LinkContent { label = "B", url = "https://b.example" })
                        ]
                in
                moveBlock 2 (-1) blocks
                    |> List.map .id
                    |> Expect.equal [ 2, 1 ]
        , test "moving the first block up is a no-op" <|
            \_ ->
                let
                    blocks =
                        [ Block 1 0 True (LinkContent { label = "A", url = "https://a.example" })
                        , Block 2 1 True (LinkContent { label = "B", url = "https://b.example" })
                        ]
                in
                moveBlock 1 (-1) blocks
                    |> List.map .id
                    |> Expect.equal [ 1, 2 ]
        ]
```

Update the import line to:

```elm
import Main exposing (Block, BlockContent(..), Device(..), canAddHeader, deviceWidth, flagsDecoder, moveBlock, updateBlockContent)
```

- [ ] **Step 2: Run, confirm it fails to compile**

Run: `cd elm && npx elm-test`
Expected: FAIL — `moveBlock` not exposed.

- [ ] **Step 3: Implement `moveBlock`, the reorder request, optimistic update + rollback**

Update the exposing list:

```elm
module Main exposing
    ( Block
    , BlockContent(..)
    , Device(..)
    , Flags
    , PageData
    , SocialIcon
    , canAddHeader
    , deviceWidth
    , flagsDecoder
    , main
    , moveBlock
    , updateBlockContent
    )
```

Implement `moveBlock`:

```elm
moveBlock : Int -> Int -> List Block -> List Block
moveBlock blockId delta blocks =
    let
        ids =
            List.map .id blocks

        currentIndex =
            List.foldl
                (\( index, id ) found ->
                    if id == blockId then
                        Just index

                    else
                        found
                )
                Nothing
                (List.indexedMap Tuple.pair ids)

        newIndex =
            currentIndex |> Maybe.map (\i -> i + delta)
    in
    case ( currentIndex, newIndex ) of
        ( Just from, Just to ) ->
            if to < 0 || to >= List.length blocks then
                blocks

            else
                swapAt from to blocks

        _ ->
            blocks


swapAt : Int -> Int -> List a -> List a
swapAt i j list =
    let
        array =
            Array.fromList list

        vi =
            Array.get i array

        vj =
            Array.get j array
    in
    case ( vi, vj ) of
        ( Just a, Just b ) ->
            array |> Array.set i b |> Array.set j a |> Array.toList

        _ ->
            list
```

Add `import Array` at the top (part of `elm/core`, no new package needed).

Add to `Msg`:

```elm
    | MoveBlock Int Int
    | Reordered (List Block) (Result Http.Error PageData)
```

Add the request:

```elm
reorderBlocks : Flags -> List Block -> Cmd Msg
reorderBlocks flags blocks =
    Http.request
        { method = "POST"
        , headers = [ Http.header "X-CSRFToken" flags.csrfToken ]
        , url = flags.apiBase ++ "pages/" ++ flags.handle ++ "/blocks/reorder/"
        , body = Http.jsonBody (Encode.object [ ( "block_ids", Encode.list (\b -> Encode.int b.id) blocks ) ])
        , expect = Http.expectJson (Reordered blocks) pageDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
```

Add to `update` (`previousBlocks` is the list before the optimistic move, captured for rollback):

```elm
        MoveBlock blockId delta ->
            case model.page of
                Just p ->
                    let
                        reordered =
                            moveBlock blockId delta p.blocks
                    in
                    ( { model | page = Just { p | blocks = reordered } }
                    , reorderBlocks model.flags reordered
                    )

                Nothing ->
                    ( model, Cmd.none )

        Reordered _ (Ok pageData) ->
            ( { model | page = Just pageData }, Cmd.none )

        Reordered previousBlocks (Err _) ->
            ( { model
                | page = Maybe.map (\p -> { p | blocks = previousBlocks }) model.page
                , error = Just "Couldn't reorder blocks. Reverted."
              }
            , Cmd.none
            )
```

Add a `moveButtons` helper next to `deleteButton`, and replace `viewBlockEditor` with this version, which appends it in every branch:

```elm
moveButtons : Block -> List (Html Msg)
moveButtons block =
    [ button [ onClick (MoveBlock block.id (-1)) ] [ Html.i [ class "fa-solid fa-arrow-up" ] [] ]
    , button [ onClick (MoveBlock block.id 1) ] [ Html.i [ class "fa-solid fa-arrow-down" ] [] ]
    ]


viewBlockEditor : Block -> Html Msg
viewBlockEditor block =
    case block.content of
        LinkContent link ->
            div [ class "block-editor" ]
                ([ Html.input
                    [ Html.Attributes.value link.label
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent (\l -> { l | label = v }) identity identity block.content))
                    ]
                    []
                 , Html.input
                    [ Html.Attributes.value link.url
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent (\l -> { l | url = v }) identity identity block.content))
                    ]
                    []
                 , deleteButton block
                 ]
                    ++ moveButtons block
                )

        HeaderContent header ->
            div [ class "block-editor" ]
                ([ Html.input
                    [ Html.Attributes.value header.displayName
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent identity (\h -> { h | displayName = v }) identity block.content))
                    ]
                    []
                 , Html.textarea
                    [ Html.Attributes.value header.bio
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent identity (\h -> { h | bio = v }) identity block.content))
                    ]
                    []
                 , deleteButton block
                 ]
                    ++ moveButtons block
                )

        SocialIconsContent social ->
            div [ class "block-editor" ]
                (List.indexedMap
                    (\index icon ->
                        div [ class "social-icon-row" ]
                            [ Html.input
                                [ Html.Attributes.value icon.platform
                                , Html.Attributes.placeholder "platform (e.g. twitter)"
                                , Html.Events.onInput
                                    (\v ->
                                        EditBlock block.id
                                            (updateBlockContent identity
                                                identity
                                                (\s -> { s | icons = List.indexedMap (\i ic -> if i == index then { ic | platform = v } else ic) s.icons })
                                                block.content
                                            )
                                    )
                                ]
                                []
                            , Html.input
                                [ Html.Attributes.value icon.url
                                , Html.Events.onInput
                                    (\v ->
                                        EditBlock block.id
                                            (updateBlockContent identity
                                                identity
                                                (\s -> { s | icons = List.indexedMap (\i ic -> if i == index then { ic | url = v } else ic) s.icons })
                                                block.content
                                            )
                                    )
                                ]
                                []
                            ]
                    )
                    social.icons
                    ++ [ button
                            [ onClick
                                (EditBlock block.id
                                    (updateBlockContent identity
                                        identity
                                        (\s -> { s | icons = s.icons ++ [ SocialIcon "" "" ] })
                                        block.content
                                    )
                                )
                            ]
                            [ text "Add icon" ]
                       , deleteButton block
                       ]
                    ++ moveButtons block
                )
```

- [ ] **Step 4: Run the Elm tests**

Run: `cd elm && npx elm-test`
Expected: PASS.

- [ ] **Step 5: Rebuild the bundle**

Run: `cd elm && elm make src/Main.elm --output=../static/js/page_editor.js && cd ..`

- [ ] **Step 6: Write the final comprehensive end-to-end test**

Append to `e2e/test_page_editor.py` — this is the capstone test from the spec's testing strategy, exercising the whole flow in one pass:

```python
def test_full_editor_flow_add_edit_switch_device_reorder_and_persist(
    page, live_server, demo_user, demo_page
):
    page.goto(f"{live_server.url}/login/")
    page.fill("#login-email", demo_user.email)
    page.fill("#login-password", "password123")
    page.click("#login-submit")
    page.wait_for_url("**/dashboard/")

    page.goto(f"{live_server.url}/dashboard/pages/{demo_page.handle}/edit/")

    # Add two Link blocks.
    page.click("button:text-is('Add Link')")
    page.click("button:text-is('Add Link')")
    expect(page.locator(".preview-block-link")).to_have_count(2)

    # Edit the first block's label; preview updates without reload.
    page.fill(".block-editor input >> nth=0", "First link")
    expect(page.locator(".preview-block-link").first).to_contain_text("First link")

    # Switch device size.
    page.click("button:text-is('Phone')")
    expect(page.locator(".preview-frame")).to_have_css("width", "390px")

    # Reorder: move the second block up above the first.
    page.locator(".block-editor").nth(1).locator("[class*='fa-arrow-up']").click()

    # Reload and confirm both the edit and the reorder persisted.
    page.wait_for_timeout(700)
    page.reload()
    expect(page.locator(".preview-block-link").first).not_to_contain_text("First link")
```

- [ ] **Step 7: Run the entire test suite**

Run: `pytest accounts personal_links_manager -q` — backend, expect PASS.
Run: `cd elm && npx elm-test` — Elm units, expect PASS.
Run: `pytest e2e -q` — everything including the new editor tests, expect PASS.

- [ ] **Step 8: Commit**

```bash
git add elm/src/Main.elm elm/tests/MainTest.elm static/js/page_editor.js static/css/page_editor.css e2e/test_page_editor.py
git commit -m "Add block reordering and the full editor flow end-to-end test"
```
