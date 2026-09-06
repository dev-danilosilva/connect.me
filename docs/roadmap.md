# Feature Roadmap

## Core (build first)

- [ ] Landing page — public marketing homepage at `/` introducing the product, with a call to action to sign up
- [ ] User registration and login
- [ ] Profile management — display name, bio, avatar URL
- [ ] Link management — add, edit, delete, reorder, show/hide
- [ ] Public profile page at `/:username`

## Next

- [ ] Theming — background color, button style, font choices, unpaywalled (see Design considerations below)
- [ ] Embedded content — Instagram posts/reels and Spotify tracks/playlists rendered inline on the page (priority embeds — see Future for the rest)
- [ ] Analytics — click counts per link, page view totals
- [ ] Avatar/image upload — store user-uploaded profile pictures

## Future

- [ ] Social icons — Twitter, Instagram, GitHub, etc. rendered as icon buttons
- [ ] Additional embeds — YouTube, SoundCloud, TikTok players inline on the page
- [ ] QR code generation for the profile URL
- [ ] Link scheduling — set a link to appear/disappear at a specific date
- [ ] Password-protected pages — gated profile for private audiences
- [ ] Custom domains — `links.yourbrand.com` pointing to the profile

## Design considerations

Design alone isn't the headline differentiator — it's easy for Linktree to copy and rarely enough on its own to make someone move an already-shared URL. It matters as *support* for the real wedge (pricing/openness, or a specific niche): a page that looks distinctly good, not templated, makes that pitch more convincing.

Principles to build toward:

- No paywalled themes or "remove branding" upsell — full styling control should be part of the free product, not a Pro-tier unlock
- Avoid the generic "stack of rounded buttons" look as the only option — support real layout variety (grid, cards, list) as theming matures
- Mobile-first — this is a page shared and opened almost entirely from phones
- Keep it fast and lightweight — no heavy trackers/scripts that slow the page down, since speed itself is part of feeling well-designed
- Sensible, good-looking defaults for users who don't want to customize anything, with depth (custom CSS, granular theme options) available for those who do
