# Page editor design

## Context

The dashboard currently only lets a user pick a `handle` for a new `LinkPage`
(`personal_links_manager/templates/personal_links_manager/dashboard.html` +
`partials/_create_modal.html`). There is no way to add content to a page yet —
`docs/roadmap.md` lists link management, theming, and the public profile page
itself as still unbuilt.

This spec covers a new **page editor** screen: a split-screen UI (controls on
one side, a live, device-switchable preview on the other — inspired by the
general layout of avaly.me, not its specific styling) where a user builds a
page out of content blocks. It introduces:

- A block-based content model (internal architecture only — not a
  third-party-installable plugin system).
- Django REST Framework as the app's JSON API layer, including migrating the
  two existing plain-`JsonResponse` endpoints.
- An Elm single-page app for just this one screen, matching the project's
  history as a rewrite of a prior Clojure+Elm application (see e.g. the
  `# Matches Main.elm's ...` comments already in `accounts/views.py` and
  `accounts/forms.py`). The rest of the app stays server-rendered Django
  templates; this is not a broader move back to Elm.

## Out of scope

- The actual public profile page (`/:username`) — still unbuilt per the
  roadmap. The preview in this spec is the editor's own rendering, not the
  real public page (see "Known tradeoff" below).
- Embeds (Instagram/Spotify), avatar upload, themes/custom CSS, analytics —
  all later roadmap phases. The block types in this spec are Link,
  Header/Bio, and Social icons only.
- Drag-and-drop reordering — v1 uses up/down move buttons.
- Replacing the app's existing custom SVG icon partials (`templates/icons/`)
  with FontAwesome — FontAwesome is scoped to the new editor screen only.

## Architecture & routing

- New route: `GET /dashboard/pages/<handle>/edit/`, a Django view
  (`personal_links_manager.views.page_editor`) that 404s/403s if `handle`
  isn't owned by `request.user`, then renders
  `personal_links_manager/templates/personal_links_manager/page_editor.html`
  — a template containing only `<div id="elm-app">` plus an Elm `flags` JSON
  script tag with `{ pageId, handle, title, csrfToken, apiBase }`.
- The existing "Create new page" modal and its `create_page` view are
  unchanged, except the success redirect now points at
  `/dashboard/pages/<handle>/edit/` instead of back to the dashboard.
- The Elm app owns everything inside `#elm-app`: block list, live preview,
  device-size switcher. It talks to Django only through the DRF JSON API
  below — no server-rendered partials are swapped into the page after load.
- Elm source lives in a new top-level `elm/` directory (`elm/elm.json`,
  `elm/src/Main.elm`, tests in `elm/tests/`) — separate from the Django apps,
  since Elm has no relationship to Django's app structure. It compiles with
  `elm make elm/src/Main.elm --output=static/js/page_editor.js`, checked into
  `static/js/` like the existing `app.js` and `admin-dashboard.js` — no
  bundler is introduced. Running `elm make` by hand is an accepted manual
  step for now; a Makefile/npm-script wrapper can be added later if it gets
  tedious.

## Data model

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
```

- `data` shape per type, validated by DRF serializers (not DB constraints):
  - `link`: `{"label": str, "url": str}`
  - `header`: `{"display_name": str, "bio": str, "avatar_url": str}`
    (avatar upload is future roadmap work; this just takes a URL string now)
  - `social_icons`: `{"icons": [{"platform": str, "url": str}]}` — `platform`
    maps to a FontAwesome brand icon class at render time.
- A page may have at most one `header` block. Enforced in the serializer/API
  layer, not a DB constraint — simpler than a conditional unique index for a
  rule this specific.
- `position` is a plain integer, re-sequenced (`0..n-1`) on every reorder. No
  gaps/fractional-position scheme — block counts per page are small.
- This is Approach A from the options considered (single model + JSON
  payload) over per-block-type tables or multi-table inheritance: it's the
  most literally pluggable option — a new block type is a new serializer and
  a new Elm view case, no migration — and block counts per page are far too
  small for JSON-column query performance to matter.

## REST API (Django REST Framework)

- Add `djangorestframework` to `requirements.txt`; `rest_framework` to
  `INSTALLED_APPS`. Global `REST_FRAMEWORK` settings:
  `DEFAULT_AUTHENTICATION_CLASSES = [SessionAuthentication]`,
  `DEFAULT_PERMISSION_CLASSES = [IsAuthenticated]` (deny-by-default). This
  matches the app's existing session-based auth — no token auth is
  introduced. `SessionAuthentication` enforces CSRF on unsafe methods, so Elm
  sends the `csrfToken` from its flags as an `X-CSRFToken` header on
  POST/PATCH/DELETE.
- Plain `APIView`s with hand-written `path()` entries, not a DRF router +
  viewset — the block-nested-under-page shape plus the one-off `reorder`
  action don't fit a router cleanly without an extra package.

**New endpoints** (fresh `/api/` prefix — nothing existing to stay
compatible with):

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/pages/<handle>/` | Page + nested ordered blocks |
| POST | `/api/pages/<handle>/blocks/` | Create a block, appended at the end |
| PATCH | `/api/pages/<handle>/blocks/<id>/` | Update a block's `data`/`visible` |
| DELETE | `/api/pages/<handle>/blocks/<id>/` | Delete a block |
| POST | `/api/pages/<handle>/blocks/reorder/` | Body: ordered list of block ids; re-sequences `position` atomically |

