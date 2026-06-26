# OpenGateSP design system

The reference for the OpenGateSP GUI (WPF). Everything here already lives in code —
`gui/Start-OpenGateSPGui.ps1` (`$XamlControls` = component styles, `$Xaml*` = theme token
dictionaries) and `gui/MainWindow.xaml` (layout). This doc is the contract: **build new UI from
these tokens and components so the app stays one coherent surface.** Design direction follows
ShareGate Migrate/Protect — calm, guided, foolproof — see [[opengatesp-design-northstar]].

> How to extend: add a `<Style x:Key="…">` to `$XamlControls` once, reuse it everywhere via
> `Style="{DynamicResource …}"`. Add colours only as **semantic tokens** (below) to every theme
> dictionary — never hard-code a hex in a view. Every `x:Name` auto-binds to `$script:<Name>`.

## 1. Color tokens (semantic, not literal)

Views reference **roles**, not colours, so all four themes stay consistent. Defined per theme in
`$XamlFluentLight` / `$XamlFluentDark` / `$XamlLight` (Gruvbox) / `$XamlDark` (Tokyo Night).

| Token | Role |
|---|---|
| `Bg` | App / content background |
| `BgElev` | Raised surface — cards, inputs, nav rail, app bar, rows |
| `BgElev2` | Higher surface — hover, selected row, active nav |
| `Fg` | Primary text |
| `FgMute` | Secondary text, captions, labels, nav idle |
| `FgFaint` | Tertiary / disabled-ish text |
| `Accent` | Brand + primary action + active state + section headings |
| `AccentHover` | Accent hover |
| `AccentFg` | Text/icon on an accent fill |
| `Border` | Hairline dividers, input borders, grid lines |
| `BorderStrong` | Stronger border, hover border |
| `Good` / `GoodFg` | Success (export, healthy) |
| `Warn` / `WarnFg` | Warning / dry-run "Preview" actions — text uses `WarnFg` **on** a `Warn` fill |
| `Danger` / `DangerFg` | Error / destructive — text uses `DangerFg` **on** a `Danger` fill |

> On-fill text always uses the paired `*Fg` token so contrast is intentional per theme, never
> borrowed (e.g. `WarnButton` foreground = `WarnFg`). Don't put `Fg`/`AccentFg` text on a `Warn`/
> `Danger`/`Good` fill.

**Severity is data-bound**: the DataGrid colours rows by a `Severity` or `Status` field
(`Error`→Danger, `Warning`→Warn, `Skipped`→FgMute). New result objects get colour for free by
emitting one of those fields.

**Contrast**: every theme is tuned to WCAG AA for body text on `Bg`/`BgElev`. Keep new pairings AA
(≥4.5:1 normal text, ≥3:1 large/UI).

## 2. Themes

`Fluent Light` (default), `Fluent Dark`, `Gruvbox`, `Tokyo Night` — picker in the app bar, saved to
`%APPDATA%\OpenGateSP\gui.json`. Fluent is the primary identity (Microsoft-native, the audience's
home turf); the others are opt-in personality. Design and test against **Fluent Light first**.

## 3. Type scale

Segoe UI throughout; **Consolas** for brand wordmark, code, and `*Meta` captions (the "scriptable"
signature). Sizes/weights as used today:

| Role | Size / weight | Use |
|---|---|---|
| Display | 22 Bold | View hero ("What do you want to do?") |
| Brand | 19 Bold, Consolas, Accent | App-bar wordmark |
| Card title | 16 Bold | Card / choice titles |
| Section | 13 Bold, Accent | Group/section headings (`Section` style) |
| Body | 13 | Controls, labels, default |
| Nav item | 14 SemiBold | Left-nav entries (`NavButton`) |
| Caption | 12, FgMute | Helper text, muted notes (`Muted` style) |
| Meta / code | 12 Consolas, FgMute | Card meta, command text (`CardMeta`) |
| Group header | 11 SemiBold, FgMute | Nav group labels (`NavGroupHeader`) |

> **Integer sizes only** (fractional sizes render softer in WPF). Bias new text to Fluent 2's ramp —
> Caption 12 / Body 14 / Subtitle 16/20 / Title 20/28 / Display 28/36 — and prefer **SemiBold (600)**
> for emphasis, reserving Bold for the brand wordmark and view heroes.

## 4. Spacing, radius, motion

