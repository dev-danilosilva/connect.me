# Page layout spec, version 1

A link page's content is stored as one JSON document per page, with a top-level `version`. Each page has two:

- `LinkPage.draft_layout`: what the editor works on. New pages get a default draft: a hero showing the page title, plus an empty socials section and an empty links section.
- `LinkPage.published_layout`: what visitors see, copied from the draft by Publish (`published_at` records when). It's null until the page is first published.

The code that defines the spec:

| Where | What |
|---|---|
| `personal_links_manager/layout/v1.py` | The v1 serializers: the authority on what's valid |
| `personal_links_manager/layout/__init__.py` | Version registry, `validate`, `upgrade`, `default_layout` |
| `elm/src/PageEditor/Layout.elm` | Elm types, decoder and encoder |
| `elm/src/PageEditor/Preview.elm` | Renders a layout as the link page |

## The document

```json
{
  "version": 1,
  "sections": [
    { "id": "…", "type": "hero",
      "displayName": "Ada Lovelace", "bio": "…", "imageUrl": "https://…" },
    { "id": "…", "type": "socials",
      "items": [ { "id": "…", "network": "github", "url": "https://github.com/ada" } ] },
    { "id": "…", "type": "links",
      "items": [
        { "id": "…", "type": "link", "label": "Book a call", "url": "https://…",
          "background": { "type": "solid", "color": "#4c1d95" } },
        { "id": "…", "type": "link", "label": "Gallery", "url": "https://…",
          "background": { "type": "image", "url": "https://…" } },
        { "id": "…", "type": "link", "label": "Watch my talk", "url": "https://…",
          "background": { "type": "video", "src": "https://…", "poster": "https://…" } }
      ] }
  ]
}
```

A page is an **ordered list of typed sections**. A links section holds an **ordered list of typed tiles**. The page renders sections in list order, and tiles in list order within their section. Order is always a position in a list, never a stored number.

### Sections

| `type` | Fields |
|---|---|
| `hero` | `displayName` (≤ 80 chars), `bio` (≤ 300), `imageUrl` (http(s) URL, or `""` for the fallback background). At most one per page. |
| `socials` | `items`: up to 20 `{ id, network, url }` |
| `links` | `items`: up to 50 tiles |

`network` is one of `instagram`, `youtube`, `github`, `linkedin`, `x`, `tiktok`, `facebook`, `spotify`, `website`. The renderer maps it to its icon and accessible label, so stored data never holds CSS class names.

### Tiles

| `type` | Fields |
|---|---|
| `link` | `label` (≤ 80), `url`, `background` |

A link tile's `background` is one of:

| `type` | Fields |
|---|---|
| `solid` | `color`: `#rrggbb` |
| `image` | `url` |
| `video` | `src`, `poster` |

### Rules

- **All keys are required. Unknown keys are rejected at every level.** A stored v1 document is exactly v1.
- **Unknown section, tile and background types are rejected.**
- **Ids:** every section and every item has an `id`, a UUID string unique within the document. Editing, reordering and moving items key on it, and so will analytics.
- **URLs are http(s) only.** They become links and media sources on a public page, so `javascript:` and other schemes are rejected.
- **Colors are `#rrggbb` only.** They're rendered into an inline style.
- **At most 20 sections.**

## API

All endpoints are owner-only (another user's page returns 404) and use session auth with CSRF.

| Method and path | Does |
|---|---|
| `GET /api/pages/<handle>/draft/` | Returns the draft document |
| `PUT /api/pages/<handle>/draft/` | Validates and saves the body as the draft, then returns it. Invalid documents get 400 with field errors, and the old draft is kept. |
| `POST /api/pages/<handle>/publish/` | Copies the draft to the published layout, then returns `{ "publishedAt": … }` |

The editor also receives the draft on page load, as the `draftLayout` flag.

## Extending the spec

### Versioning rule

**Every change to the spec gets a new version**, additive or not. Stored documents are always at the current version, so code only ever reads one version.

To add version N+1:

1. Add `personal_links_manager/layout/vN+1.py` with its serializers, register it in `SERIALIZERS` and bump `CURRENT_VERSION`.
2. Add `UPGRADES[N]`, a function that turns an N document into an N+1 document. For a purely additive change it only sets `version` and fills new required fields with defaults.
3. Add a data migration that runs `layout.upgrade` over every `draft_layout` and `published_layout`.
4. Update `elm/src/PageEditor/Layout.elm`: the version constant, the types, the decoder and the encoder.

### Where planned features go

| Feature | Change |
|---|---|
| Reordering links or sections | None in the format. The editor reorders the lists. |
| Moving a link to another section | None in the format. The item moves between lists. |
| Several link groups | None in the format. A page may already have several `links` sections. |
| A custom section | A new section `type`: add a serializer to `SECTION_TYPES`, a `SectionContent` constructor with decoder and encoder branches in `Layout.elm`, and a `viewSection` branch in `Preview.elm`. |
| A new kind of tile, e.g. a Spotify player | A new tile `type`: add a serializer to `TILE_TYPES`, a `TileContent` constructor with decoder and encoder branches, and a `viewTile` branch. It sits in the same `items` list as link tiles. |
| Tile sizes, e.g. an embed spanning both columns | A new `size` field on tiles. |
| Per-section options (title, list vs grid, visibility) | New fields on that section type. |

Adding a constructor to `SectionContent` or `TileContent` makes the Elm compiler point at every `case` that has to handle it.