All of the above use a custom `IsPageOwner` permission (403 if
`page.owner != request.user`). Per-type `data` validation lives in
`LinkDataSerializer` / `HeaderDataSerializer` / `SocialIconsDataSerializer`,
selected by `block_type` — this is where "pluggable" actually lives in code.

**Migrated existing endpoints** (URLs unchanged — only the view
implementation moves to a DRF `APIView`, to minimize disruption):

- `/dashboard/handle-check/` (handle availability)
- `/admin/dashboard-data/` (admin stats; `IsAdminUser` permission)

## Elm app

- `Browser.element`, not `Browser.application` — it owns `#elm-app`, not
  page routing. Flags: `{ pageId, handle, title, csrfToken, apiBase }`.
- **Model**: `{ page : PageMeta, blocks : List Block, device : Device, saving : Dict Int SaveStatus }`,
  where `Device = Desktop | Tablet | Phone` controls only the CSS width of
  the preview container (unconstrained / 768px / 390px) — block markup is
  identical at every width, since the app's CSS is already mobile-first per
  `docs/roadmap.md`'s design principles.
- **Editing → preview → save**: typing in a block field updates
  `Model.blocks` immediately (`onInput` → `Msg` → `update`), so the preview
  re-renders every keystroke with no network round-trip. The change is
  persisted via a **debounced PATCH** (~500ms of no further input) —
  decouples "the preview feels instant" from "every keypress hits the
  network."
- **Reordering**: ↑/↓ buttons per block send `POST .../blocks/reorder/` with
  the full new id order. `Model.blocks` reorders optimistically; rolls back
  if the request fails.
- **Adding a block**: a per-type "Add" control (Link / Header / Social
  icons). The Header control disables/hides once a header block exists,
  mirroring the server's one-header rule client-side too. `POST
  .../blocks/` → the server's response (with its real id) is appended to
  `Model.blocks`.
- **Errors**: a failed save/delete/reorder shows an inline retry affordance
  on the specific block that failed (not a global toast/banner), and reverts
  optimistic state if the retry isn't taken. Keeps failures localized to the
  block that caused them.
- **FontAwesome**: Free CDN `<link>` added only to
  `page_editor.html`. Elm emits `<i class="fa-...">` nodes via plain
  `Html.Attributes.class` — no Elm FontAwesome package needed for this scope
  (brand icons for social platforms, solid icons for add/delete/move-block
  controls).

## Known tradeoff: preview vs. real public page

The live preview is the Elm app's own rendering of the blocks, not the real
`/:username` public page (which doesn't exist yet). Once that page ships —
presumably as a server-rendered Django view, consistent with the rest of the
app — there will be two independent implementations of "how a block renders"
(Django templates for the public page, Elm view functions for the editor
preview) that must be kept visually in sync by hand. This is accepted for
now; revisit if/when the public page is built, e.g. by extracting shared
block-rendering rules (spacing, typography) into CSS both sides use, even
though the markup generation itself stays duplicated.

## Testing strategy

- **Backend (pytest-django, existing pattern)**: unit tests for the `Block`
  model, each per-type serializer (accepts valid `data`, rejects invalid
  shapes), and each API view — ownership/permission checks (403 for
  non-owners), one-header enforcement, reorder correctness. The two migrated
  endpoints keep their existing response contracts, so their current tests
  mostly just move with the file.
- **Elm (`elm-test`, new tooling for this repo — not installed anywhere
  yet)**: unit tests for `update` — the debounce-then-save transition,
  optimistic reorder + rollback-on-failure, and the one-header-block guard
  in the "Add block" controls.
- **e2e (Playwright, existing pattern)**: one new `e2e/test_page_editor.py`
  driving the real editor screen — add a Link block, edit its label/URL and
  see the preview update without a page reload, switch device size, reorder
  two blocks, reload and confirm persistence. This is the test that proves
  the Django↔DRF↔Elm wiring works end to end, not just each piece in
  isolation.