- **Spacing scale**: 4 · 8 · 12 · 16 · 24 · 32. View padding `28,26`; field row gap `5`; control gap
  `8`. Align to the grid; don't invent one-off margins.
- **Radius**: 8 (inputs, dropdowns, nav, buttons-inner 9), 14 (cards), 6 (menu items). Pick by size,
  stay in the set.
- **Motion**: subtle and purposeful only — combo fade, hover overlays (10% / 18% pressed), the
  indeterminate busy bar. No decorative animation. (Honor reduced-motion if added later.)

## 5. Components (in `$XamlControls`)

| Style key | Control | Notes |
|---|---|---|
| *(default)* `Button` | primary | Accent fill, white-overlay hover/press, 0.45 disabled |
| `GhostButton` | secondary | Transparent + strong border — secondary actions |
| `WarnButton` | preview | Warn fill — **dry-run "Preview (WhatIf)"** (the safety affordance) |
| `GoodButton` | success | Good fill — export / confirm-safe |
| `TextBox` / `ComboBox` / `CheckBox` | inputs | 8-radius, accent focus ring, custom check/caret |
| `TabControl` / `TabItem` | tabs | Underline-on-select — the Copy "type of copy" chooser |
| `Card` / `CardTitle` / `CardBody` / `CardMeta` | choice card | 14-radius, accent border on hover — the chooser tiles |
| `NavButton` / `NavGroupHeader` | left nav | Accent left-bar + tint when active |
| `Breadcrumb` | wizard trail | `Group › View` today; the wizard extends it to `Copy › Source › …` |
| `EmptyState` | empty grid | Centered, invites an action |
| `DataGrid` (+ header/row/cell) | results | Zebra rows, severity colouring, read-only |
| `NavIcon` + Segoe MDL2 glyphs | left nav | Icon + label per item — one icon set, single weight, on-grid |
| `FocusVisual` | interactive | 2px Accent **keyboard focus ring** on buttons/nav/cards |
| Toast (`Show-Toast`) | feedback | Top-right, status-coloured bar; success auto-dismisses, errors persist, click to dismiss |
| App-bar cog → `ViewSettings` | settings | Theme, connection, logs, about + update-check in one place |
| First-run onboarding (`Show-Onboarding`) | first launch | Guided, in-app Entra app setup when no connection is saved |

## 6. Layout & navigation

- **Shell**: app bar (brand · breadcrumb · connection pill · theme) / left **nav rail** (240) /
  scrolling content / status bar (message + busy bar). One window, views toggled by `Show-View`.
- **Nav** is grouped with small-caps `NavGroupHeader`s and ordered by the journey
  (discover → move → verify → govern). Active item shows the accent bar. (Group order + rationale:
  §8.)
- **Connection state** is always visible (the app-bar pill: dot + "Connected: …").

## 7. The dry-run-first safety pattern (signature)

Every write operation previews before it acts — the product's trust signature. In the GUI that is a
**`WarnButton` "Preview (WhatIf)"** beside the primary **Run/Apply**, and a confirm dialog before
anything that writes. Engine cmdlets are dry-run by default; the GUI mirrors that. Never give a
write action a single un-previewable button.

## 8. Navigation IA (and why it's ordered this way)

The rail reads like a **migration runbook**, not a feature dump — grouped by the real timeline
*assess → move → verify → govern*, mirroring ShareGate's structure:

```
 Home                         ← launchpad (pinned top, ungrouped)
 MIGRATION
   Explore                    ← read-only source assessment (Invoke-SPExplore + discovery)
   Copy                       ← the guided chooser + wizard (absorbs file-share import + Teams/Groups)
   Pre-check                  ← local folder readiness (Test-SPMigrationReadiness)
   Security                   ← sharing / permissions / matrix / orphaned / inventory + lifecycle
 ACTIVITY
   Tasks                      ← what's run this session + result
   Scheduled                  ← unattended governance reports
 GOVERNANCE
   Provisioning               ← create sites, bulk metadata
 Connect                      ← global connection (pinned bottom — setup, not a per-copy step)
```

**Why this order.** *Explore is first* because the safe, read-only assessment is the correct entry
point — look before you leap — and it teaches the right sequence the moment the app opens. *Copy is
one node*: folding the old Migrate / Copy-site / Teams-&-Groups into a single chooser collapses three
competing "where do I copy?" entries into one, the biggest cognitive-load cut. *Splitting one-time
project work (MIGRATION) from recurring oversight (ACTIVITY / GOVERNANCE)* means a user never scans an
unrelated list to find what they need now. *Connect lives at the bottom*, not as a step, because
OpenGateSP uses one saved connection — it's setup, not part of a copy.

