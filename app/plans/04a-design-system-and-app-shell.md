# Plan 04a: Design System & App Shell

## Dependencies
Plan 01 (project scaffolding), Plan 02 (storage, for the tab-shell's identity-gating check)

## Scope

Land the visual foundation — typography, color tokens, icon library, shared components — and the app shell that hosts every screen. Every UI plan from here on (04, 05, 06, 08, 10, 15) depends on this.

> **Post-audit revision (2026-06-28).** A design/UX audit changed two things this plan specifies: (1) the bottom tab bar is now **Feed · Friends · Rooms · You** with compose as a **floating action button** (not a "Post" tab/modal) — see App shell; (2) the shared-component set grew (see Shared components). Original text is kept for history with inline notes where the spec changed. (Also: the app shipped with **Lucide** icons via `StarlingIcon`, not Phosphor as written below — see `.design-sync/NOTES.md`.)

### Typography
Ship three typefaces, matching the Claude Design handoff:

- **Fraunces** (variable, SOFT+WONK axes) — display face. Used for headlines, screen titles, large numerics, and the italic accent ("real" in the Welcome tagline).
- **IBM Plex Sans** (variable) — UI face. All body copy, labels, buttons, inputs.
- **IBM Plex Mono** — technical strings. Recovery phrase words, truncated pubkeys, invite-link display.

**Packaging**: ship TTFs in `app/starling/assets/fonts/` and declare them in `pubspec.yaml`. Do not pull from Google Fonts at runtime — the app must work offline on first launch and must not leak a font-CDN request on startup.

**Font files to ship** (from the design handoff):
- `Fraunces-VariableFont_SOFT_WONK_opsz_wght.ttf`
- `Fraunces-Italic-VariableFont_SOFT_WONK_opsz_wght.ttf`
- `IBMPlexSansVar-Roman.ttf`
- `IBMPlexSansVar-Italic.ttf`
- `IBMPlexMono-Regular.ttf`
- `IBMPlexMono-Medium.ttf`

### Color tokens
Warm, paper-based palette — explicitly never blue-gray. Define as a Flutter `ThemeExtension` so individual widgets can read tokens directly instead of threading colors through props.

**Neutrals**
- `paper: #F5F0E6` — page background
- `linen: #EDE6D6` — card/section background, pressed state
- `hairline: #E1D8C3` — borders, dividers
- `stone: #A09684` — tertiary text, hints
- `graphite: #6B6559` — secondary text
- `ink: #2E2A24` — primary text, near-black

**Brand (sage)**
- `sage: #7A8B6F` — primary buttons, brand accents
- `sageDeep: #5C6C52` — pressed / active
- `sageSoft: #DCE3D3` — tint backgrounds, focus halos

**Accent (clay)**
- `clay: #C96F4A` — like hearts (filled), warning markers
- `clayDeep: #A6513A`

**Semantic**
- `success: #6B8762` (moss)
- `warning: #C96F4A` (clay)
- `danger: #A6513A` (rust)

**Shadows** use `rgba(46, 42, 36, α)` — warm-ink, never pure black:
- `shadowSoft: 0 2px 12px rgba(46, 42, 36, 0.08)`
- `shadowLift: 0 4px 24px rgba(46, 42, 36, 0.10)`

**Motion**
- Standard ease: `Curves.cubic(0.25, 0.1, 0.25, 1)`
- Fast: 150ms · Standard: 250ms · Slow: 400ms

Single light theme for v1. No dark mode for MVP — add later if demanded. The Claude Design tweaks panel lets designers preview clay/sage/rust/copper accent swaps; the app ships with clay only. Do not wire accent swapping into user-facing settings.

### Spacing, radii, type scale
Publish all tokens on the `StarlingTheme` extension. Type scale values (px at logical density): display 48, h1 32, h2 24, h3 20, body 16, small 14, caption 13, micro 12. Radii: 8, 12, 16, `9999` (full). Spacing 8pt grid: 4, 8, 12, 16, 20, 24, 32, 40, 48, 64.

### Icon library
Use `phosphor_flutter` (the Phosphor icon set). Every icon in the mockup resolves to a `ph-*` name; Phosphor's Dart port provides the same set with identical names. Install:

```yaml
phosphor_flutter: ^2.0.0
```

Wrap it in a shared `StarlingIcon` widget so call sites don't import Phosphor directly — that gives us a choke point to swap icon sets later without touching every screen.

**Rationale**: the design was built in Phosphor and the visual weight is specific to that set. Flutter's built-in Material/Cupertino icons don't match — shipping them would mean repainting every icon weight and stroke by hand. Ship the real library.

### Shared components
Build these first; every subsequent plan consumes them.

- **`StarlingIcon`** — thin wrapper around `phosphor_flutter`. Props: `name`, `size`, `color`, `weight` (Regular / Bold / Fill). Default weight is Regular.
- **`Avatar`** — circle with initial fallback or image source. Sizes: xs (20), sm (28), md (36), lg (72), xl (96). Accepts `name`, `color` (background if no image), `imageProvider`. Font is Fraunces display at size/2.6 matching the design.
- **`TopBar`** — optional left slot, centered-or-left title in Fraunces, optional right slot, optional subtitle row. Used by every screen that has a header (Setup, Recovery, Settings, Post detail, Friends, etc.). Feed and Profile deliberately do not use `TopBar` — they have custom in-screen headers per Plan 06.
- **`TabBar`** (bottom) — four tabs: **Feed** (house), **Friends** (users), **Rooms** (radio), **You** (user). Active tab shows brand color and semi-bold label. _(Post-audit: the old "Post" tab was replaced by **Rooms**; compose moved to a FAB — see App shell below.)_
- **`Sheet`** — bottom-sheet modal with a drag handle, scrim, slide-up animation (280ms, eased), rounded top corners (20). Max height 85% of viewport. Used by `QrInviteSheet` (Plan 08) and anything future that needs a focused action.
- **`PrimaryButton` / `SecondaryButton` / `GhostButton`** — sage-fill / paper-with-hairline / text-only sage-deep. Primary is the default CTA; Secondary for alternative actions in the same flow; Ghost for muted actions (e.g. "Post" in the compose header). All support `block` layout (full-width, taller padding).
- **`IconButton`** — 36×36 hit target, 10px radius, linen hover. Used for top-bar affordances.
- **`Input`** — text field with optional label. Focus state: sage border + sage-soft glow.
- **`Textarea`** — multi-line variant, min-height 96, no resize handle.
- **`QRCode`** — deterministic QR rendering. Props: `data` (string), `size` (px), foreground/background colors. For v1, use a Dart QR generator (e.g. `qr` package) rather than the design's fake-grid component — we need real scannable codes, not a visual stand-in. Wrap in a fixed-size paper card with `shadowSoft`.
- **`SyncDot`** — small (8px) colored dot with optional pulse animation. Used by the feed's sync/search bar (Plan 06). Four states: synced (success), syncing (sage, pulsing), waiting (clay), offline (stone).

**Post-audit additions (2026-06-28):**
- **`StarlingCard`** — titled surface (paper, hairline border, 14 radius, optional `shadowSoft`). Replaces the ad-hoc section-card pattern in settings/profile.
- **`StarlingBadge`** — tinted status pill (leading dot or glyph + label). Consolidates the inline status chips in network/connection settings + friend reachability.
- **`StarlingAlertDialog`** / `showStarlingConfirm(...)` — themed confirmation dialog replacing the default Material `AlertDialog`; `destructive: true` renders the confirm in clay.
- **`StickyActionBar`** — bottom-pinned action bar (paper, hairline top, bottom-safe). Shared by Compose + Preview.
- **`AccentButton`** — clay-fill button (public counterpart to the existing accent variant); used for destructive confirms.
- **`StarlingIconButton`** gained `semanticLabel`/`tooltip` and a 44px min tap target (accessibility).

**Naming**: all components live under `lib/widgets/` and share the `Starling` prefix only where needed to avoid clashing with Flutter built-ins (e.g. `StarlingIcon`). Prefer unprefixed names (`Avatar`, `Sheet`, `TopBar`) when there's no clash.

### App shell
The shell is a single `ShellRoute` in `go_router` that renders:
- A full-bleed content region (the active tab's navigator)
- A pinned `TabBar` at the bottom, hidden during modal screens (Compose, onboarding, restore)

Each tab owns its own `Navigator` stack so pushing Settings from Profile doesn't pop Feed. Going back via hardware/gesture within a tab stays inside that tab; tapping a tab a second time pops its stack to root.

**Compose as a FAB** _(post-audit 2026-06-28; originally the "Post" tab)_: compose is launched from a **floating action button** (bottom-right, hidden while a voice call is active), which pushes `/compose` as a full-screen modal above the shell. Compose's actions (Cancel / Next) live in a bottom `StickyActionBar`. Dismissing returns the user to whichever tab they were on. Posting is an action, not a place — now expressed as a FAB so all four bottom slots are real destinations (Feed · Friends · Rooms · You).

**Safe areas**: the shell wraps content in `SafeArea` with `top: true` + custom bottom handling so the `TabBar` sits above the home-indicator inset. Onboarding and Restore do not use the shell — they render full-screen with their own padding.

**Identity gate**: shell mount checks `identityProvider`. If identity is missing, redirect to `/onboarding/welcome`. This is the one piece of Plan 04 that Plan 04a has to know about.

### Flutter theme wiring
Wire tokens into `ThemeData` for default text styles, button themes, and input decoration. But: the design's shapes don't map cleanly to Material defaults (e.g. buttons are 10px radius not 4, inputs are 12px radius with a specific focus halo). Rather than fight Material, ship `StarlingTheme` as a `ThemeExtension` and write custom widgets that read from it. Material defaults remain as a fallback for any third-party widget that ignores our extension.

### Riverpod
- `starlingThemeProvider` — exposes the `StarlingTheme` extension for non-widget consumers (e.g. computing a hex string for QR foreground).
- No dynamic theme-swap plumbing. Single light theme.

## Files created/modified
- `pubspec.yaml` (add `phosphor_flutter`, `qr`)
- `pubspec.yaml` (register font assets under `flutter.fonts`)
- `app/starling/assets/fonts/` — ship the 6 TTFs listed above
- `lib/theme/starling_theme.dart` — `ThemeExtension` carrying every token
- `lib/theme/starling_colors.dart` — raw color constants
- `lib/theme/starling_typography.dart` — `TextStyle` presets (display, h1, h2, h3, body, small, caption, micro, mono, quote)
- `lib/theme/starling_spacing.dart` — spacing + radii tokens
- `lib/theme/starling_motion.dart` — curves and durations
- `lib/widgets/starling_icon.dart`
- `lib/widgets/avatar.dart`
- `lib/widgets/top_bar.dart`
- `lib/widgets/tab_bar.dart`
- `lib/widgets/sheet.dart`
- `lib/widgets/buttons.dart` — primary / secondary / ghost / icon
- `lib/widgets/inputs.dart` — input + textarea
- `lib/widgets/qr_code.dart`
- `lib/widgets/sync_dot.dart`
- `lib/shell/app_shell.dart` — `ShellRoute` scaffold
- `lib/shell/tab_nav.dart` — per-tab navigator stacks
- `lib/router.dart` (update from Plan 04: register `ShellRoute`, Compose modal route, onboarding routes)
- `lib/main.dart` (update: wire `StarlingTheme` into `MaterialApp.theme`)
- `test/widgets/` — golden tests for each shared component
- `test/shell/app_shell_test.dart` — tab-switching, identity-gate redirect, Compose modal behavior

## Verification
- Every token defined in the mockup CSS (`colors_and_type.css`) has a corresponding Dart token on `StarlingTheme`
- Fraunces renders correctly for display text on both platforms (italic variant works for the Welcome "real" accent)
- IBM Plex Sans renders in Roman + Italic; weights 100–700 are reachable via variable axis
- IBM Plex Mono renders Regular + Medium
- Phosphor icons match the design's `ph-*` names one-to-one (spot-check 10 icons from the mockup)
- Shell: Feed / Friends / You tabs preserve their navigation stack when switching away and back
- Shell: tapping "Post" opens Compose as a full-screen modal over the current tab; dismissing returns to that tab
- Shell: tapping the current tab a second time pops its stack to root
- Shell: no identity → redirects to `/onboarding/welcome`
- `Sheet` animates in at ~280ms, scrim fades, content is scrollable if it overflows
- `QRCode` produces a scannable QR for a sample `starling://connect?card=...` payload (scan with another phone)
- `Avatar` renders image source if provided, otherwise initial over background color
- Buttons: primary/secondary/ghost/icon all match the design's padding, radius, and hover/pressed states
- Input focus state shows sage border + sage-soft 3px outer glow
- Golden tests pass on both iOS and Android form factors

## Key decisions
- **Ship fonts, don't fetch them.** The app is supposed to work offline and leak no network requests on first launch. Google Fonts at runtime violates that.
- **`phosphor_flutter` over hand-rolled icons.** The design's visual weight is Phosphor-specific. Repainting Material icons to match would cost far more than the ~400KB the package adds.
- **Tokens via `ThemeExtension`, not Material theming.** Material's button/input theming is shaped around its own geometry. Starling's shapes (10/12/14px radii, specific hover/pressed colors, custom focus halo) don't fit cleanly; fighting Material produces subtly-wrong output. Custom widgets reading from an extension is the simpler path.
- **"Post" tab opens a modal, not a navigator.** Posting is an event, not a place — modal framing matches the mental model and avoids an empty "Compose tab" state.
- **Single light theme.** Dark mode is not in the design and would double the design surface. Defer.
- **No accent-color toggle in Settings.** The mockup exposes clay/sage/rust/copper as a designer-only tweak, not a user feature. Ship clay.

## Risks
- **Font size.** The six TTFs add ~2–3MB to the app bundle. Acceptable, but worth confirming against platform size budgets (iOS "over-the-air" 200MB cellular cap, Android APK size).
- **Phosphor package maintenance.** If `phosphor_flutter` falls behind the upstream icon set, we might miss new icons. Mitigation: our `StarlingIcon` wrapper isolates the choke point.
- **Per-tab navigator state.** `go_router`'s `StatefulShellRoute` handles this correctly but has edge cases around deep links. Test deep links into non-active tabs explicitly.
- **QR encoding capacity.** Base64url-encoded connection cards can exceed low-density QR capacity if endpoints list is large. The `qr` package supports dynamic sizing — verify the worst-case card (pubkey + .onion + relay .onion + capabilities) stays within scannable density.
