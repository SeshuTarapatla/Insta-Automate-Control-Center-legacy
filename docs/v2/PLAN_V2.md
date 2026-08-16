# v2 — Implementation plan

Thirteen checkpoints on branch `feat/v2-ui-overhaul`, ending at **v2.0.0**.

Same discipline as PLAN.md's phases, and the same project rules apply unchanged:

- **Rule 4** — each `V2.n` is a commit boundary with a manual test **the user runs before
  the commit**. Do not commit a UI checkpoint ahead of its test, not even with "awaiting
  your test" in the message. `flutter analyze` + `flutter test` are part of that gate:
  overflow is a paint-time error both `analyze` and every agent-side test are blind to
  (D19).
- **Rule 5** — the user drives the app. Build it, `flutter analyze` it, `flutter test` it,
  start it, then **stop and hand over** with a specific list of what to check. Never click,
  navigate or screenshot the running app.
- **Rule 2** — record decisions in `docs/DECISIONS.md` as they're made, continuing the `D`
  numbering (next is **D108** — see the log's own newest entry for the current count).
- **Rule 7** — no compromise on UI/UX.

## Scope boundary — read this first

> **v2 is entirely within this repo, and entirely within `app/`.**
>
> No `ia-agent` changes. No `Insta-Automate` pipeline changes. No helm chart changes. No
> mobile client changes. Every piece of data the redesign needs is already served by an
> existing REST endpoint or WS channel:
>
> | Redesign needs | Already served by |
> |---|---|
> | pipeline edge backlog counts (Flows, Overview) | `GET /api/library/folders` + the `library.changes` channel (CP 5.1) |
> | curation backlog tile (Overview) | same |
> | review mode's writes | `POST /api/library/apply`, `POST /api/library/delete` (CP 5.2) — unchanged, same confirm dialogs |
> | command palette actions | every existing controller/provider |
> | title-bar status cluster | `connectionProvider` + `dependenciesControllerProvider` |
>
> That means **no redeploys, no pod restarts, no `ia build`, no cross-repo branches**, and
> the live pipeline is never at risk from this work. If a checkpoint appears to need an
> agent change, stop and re-check — it almost certainly doesn't, and if it genuinely does
> that's a scope decision for the user, not something to absorb quietly.

`app/pubspec.yaml` version goes `1.0.0+1` → `2.0.0+1` in **V2.14**, not before.

**2026-08-10 (D121): three bug-fix checkpoints inserted ahead of the release checkpoint.**
The user brought nine live bugs/feature requests found using the accepted V2.5–V2.12 work,
too many for one checkpoint and not release-polish, so they don't belong in what was V2.13.
Grouped into three sub-checkpoints — **V2.13.1, V2.13.2, V2.13.3** — inserted between V2.12
and the release checkpoint, which is renumbered **V2.14** (still "Motion, accessibility,
release," content unchanged). This is a planning-only session — no code changed. See
`docs/DECISIONS.md`'s D121 for the full grouping rationale.

**Scope note:** V2.13.1 is the first checkpoint in this whole plan expected to touch
`agent/`, not just `app/` — a deliberate, acknowledged exception to the scope boundary
above, the same class of call as the 2026-08-05 cross-repo deviation (D113). Flagged here
so it isn't mistaken for scope creep when the implementation session gets there.

---

## V2.1 — Token foundation

**Goal:** the whole design system exists and drives the app, which looks *pixel-identical*
to today.

- Add `flutter_animate ^4.5.2`, `phosphor_flutter ^2.1.0`.
- Download and commit `app/assets/fonts/` — `InterVariable.ttf`,
  `InterVariable-Italic.ttf`, `JetBrainsMono-{Regular,Medium,Bold}.ttf`, plus both
  `OFL.txt` licenses. Wire into `pubspec.yaml` (Inter as a variable font).
- Build `core/theme/`: `tokens.dart` (every class in DESIGN_SYSTEM §1), `density.dart`,
  `build_theme.dart`, `registry.dart`, `themes/classic.dart`.
- `build_theme.dart` fills **all ~40 `ThemeData` component sub-themes** — this is the bulk
  of the work and the thing that actually removes the generic look.
- `themes/classic.dart` derives from `ColorScheme.fromSeed(0xFF6C63FF, dark)` so the match
  to today is exact rather than transcribed (THEMES §1).
- Keep `ThemeData.palette` working as a deprecated shim reading from the new tokens.
  Nothing else changes yet.

**Verify:** `flutter analyze` clean · `flutter test` 52/52 unchanged · `flutter build
windows --debug` succeeds.

**Checkpoint test (yours):** start the app and confirm it looks **the same as it did
before** — same colors, same spacing, same everything, except monospace text (service
subtitles, config path, terminal, queue names) which is now JetBrains Mono instead of the
Consolas/`monospace` mix. Anything that looks different here is a token that got a wrong
value, and it's much cheaper to catch now than after 90 files migrate onto it.

**Risk:** the sub-theme sweep is broad and easy to get subtly wrong. Mitigation: this
checkpoint's entire success criterion is "no visible change," which makes any error
immediately obvious.

---

## V2.2 — Component library

**Goal:** `app/lib/ui/` exists, is tested, and is used by nothing yet.

- Every component in [COMPONENTS.md](COMPONENTS.md), built against the tokens.
- Move `core/async_state_view.dart` → `ui/feedback.dart` (widened with `emptyWhen` +
  skeleton), and `features/services/status_dot.dart` → `ui/status.dart` (behaviour
  unchanged — it's on the do-not-undo list).
- New `app/test/ui/` suite, with real assertions for `ResizableSplit`'s minimums at the
  1024px floor and `AppTable`'s flexible-column invariant (the D77 regression).

**Verify:** `flutter analyze` clean · existing 52 tests unchanged · new `ui/` tests green.

**Checkpoint test (yours):** nothing user-visible changed. This one is a code review rather
than a click-through — skim `ui/` and say whether the vocabulary matches how you think
about the app.

---

## V2.3 — Migration

**Goal:** every feature file speaks tokens and components. The look is *consistent* for the
first time, and only incidentally different.

- Convert all 90 files under `features/`, `shell/`, `core/`.
- Wrap all seven screens in `AppPage` — this alone fixes the six page paddings (AUDIT §3)
  and the four header conventions (§4).
- Convert the eleven remaining hand-rolled `.when()` sites (AUDIT §6).
- Every number → `NumericText`, every icon → `AppIcon`, every gap → `Gap`.
- Delete the `palette` shim.

**Acceptance criteria — enforced, not aspirational:**

```bash
# must return nothing (the QR quiet zone excepted, tokened as chart.qrQuietZone)
grep -rn "Color(0x" app/lib --include=*.dart | grep -v core/theme/
grep -rn "Colors\.[a-z]" app/lib --include=*.dart | grep -v Colors.transparent
grep -rn "fontFamily: '" app/lib --include=*.dart | grep -v core/theme/
grep -rn "EdgeInsets" app/lib/features --include=*.dart   # should be near-empty
```

`test/token_coverage_test.dart` encodes the first three so they can't regress.

**Verify:** `flutter analyze` clean · all layout tests green (they are the safety net for
this checkpoint — any padding/size change that breaks a constraint shows up here) ·
`flutter build windows --debug`.

**Checkpoint test (yours):** walk all seven screens. Everything should feel *tidier* —
consistent margins, consistent headers, aligned numbers that no longer jitter as they
update — with no feature missing and no layout broken. Resize down to the 1024×700 minimum
and confirm nothing overflows.

**Risk:** the largest single checkpoint. If it feels too big while in progress, split it by
feature directory (`features/settings` + `features/services` first, then the rest) — each
half is independently verifiable.

---

## V2.4 — Theme catalog

**Goal:** the first big visible payoff. Six themes, switchable, animated.

- `themes/command_deck.dart`, `nocturne.dart`, `mica.dart`, `daylight.dart`, `swiss.dart`
  — every value from [THEMES.md](THEMES.md).
- `TerminalPalette.light` (THEMES §8).
- `theme_controller.dart` + `shared_preferences` persistence.
- Settings → **Appearance** tab: theme grid with live miniatures, density, reduce-motion,
  terminal-palette override (THEMES §9).
- `AppTokens.lerp` with real interpolation; Mica's native `setEffect` hard-cut handled and
  documented.
- `test/theme_contrast_test.dart` over all six themes × four statuses × three content
  levels.

**Verify:** `flutter analyze` · all tests · contrast test green (**adjust any value that
comes in under floor** — THEMES §7's table is computed, not measured).

**Checkpoint test (yours) — the big one:**
1. Switch through all six themes. Each should feel like a genuinely different application,
   not a recolour.
2. Visit every screen in **Daylight** specifically — it's the theme that exposes any
   remaining dark-mode assumption. Look for white-on-white, invisible borders, unreadable
   status colors.
3. Switch to **Mica** and confirm the desktop actually shows through the chrome.
4. **Open the Services terminal in Daylight and Swiss** and confirm the services' ANSI
   output is legible on white. If it isn't, set the terminal override to "always dark" —
   that's a supported outcome, not a failure (THEMES §8).
5. Toggle **compact** density and confirm nothing overflows anywhere.
6. Restart the app and confirm your theme and density persisted.

---

## V2.5 — Shell

**Goal:** title bar, nav rail, page transitions.

- Title bar: the five-dot status cluster replacing the text chip, the ⌘K button.
  **Keep the faked-maximize workaround verbatim** (`title_bar.dart:93-98`) — that's a real
  Win32 glitch fix.
- Nav rail: groups, `CountBadge`s, `Ctrl+1..7`, `Ctrl+B` collapse (persisted), the Review
  sub-item.
- `PageTransition` in `AppShell`.

**Verify:** `flutter analyze` · tests · a new `shell_layout_test.dart` covering the rail
collapsed and expanded at the 1024px floor.

**Checkpoint test (yours):** the five status dots read correctly against reality (kill a
service and watch one go red). `Ctrl+1..7` and `Ctrl+B` work. Badges show real counts. Page
transitions feel quick, not sluggish. **Confirm `?` still opens the shortcut reference and
still doesn't eat a literal `?` typed into a search box** — that was left open from CP 7.3
and the new `Ctrl+n` bindings are the moment to settle it.

---

## V2.6 — Flows pipeline

**Goal:** [SCREENS.md](SCREENS.md) §2.

- Vertical node/edge pipeline, edges carrying live backlog counts from
  `libraryFoldersControllerProvider`.
- The two ⚑ human-review edges, clickable through to Library.
- Node expansion accordion.
- **Preserve all six `_StatusKind` states and `_kindOf`'s exact derivation** (D84), the
  cooldown-only countdown rule, the D93 ⓘ tooltip content, and every button's semantics
  (D86, D88, D69) and confirm dialog.

**Verify:** `flutter analyze` · `flows_layout_test.dart` rewritten to the new structure,
still asserting every state renders and nothing overflows at 1024px — including the
four-button `entity-follow` case that overflowed for real in D87.

**Checkpoint test (yours):** all five flows show correct state. A blocked flow says *why*
inline. The backlog numbers on the edges match the Library folder counts. Cooldown counts
down and nothing else does. Trigger now / Stop / Reduce reserve all still work with their
confirms. The ⚑ edges jump to the right folder.

---

## V2.7 — Overview bento

**Goal:** [SCREENS.md](SCREENS.md) §1.

- Bento grid, the hero status tile, `FlowCardCompact`, the curation tile, caps-as-bars +
  `Sparkline`, device, recent notifications.
- Section headers keep CP 7.3's jump-to-screen behaviour.

**Verify:** `flutter analyze` · `overview_layout_test.dart` rewritten — tile reflow at all
three breakpoints, and the hero tile in all four `StatusKind`s.

**Checkpoint test (yours):** the whole page fits without scrolling at the real window size.
The hero sentence is accurate — deliberately break something (stop a service, switch a flow
off) and confirm it changes. The curation counts match Library.

---

## V2.8 — Live

**Goal:** [SCREENS.md](SCREENS.md) §3.

- Header ribbon absorbing `RunSummary`; elapsed timer; `AnimatedCounter`s.
- **Horizontal** `ResizableSplit` (⚠️ the vertical proposal was reversed — OBSERVED §7), expand-a-pane.
- Log console: level `AppSelect`, search, sticky errors preserved.
- Surface card widths computed rather than the three hardcoded per-flow values.
- The scrape before→after morph (ARCHITECTURE §9, finally).

**Preserve:** D41's large-card rule, D42's aspect ratios, D62's vertical scan filmstrip,
D67's ordering, D85's `ResultCardActions`, and `LiveController`'s auto-follow behaviour
including the `_didInitialCatchUp` latch (D69) and the exact-run-id event scoping (D40).

**Verify:** `flutter analyze` · `live_layout_test.dart` extended — this is the suite that
caught the `AgentImage` placeholder overflow at a 1080:198 crop ratio (CP 4.4), so the
computed-width change needs coverage at several window sizes.

**Checkpoint test (yours) — needs a real run.** Trigger a scrape and watch: the elapsed
timer runs, counters animate, the in-progress card morphs into the resolved composite,
images fill the full width, log search works, the split drags and persists across a
restart. Then check at least one other flow (scan or classify) to confirm the computed card
widths work where the old hardcoded 420 was tuned only for scrape.

---

## V2.9 — Library browse

**Goal:** [SCREENS.md](SCREENS.md) §5a-0 and §5a.

- **Per-folder grid cell aspect ratio first** (SCREENS §5a-0) — the highest-impact single
  fix in the Library, wasting 40–82% of every cell today.
- Stage-grouped folder rail with the ⚑ review markers; `ResizableSplit` rails.
- Single toolbar row with actions always visible (disabled, not hidden).
- Skeleton loading; `plural()` helper; `NumericText` counts.
- **Preserve D48's selection mechanics exactly** — plain click/Space toggles, arrows move
  focus only, shift ranges. This is a recorded user preference
  (`feedback-multiselect-toggle`); do not touch it.

**Verify:** `flutter analyze` · `library_layout_test.dart` extended — the toolbar at the
1024px floor is where a real overflow was caught in CP 5.3.

**Checkpoint test (yours):** rails drag and persist. Apply and Delete are visible-but-
disabled with nothing selected. Selection behaves exactly as before. Counts match.

---

## V2.10 — Library review mode

**Goal:** [SCREENS.md](SCREENS.md) §5b. The headline feature.

- Full-window review surface, keyboard map, filmstrip, progress, batch buffer.
- Entered from `R`, the toolbar, the nav rail sub-item, and the Flows ⚑ edges.
- **Writes go through the existing `POST /api/library/apply` with the existing confirm
  dialog.** Nothing is written until Apply.
- Automatic pagination as the end of the loaded set approaches — never present a partial
  set as the whole folder (the class of bug D90 caught on mobile).

Also lands here: the **lightbox** on double-click (SCREENS §5c) — ✅ confirmed by the user,
who doesn't use double-click; copy-id moves to the context menu where it already exists.

**Verify:** `flutter analyze` · a new `review_mode_test.dart` — every key maps to the right
action, the buffer is correct across a pagination boundary, `Esc` writes nothing.

**Checkpoint test (yours):** review a real batch end to end in `gender_valid`, apply it,
and confirm the files moved exactly as the grid's Apply would have. **Also test `Esc`
mid-batch and confirm nothing was written.** Then do the same in `scraped`.

**Risk:** this is the only checkpoint that writes to real curation data. The confirm dialog
and the "nothing until Apply" rule are what make it safe; verify both before trusting it
with a large batch.

---

## V2.11 — Services, Insights, Settings

**Goal:** [SCREENS.md](SCREENS.md) §4, §6, §7.

- Services: `ResizableSplit`, tiles with `accentEdge`, the framed terminal with
  search/copy/clear/font-size, dependencies as `AppTable`, a clearer self-heal affordance.
- Insights: one `AppPage`, ranking → `AppTable`, funnel draw-in animation, the caps summary
  strip, cross-links to Library.
- Settings: Ops job list → `AppTable` with live elapsed timers, Devices QR polish, Limits
  grouping.
- **Preserve** D78's funnel painter logic, D77's column behaviour, D72's ops-panel overflow
  fix, and every destructive-job confirm dialog.

**Verify:** `flutter analyze` · `services_layout_test.dart`, `insights_layout_test.dart`,
`ops_layout_test.dart`, `devices_layout_test.dart` all extended.

**Checkpoint test (yours):** terminal search and copy work against a real streaming service.
Ranking sorts and its rows still open the entity dialog. Run one non-destructive ops job
(Deploy flows / Reset work pool) and watch the live log + elapsed timer. Confirm the five
destructive jobs still prompt.

---

## V2.12 — Command palette

**Goal:** [SCREENS.md](SCREENS.md) §8.

- `ui/command/` with the registry, fuzzy matcher, grouped results, recents.
- Every source wired; every action reusing the existing path and existing confirms.
- `shortcuts_reference.dart` regenerated from the registry so it can't drift.

**Verify:** `flutter analyze` · a new `command_palette_test.dart` — the matcher, group
ordering, and that every registered action resolves to a real callback.

**Checkpoint test (yours):** `Ctrl+K` from every screen. Search for a flow, a folder, an
ops job, a theme, a config key. Confirm a destructive action invoked from the palette still
prompts. Confirm `Esc` dismisses and focus returns where it was.

---

## V2.13.1 — Device identity

**Goal:** the ADB-paired phone is identified by model everywhere, not its serial, and the
user can point the agent at a specific device instead of whatever it happens to find first.

Two live requests, grouped because both touch the same device-identification surface
(`core/device_models.dart`'s `DeviceStatus`, agent's `GET /api/device`) rather than because
they're the same size — #2 is the bigger of the two.

- **Cache the model, don't just fetch it live.** `ia_agent/api/device.py`'s `_device_model()`
  (D46) already does a best-effort `adbutils` lookup on every `GET /api/device` call and
  falls back to the bare serial on failure — but it never persists anything, so the fallback
  fires every time the phone is merely disconnected, not just on a device seen for the first
  time. Add agent-side persistence (`%LOCALAPPDATA%\ia-agent\`, the same machine-local
  precedent as D12/D50/D65's own device/session state): the first time a serial resolves to
  a real model, cache `{serial: model}` — it's fixed hardware, this never needs to expire —
  and serve the cached model on every subsequent request even while disconnected, falling
  back to the bare serial only for a serial that's never been seen at all. Today `serial`/
  `model` only render in `features/live/device_bar.dart` (confirmed the only app-side call
  site — the paired-phone list in Settings → Devices is a different system, CP 6.1's LAN
  pairing `id` token, not the ADB serial, and is unaffected).
- **A Settings control to pick the device.** Today the agent's adb lookup implicitly targets
  whatever `adbutils` finds first — fine with one phone attached, silently wrong with more
  than one. New Settings control (Devices tab, alongside the existing pairing card): a text
  field to pin a specific serial by hand, plus — when adb is reachable and reports attached
  devices — a live dropdown of currently-attached serials to pick from instead of typing.
  Needs a new agent read endpoint (`adb devices`, agent-side, matching the existing
  `wsl_bridge`/`window.py` "thin client over an existing tool" shape rather than a new
  subsystem) and a persisted "pinned serial" setting the device-status lookup prefers over
  "first device found" whenever one is set.

**Checkpoint test (yours):** disconnect the phone after it's been seen once and confirm
`DeviceBar` still shows the model, not the serial. With the phone attached, open Settings →
Devices and confirm the adb dropdown lists it; pin it by serial and confirm nothing changes
(same device); if a second device is ever available, confirm switching the pin actually
retargets `GET /api/device`.

---

## V2.13.2 — Library review mode refinements

**Goal:** three corrections to V2.10's review mode (D115) and its entry points, all found by
actually using it since acceptance.

- **Review nav entry picks the wrong folder.** The nav rail's dedicated **Review** sub-item
  (`shell/nav_rail.dart:94`) and the Overview curation tile's "Review →" button
  (`features/overview/curation_tile.dart:61`) both open `curationFolders.first` —
  but `curationFolders` (`curation_tile.dart:18`) is `['gender_valid', 'scraped']`,
  **deliberately excluding `gender_invalid`** per D115's own call to keep Overview's
  "needs attention" surface narrow. That narrowing was correct for Overview's badge/hero
  sentence; reusing the same list as the nav rail's review *entry point* is the bug — it
  means Review can never land on `gender_invalid` at all, regardless of backlog, even though
  it's first in the real YOUR REVIEW stage order (`gender_invalid → gender_valid → scraped`,
  D115's last addendum) and items selected there are exactly what feeds `gender_valid`. Fix:
  give the nav rail's Review entry its own folder-priority list matching the real stage
  order, and pick the first of those three with a nonzero backlog count — leave Overview's
  `curationFolders` (hero tile, curation tile's own badge, command palette) untouched, since
  D115's narrowing there was intentional and about a different surface.
- **Apply requires every loaded image decided — too strict for a large batch.** `review_page.dart`'s
  `canApply` (line 209) requires `images.every((e) => _decisions.containsKey(e.name))` before
  Apply unlocks at all — built deliberately (the comment at lines 204-209) to avoid ever
  presenting a partial set as the whole folder, D90's mobile bug in a new shape. The user
  wants a looser rule for the common case of working a folder in convenient chunks: apply
  whatever's actually been decided (green keeps, red discards) and leave undecided (gray)
  images untouched for a later session, instead of blocking Apply on finishing the whole
  loaded set. The folder-wide `POST /api/library/apply` (CP 5.2) can't express this — it
  reads the directory fresh and trashes *everything not selected*, so it structurally can't
  leave an undecided image alone. **The reusable primitive already exists**: D90 built
  `POST /api/library/move` (explicit `{from, to}` pairs, touches nothing else) alongside the
  existing explicit-path `delete()`, specifically because `apply()`'s whole-directory
  assumption was already wrong for one other case (mobile's paginated apply). Review mode's
  partial-apply almost certainly wants the same pair — move the green decisions, delete the
  red ones, never call `apply()` — rather than a new endpoint. Full design (what "Apply"
  should say/confirm when some images are left gray, whether the review session can be
  resumed later against the same folder) is for the implementation session.
- **Review mode takes the whole window — keep the nav rail visible.** D115 built review mode
  as "a real full-screen route covering the title bar and nav rail entirely, matching
  SCREENS.md §5b's own mockup" — a deliberate choice at the time. The user now wants the left
  nav rail to stay visible and reachable, with review confined to the Library page's own
  content area instead. This is a real reversal of that specific piece of D115, not a bug —
  scope it to the nav rail only (the user didn't ask about the title bar) and treat
  everything else about review mode (keyboard map, filmstrip, progress, batch buffer, Apply
  flow) as unchanged.

**Checkpoint test (yours):** with a backlog in `gender_invalid`, click Review from the nav
rail and confirm it opens there, not `gender_valid`. Decide a handful of images in a large
folder, leave the rest gray, and confirm Apply now runs on just the decided ones without
complaint — then reopen the same folder and confirm the undecided images are still there,
undecided. Confirm the nav rail stays visible and clickable while reviewing.

---

## V2.13.3 — Dashboard & shell fixes

**Goal:** four smaller, unrelated fixes grouped together because each is a quick, contained
polish/bug item rather than because they share a surface.

- **Caps tile stuck on yesterday's numbers.** With every flow switch off since yesterday and
  the calendar day rolled over, Overview's `CapsTile` still shows yesterday's caps as if they
  were today's. D116 already fixed the tile to prefer `liveFlows?[flow]?.today` (the
  scheduler heartbeat's live `flows.state`, pushed continuously per D28 regardless of whether
  a flow is actually triggering) over the once-per-session `burndown` snapshot — but that
  fix assumed a new day's counter always exists once the day rolls over. Two hypotheses to
  check at implementation time, not yet confirmed: (a) the agent/pipeline's day-counter row
  is only created lazily on a flow's *first trigger* of a new day, so with every flow stopped
  indefinitely no such row is ever created and the heartbeat keeps reporting the last real
  (yesterday's) row; or (b) `features/overview/caps_tile.dart`'s own fallback logic has a path
  where `liveFlows` is present but stale and it never re-derives "today" from the wall clock.
  Start with the scheduler's day-counter/heartbeat logic and `caps_tile.dart` itself.
- **Nav rail's collapse/expand button needs a precise click.** `shell/nav_rail.dart`'s
  `_CollapseToggle` is a small `IconButton`; expanding relocates it, so the user has to move
  the cursor and click again each time rather than clicking anywhere in that row. Make the
  whole horizontal strip containing the toggle clickable (`InkWell` spanning the row's full
  width), not just the icon itself.
- **Status labels read too small.** `ui/status.dart`'s `StatusChip` (and its compact dot+label
  variant) is the shared themed status-label component used by Live's counters and the
  Dependencies table. Bump its sizing (padding/font) up modestly — one shared-component
  change, same pattern V2.2/V2.7/V2.9 already established, rather than per-call-site tweaks.
- **Rename Dependencies' "This machine" group.** `core/dependency_models.dart:39` —
  `DependencyGroup.host`'s label goes from `'This machine'` to `'Host'`. One-line change.

**Checkpoint test (yours):** stop every flow, let a day roll over (or simulate it), and
confirm Overview's caps tile shows real zeros/live counts for the new day, not yesterday's
frozen numbers. Confirm the nav rail toggle responds to a click anywhere in its row, not just
the icon. Confirm status labels on Live and Dependencies read visibly larger. Confirm
Dependencies' host group now reads "Host."

---

## V2.14 — Motion, accessibility, release

**Goal:** the final pass, then tag.

- Motion audit against DESIGN_SYSTEM §1.9's doctrine — anything decorative gets removed,
  anything missing gets added. `motion.reduced` verified against the Windows setting.
- Accessibility floor (DESIGN_SYSTEM §6): every icon-only button has tooltip + semantics,
  focus order matches visual order, dialogs trap and restore focus.
- `MouseCursor` correctness sweep.
- Performance check: the library grid scrolling 7,655 thumbnails, the log console at a few
  thousand lines, Mica compositing while the terminal streams.
- Update `docs/ARCHITECTURE.md` §9 to describe what was actually built.
- `pubspec.yaml` → `2.0.0+1`. Tag `v2.0.0`.

**Checkpoint test (yours):** a full pass over every screen in at least three themes, at the
real window size and at the 1024×700 floor. Turn on Windows' "Show animations: Off" and
confirm the app goes still.

---

## Sequencing notes

- **V2.1 → V2.4 are the foundation and should not be reordered.** Tokens before components
  before migration before themes; each depends on the last, and V2.4 is where the work
  first pays off visibly. Done — see `docs/DECISIONS.md`'s D99–D106.
- **V2.5 → V2.12 are independent of each other, but not unordered** — split
  2026-08-05 (D107) into visual and functional groups, visual first, so the app looks
  finished throughout the rest of v2 rather than gaining new interactions on top of an
  unfinished look:

  | Group | Checkpoints | Why this group |
  |---|---|---|
  | **Visual** | V2.6, V2.7, V2.9, V2.5, V2.8 (in that order) | Redesigns how something already works looks or is organized — the underlying capability doesn't change. V2.6 (Flows pipeline) and V2.9 (Library's per-folder aspect ratio) lead, per this doc's own "most transformative"/"highest-impact" calls; V2.5 (Shell) and V2.8 (Live) follow as more incremental. |
  | **Functional** | V2.10, V2.12, V2.11 (in that order) | Adds a genuinely new interaction or capability. V2.10 (Library review mode) leads — it's the headline feature of all of v2, and is unlocked the moment V2.9 lands; V2.12 (Command palette) is next since `Ctrl+K` doesn't exist at all today; V2.11 (Services/Insights/Settings) last, since its real functional additions (terminal search/copy/font-size, resizable panes) are the least load-bearing of the three. |

  **Execution order: V2.6 → V2.7 → V2.9 → V2.5 → V2.8 → V2.10 → V2.12 → V2.11 → V2.13.1 →
  V2.13.2 → V2.13.3 → V2.14.**
- **V2.10 depends on V2.9** — satisfied by the order above (V2.9 comes before V2.10 either
  way). Nothing else in V2.5–V2.12 depends on anything else in that range.
- **V2.13.1–V2.13.3 are a 2026-08-10 (D121) out-of-band insertion**, not part of the
  original visual/functional split above — three bug-fix/feature-request checkpoints found
  by using the already-accepted V2.5–V2.12 work, grouped by touched surface (device
  identity; Library review mode; dashboard & shell). They're mutually independent and could
  run in any order; listed 1→3 in the order the user raised them, not by dependency.
- **V2.14 is always last**, regardless of how the rest is ordered — it audits whatever every
  other checkpoint (V2.5–V2.13.3) actually produced (motion, accessibility, performance), so
  there's nothing for it to check until they're all done.
- If the session running this is Sonnet with a limited context budget, **one checkpoint per
  session** is the right granularity. V2.3 needed two.

## Standing risks

| Risk | Mitigation |
|---|---|
| V2.3 is a 90-file mechanical change with real regression potential | The ten existing layout tests are the net; run them after every file batch, not just at the end. Split by feature directory if needed. |
| Daylight/Swiss expose dark-mode assumptions that never had to be tokens | V2.4's checkpoint test walks every screen in Daylight specifically, for exactly this. |
| ~~The real window is tall and narrow, and I have never seen it~~ | ✅ **Closed** — the app was observed 2026-08-04 (D97). The window is landscape, 1253 × 1013 logical; the affected sections are corrected. See [OBSERVED.md](OBSERVED.md). |
| Review mode writes to real curation data | Nothing written until Apply; existing endpoint; existing confirm dialog; `Esc`-writes-nothing tested explicitly. |
| Scope creep across the checkpoint list | The scope boundary at the top: no agent, pipeline, helm or mobile changes — **except V2.13.1**, an acknowledged, flagged exception (D121). If any other checkpoint seems to need one, stop and ask. |
| A theme's contrast fails after a hand-tweak | `theme_contrast_test.dart` runs in every checkpoint's gate, not just V2.4's. |

## What v2 explicitly does not do

- **No mobile client changes.** `ia_manager` keeps its current look. A matching mobile
  restyle is a separate project with its own branch (`feat/lan-agent`) and its own device
  testing loop.
- **No `fl_chart` 1.x upgrade.** Pinned at `^0.69.0` through v2.0.0; the breaking upgrade is
  a post-release item, best done alongside a chart redesign rather than inside a theming
  project.
- **No new agent endpoints, no new data — except V2.13.1.** Every other checkpoint's
  redesign is a better presentation of data the agent already serves; V2.13.1 (device
  identity caching + a manual/adb-dropdown device picker) is the one deliberate,
  D121-flagged exception.
- **No light-theme mobile parity, no web build, no localisation.** Out of scope.