> To add a nav item: add a `RadioButton` (style `NavButton`) under the right group header in
> `MainWindow.xaml`, then add the view to `$script:ViewMap`/`CrumbMap`/`GroupMap` and a
> `NavX.Add_Checked({ Show-View 'X' })` in the PS1. Keep groups to ~3–5 items.

## 9. The guided Copy wizard (the centerpiece pattern)

ShareGate's foolproof copy is **chooser → breadcrumb steps**, and OpenGateSP mirrors it:

1. **Chooser** (`ViewCopyLanding`) — *"What would you like to copy?"* A `TabControl`
   (SharePoint · Collaboration · Import external) over a `WrapPanel` of `Card`s. Each card states
   **what's copied** in plain words and routes to the right flow. A *Recent copies* grid lets you
   re-run. This is the single entry — a new user can't pick the wrong tool.
2. **Wizard** (`ViewCopyWizard`) — a five-step flow with a **step rail** at the top
   (`Source › Destination › Scope › Options › Preview & run`), a step-panel host, and a **sticky
   footer** (`‹ Back` · "Step n of 5" · `Next ›` / `Preview` + `Run`). One step visible at a time.

Rules baked in (see §10): **Next is disabled until the step is valid** (source present;
destination present and ≠ source); **Run is locked until you Preview the current settings** (a
param-hash re-arms it whenever an option changes); every Run **confirms with a named summary**. The
Scope step uses **`Compare-SPSite`** — our stand-in for ShareGate's dual live trees — to show
source-vs-destination lists with the diff in one grid. Each control maps to one `Copy-SPSite` /
`Copy-SPList` parameter (`Build-CopyParams` is the single source of truth for Preview, Run, and a
future "Copy as PowerShell").

> To add a step: add a `Panel*` to the step host, extend `$panels`/`$steps` in `Set-WizardStep`,
> add its validation to `Update-WizardNav`, and map its controls in `Build-CopyParams`. To add a
> copy *type*: add a `Card`, an `Open-CopyWizard '<type>'` handler, and a branch in
> `Build-CopyParams`.

## 10. Human-interface principles

Make it impossible to get lost, honest about what it does, and quiet around one focal point.

1. **One primary action per screen.** Exactly one filled accent button (the step's `Next`/primary).
   `Back` is a ghost; the destructive `Run` is gated and never the default focus.
2. **The breadcrumb/step rail is real.** It shows *where you are* and *how many steps remain*, and
   lets you move backward with state intact; future steps stay locked.
3. **Disabled-until-valid.** Don't let someone reach an action that will fail — grey `Next` until
   required fields validate (URL present, source ≠ destination), and surface Connect inline if the
   connection isn't live, rather than failing at Run.
4. **Preview before run, always.** Writes are gated behind a dry-run (`-WhatIf`) of the *current*
   settings; change anything and the preview must be re-run. This is the product's trust signature
   (§7) — never a single un-previewable write button.
5. **Plain-language scope.** Say what's copied and what isn't in human terms; show unsupported items
   **disabled with a why-tooltip**, not hidden. Honest scope beats silent omission.
6. **Confirm writes with a named summary.** Every write shows `source → destination` and the action;
   nothing writes on a lone click.
7. **Name things by what the user controls**, never by the system. "If items already exist:
   Copy and replace / Don't copy / Keep both / Copy if newer" — the engine value (`Replace`…) lives
   in a tooltip. An action keeps its name through the flow ("Run copy" → "Copy complete").
8. **Empty/error/loading are direction, not mood.** Empty states invite the next action ("Your
   copies will show up here…"); errors say what happened and where to look ("…see ./logs"); the busy
   bar shows work is happening.

### What separates award-winning from generic (do / don't)

- **Spacing discipline** — every gap from the 4/8/12/16/24/32 scale; align controls to one grid.
  Inconsistent margins read as amateur faster than any color choice.
- **One accent.** `Accent` carries brand + primary action + active state and nothing competes.
  Resist a second bright color.
- **Restraint (Chanel's mirror).** Before shipping a screen, remove one element — the densest screen
  is rarely the clearest. Let the wizard's guidance be the one memorable thing.
- **Consistent iconography & labels.** Same word for the same concept everywhere; sentence case;
  active voice; no filler.
- **Hierarchy through type & weight**, not boxes. Lead with a clear title, then muted helper text;
  don't wrap everything in borders.
- **AA contrast, visible focus.** Keep ≥4.5:1 body text; the accent focus ring on inputs stays.
- **Motion is subtle and purposeful** — hover/press overlays, the busy bar. No decorative animation;
  it reads as AI-generated.
- **Don't** expose system/PowerShell jargon in primary UI, hide unsupported options silently, stack
  multiple primary buttons, or invent one-off colors/margins. **Do** preview-before-write, disable-
  until-valid, and explain every empty/error state.

---

## 11. Refinements & follow-ups (from the cited design review)

Concrete specifics to apply as the GUI matures — grounded in Fluent 2, WCAG 2.1, and NN/g.

**Already applied (v0.9.0):** integer type ramp; paired on-fill tokens `WarnFg`/`DangerFg`
(`WarnButton` no longer borrows `AccentFg`); validation-driven `Next`/`Run` gating in the wizard.

**Already applied (v0.10.0):** nav icons + app identity; a Settings cog/view; first-run onboarding;
toasts; keyboard shortcuts (`?` overlay / `Esc` / `Ctrl+,`); in-context tooltips; and the **2px
keyboard focus ring** (`FocusVisual`, on buttons/nav/cards).

**Prioritized follow-ups** (highest leverage first):

1. **Extend the focus ring to tabs + text inputs** — `FocusVisual` now applies to buttons/nav/cards
   (v0.10.0); add it to `TabItem`, `TextBox`, `ComboBox`, `CheckBox` for full coverage. (learn.microsoft *styling-for-focus-and-focusvisualstyle*; WinUI focus specs)
2. **Tabular, right-aligned numerals for numeric grid columns** — the single biggest "made by pros"
   signal for a data tool. In `Show-Grid`, right-align + `Consolas`/`Typography.NumeralAlignment="Tabular"`
   on count/size columns. (Stripe; Vercel Geist)
3. **`AutomationProperties.Name`/`LabeledBy`/`HelpText` on every input**, plus `AccessText`
   mnemonics, **Enter**=primary / **Esc**=cancel, and `TabNavigation="Cycle"` in dialogs. (learn.microsoft *AutomationProperties*)
4. **Validate on blur, error beside the field (text + icon, not color alone)** — keep future-step
   locking; add "Advanced options" progressive disclosure for rarely-used fields. (NN/g *errors-forms-design-guidelines*, *progressive-disclosure*, *wizards*)
5. **Toast channel for results** (top-right, status-colored, success auto-dismiss 4–6s, errors
   persist, `AutomationProperties.LiveSetting`); keep the status bar for in-progress. (Fluent/M365)
6. **Elevation discipline** — hairline 1px borders as the default separator; `DropShadowEffect`
   (`CacheMode="BitmapCache"`) only on true floating layers (menus/dialogs/toasts). (Refactoring UI; Fluent shadow tokens)
7. **Motion tokens** — 100/150/250 ms; enter = decelerate (`CubicEase` Out), exit = accelerate (In);
   animate `RenderTransform`+`Opacity` only; **gate storyboards on
   `[System.Windows.SystemParameters]::ClientAreaAnimation`** for reduced-motion. (learn.microsoft *timing-and-easing*, *SystemParameters*)
8. **One icon set** — Segoe Fluent Icons (ships with Win11, zero dependency), all-outline, single
   stroke, on the pixel grid; the app is icon-light today. (designsystems.com *iconography-guide*)
9. **Contrast audit** — verify `FgMute` on `Bg` per theme (the usual AA miss) and apply WCAG **1.4.11**
   (UI boundaries + focus ≥3:1). (w3.org/WAI/WCAG21; webaim.org checker)

**Product follow-ups:** persist Recent copies + the wizard draft to `%APPDATA%`; a dedicated
Settings / PowerShell-&-MCP view; a cross-tenant path inside the wizard (today same-tenant; cross-tenant
stays on the CLI/MCP).

---

*Implemented in `gui/Start-OpenGateSPGui.ps1` (`$XamlControls` + theme dictionaries + view wiring) and
`gui/MainWindow.xaml`. Change a token or component once and it propagates across all four themes.*
