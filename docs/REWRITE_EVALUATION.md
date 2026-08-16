# Rewrite Evaluation

**Context (2026-08-15):** the pipeline's flows are indefinitely stopped and the
`Insta-Automate` Helm release is uninstalled, both for the foreseeable future. With that downtime
available, the user is weighing whether to **archive all three repos**
(`Insta-Automate`, this control center, and the `ia_manager` mobile client) and **rebuild from
scratch**, fixing the architectural issues surfaced by reviewing them critically — rather than
continuing to build on top of them as-is.

**This is not a confirmed decision.** All three repos represent significant development time and
are stable and functionally complete for everything the user currently needs — archiving them is
a real cost, not a formality. This document exists to work through that call by evaluating the
tech stack and architecture question by question while the pipeline is paused anyway, so that if
a rewrite does happen, it starts from settled answers instead of repeating this analysis; if it
doesn't happen, the answers still stand as a record of what would be fixed.

**Logging convention:** an entry is added below only when the user says **"note that"**. Each
entry is: the question, the final decision, and a short paragraph description — including
pros/cons where they materially matter to the call.

---

## 1. Database: Postgres or SQLite?

**Decision:** Switch to SQLite.

Postgres isn't wrong, just disproportionate to what this app actually does with it — a small,
relationally loose schema (no enforced foreign keys in use today), one real local writer, and
modest volume (~2K new rows/day on the biggest table, single-digit millions even a decade out).
SQLite gives up nothing this app uses in exchange for a single-file store that backs up as a file
copy instead of the current hand-rolled CSV/topological-sort dump, and drops a whole k3s
Deployment, a k8s secret, and connection-pool management. **Pros:** trivial backup/restore,
removes a running service and its ops surface, no realistic scale ceiling for this app's growth
rate. **Cons:** loses a standing `psql` server for ad hoc querying (the `sqlite3` CLI covers
this adequately), needs `PRAGMA journal_mode=WAL` for the two-pod concurrent-write case, and is a
real, if contained, migration — every `Postgres`/`PostgresSecret` call site needs to point at a
file instead.

---

## 2. Orchestration: keep Prefect, or replace it?

**Decision:** Replace it — good tool, wrong fit for what this app actually needs from it.

Prefect's actual differentiators (distributed workers, DAG dependencies, its own
scheduling/concurrency primitives) go unused: the 5 flows have no dependencies on each other, and
every piece of gating logic that matters here — backpressure, day limits, cooldowns, force-run,
reduce-reserve — is already hand-rolled in `controllers/prefect.py`, not expressed through
Prefect. What's left is a job runner plus retries, and its two-pod, git-clone-per-run deployment
shape has caused a real, repeated incident chain (`D36`–`D39`, `D55`, `D38`'s still-unfixed
work-pool-orphaning bug) and cost a whole Ops-panel checkpoint (4 of its 10 jobs) just to manage.
**Pros of replacing:** collapses the scheduler/worker split into one process, removes the
git-clone-per-run staleness trap (code changes take effect on deploy, not on next run), removes
the work-pool-orphaning bug class entirely. **Cons:** loses the one genuinely useful piece
(automatic task retries — trivially replaced with a few lines of code) and is a materially
bigger, cross-repo rework than the DB swap (Helm chart, the `ia` CLI, the deployment model) — not
something to take on lightly, but worth carrying into any rewrite given the incident history.

---

## 3. Given entries 1 and 2, is there still a dependency on WSL or Kubernetes?

**Decision:** No — both can be fully retired for this project.

Checked the live cluster rather than assume: `insta-automate`'s own Helm chart only ever deployed
the scheduler + worker pods, never Postgres or the actual Prefect server — those turned out to be
two separate, generically-named releases (`Postgres-0.1.0`, `Prefect-0.1.0`) that stayed running
even with the project's own chart uninstalled. The user confirmed these were deliberately built
generic for possible reuse across future projects, but no such projects are planned, so both are
fine to retire alongside entries 1 and 2. `wsl-bridge` itself never actually depended on WSL
despite the name — it runs as a plain native Windows exe, supervised by the agent, calling a
native `scrcpy.exe` over Windows loopback; the only real WSL dependency in this whole stack is
indirect, via Rancher Desktop using WSL2 as k3s's backend. With Postgres → SQLite and Prefect →
custom in-process scheduling, nothing in this project touches Kubernetes anymore (every other
service — `ollama`/`vl-server`/`wsl-bridge`/`ia-agent` — is already native Windows), which removes
the Rancher Desktop/WSL2 dependency as a direct consequence, along with the whole Docker-image-
build step (`ia build`) the containerized worker model required. **Pros:** collapses the entire
deployment story to native Windows processes on one machine — no more Helm charts, no Docker
images, no k8s YAML, and it retires the whole class of git-clone/work-pool-drift incidents
(`D36`–`D39`, `D55`, `D38`) at the root instead of working around them; also resolves the
Dockerfile-plaintext-secrets issue (Q10) as a side effect, since no image build would ever need
credentials baked in again. **Cons/caveats:** one loose end neither prior decision covers — the
`tg-auth` Telegram session currently lives in a Kubernetes Secret and needs a new home (a local
encrypted file, the same pattern `IA_AGENT_TOKEN` already uses) before Rancher Desktop can
actually be uninstalled.

---

## 4. Should Python be confined to the main pipeline, with control center + mobile client both pure Dart?

**Decision:** Yes.

The user raised this because control center currently carries a lot of Python (the `ia-agent`
backend) purely because the project came together late and reused the pipeline's own tooling —
worth questioning rather than inheriting by default. Checked the numbers: `agent/` is 6,294 lines
across ~20 modules with 16 dependencies; `sqlmodel`/`psycopg2-binary` (Postgres) and `kubernetes`
(used in exactly one module) are dead weight once entries 1 and 3 land, and `my-modules` was
pulled in largely for its `postgres.py`/`kubernetes.py` submodules — once those aren't needed, the
practical code-reuse argument for staying in the pipeline's language mostly evaporates. (Also
found `telethon` listed as a dependency but unused anywhere in the agent's source — unrelated
cruft a rewrite sheds for free.) **Pros:** one language across both Dart-facing products removes
a real, already-documented class of bug — hand-mirrored REST/WS contracts between two ecosystems
drifting out of sync (this file's own history has explicit callouts to keep Dart model field
tables in step with the Python API by hand); one toolchain, one dependency graph, shared actual
types instead of parallel ones. **Cons/caveats:** what's left after stripping Postgres/k8s is
genuinely hard to port, not just historically Python — `pywinpty` (ConPTY-based terminal hosting
for service supervision), `watchfiles` (the library folder watcher), `adbutils`, `psutil`
(process-tree walking), image thumbnailing — this is where Python's ecosystem is more mature than
Dart's for low-level Windows systems work, and budget real effort here specifically. Also a
structural correction to keep in mind going in: the long-lived background piece can't be the
Flutter app itself (Flutter's engine needs a render surface) — it'd be a separate headless Dart
binary (`dart compile exe`, no Flutter engine), same two-process shape as today, just one
language instead of two.

---

## 5. Can the DB metadata schema be simplified — fewer, less redundant tables?

**Decision:** Yes — six tables down to three: `entity`, `stats` (one row per day, merging
`scan`/`scrape`/`follow`), and `profiles` (merging `scanned` + `user` into one row per scanned
username, progressively filled in as it moves through scan → classify → scrape → follow).

Audited every column of every table against real read-sites across all three repos, not just
what's written. `user` (23,825 rows) turned out to be pure write-only dead weight — nothing in
the pipeline, agent, or Flutter app ever reads it back; `f1`/`f2`/`p` only matter in-memory at
scrape time for the same-request gate decision. `entity.scraped` is a column nothing ever
assigns. `entity.url` duplicates `entity.id` (fully derivable, `Entity.from_id()` already proves
the reverse direction works) despite `url` being the declared PK while everything else actually
references `id`. Merging `scanned`+`user` into one progressively-filled `profiles` row (the
user's own refinement, better than the original "just delete `user`" call) gets real per-entity
follow tracking essentially for free — a `followed_status` column (the real six-verdict string:
`FOLLOWED`/`REQUESTED`/`FOLLOWING`/`FOLLOWED_BY`/`WANTS_TO_FOLLOW`/`FAILED`, not a collapsed
bool) on a row that already exists from the scan stage, versus D49's earlier verdict that a whole
new table for this wasn't worth a cross-repo change — the calculus changes once it's designed in
from the start rather than bolted onto stable code. **No currently-consumed data is lost** —
confirmed by checking that `entity_view.py`/`insights.py`'s SQL never even selects
`user.name`/`user.bio`, so neither could have reached either Flutter client either. Two fields
(`name`, `bio`) are captured today with zero consumers and the new schema stops capturing them —
a deliberate, cheap-to-reverse choice, not a silent loss, since nothing is built around their
presence. The raw-text `posts`/`followers`/`following` strings aren't a loss at all, just a
redundant encoding of the `p`/`f1`/`f2` ints already kept. One real implementation risk flagged
for whoever builds this: `profile_scrape`'s current code re-derives its row's identity from
freshly-scraped UI text (`User.from_ui()`) instead of the already-known filename-derived id every
stage has in scope, and a blind `session.merge()` on a mismatched id would silently create an
orphan row instead of updating the right one — `classify`'s existing `Scanned.fetch(id, session)`
pattern (fetch by the known id, then mutate) is the correct one to copy for every stage's write
into the merged table. Also recommended: an explicit `stage` column
(`SCANNED`/`CLASSIFIED`/`SCRAPED`/`FOLLOWED`) rather than inferring progress from which columns
are null, since a legitimately-scraped profile with zero posts writes `p = 0`, not null.

---

## 6. Are there unnecessary library/dependency installs across the Python and Flutter codebases worth removing or replacing?

**Decision:** Yes — a handful of concrete cuts, most of them small on their own but one with
multi-repo leverage.

Checked every dependency manifest across both ecosystems against actual usage (grep against real
source, not just what's declared). **Python:** `telethon` is dead in `agent/pyproject.toml` — zero
imports anywhere in the agent source, remove regardless of the DB/k8s decisions. It's dead in
`my-modules` too — no `telegram.py` source file exists there today, only a stale `.pyc` proving a
file was deleted without its dependency declaration being cleaned up alongside it; the pipeline's
own direct `telethon` dependency is real and stays. The highest-leverage single cut: `my-modules`
directly declares `kubernetes` and `psycopg2-binary`, which every consumer repo (pipeline, agent,
`wsl-bridge`, `Prefect-K3S`, `TG-Auth`) inherits transitively today regardless of whether that repo
touches Postgres/k8s itself — pruning both out of `my-modules` once its own `postgres.py`/
`kubernetes.py` go unused (after entries 1 & 3) cleans up every downstream repo's tree in one place
instead of five. `prefect-k3s` (the pipeline's dependency, not the orchestrator) retires as a
consequence of entry 2 — it's purpose-built to manage a Prefect-on-k3s deployment model that won't
exist anymore; worth a quick check for any non-Prefect utility buried inside worth keeping
standalone before dropping it outright. Everything else on both the agent's and pipeline's lists
checked out as load-bearing with a single, traceable purpose. **Flutter:** the desktop app
(`app/pubspec.yaml`, 16 deps) is already clean — spot-checked the least-obviously-necessary one
(`flutter_acrylic`) and it's real, wired into the Mica theme. The mobile client
(`ia_manager/pubspec.yaml`) has one real cut: `fluttertoast` is used in exactly one file for
something Flutter already provides free (`ScaffoldMessenger`/`SnackBar`) — the desktop app already
solved the same "show a transient message" need without an external package, so this removes a
dependency for zero functional loss. Also flagged, not a library removal but the same spirit: the
two Dart apps use different state-management libraries (`flutter_riverpod` on desktop,
`provider` on mobile) — not urgent standalone, but worth converging on Riverpod (already
load-bearing across ~200 desktop files) if/when entry 4's Dart consolidation reaches the mobile
client, so working across both codebases doesn't mean switching mental models.

---

## 7. What code logic issues or bad decisions exist in the `Insta-Automate` pipeline repo?

**Verdict:** Five real findings, two independently verified against the live code (not just
agent-reported); ranked by severity.

1. **REEL/POST scans are double-counted against the daily scan limit — verified, high
   confidence.** `flows/entity_scan.py:54-55` increments `Scan` inside the `REEL | POST` match
   arm, then line 59-60 increments it *again* unconditionally right after the match block — both
   fire on every successful scan, since `status is True` satisfies both conditions. `PROFILE` has
   no branch-local increment, so only it counts correctly. Confirmed via `git log -S` that the
   branch-local increment is leftover from an incomplete refactor (commit `47f6c04`, "Move
   increment logic after both scan checks to avoid duplication" — the old increment was never
   actually removed). **Effect:** `REELS`/`POSTS` daily caps trigger at roughly half their
   configured value, and every "today" figure for reels/posts (Overview, Flows, Insights) reads
   double actual. One-line fix: drop the increment at line 54-55.
2. **`profile_follow` never got the disabled/unavailable-profile fast-path `profile_scrape`
   added in D68.** `tasks/ia.py:579` checks `access == PUBLIC` only; when access resolves to
   `None` (disabled/no-content profile), execution falls through to a 5s button-wait timeout and
   reports a misleading `"follow button not found"` reason instead of `UNAVAILABLE` — the same
   twin-function-drift pattern this codebase has hit before (D64/D68).
3. **`reduce_reserve`/`skip_wait`-class commands are peeked-at but never consumed for
   `entity-scan`/`entity-scrape`.** `controllers/prefect.py:246-252`'s early-return check is wired
   into all three day-limited trigger loops, but only `entity_follow_trigger` calls `self._consume(...)`
   for it. If either command is ever queued against the other two flows (misrouted API call, future
   UI bug reusing the generic command endpoint), the trigger loop tight-loops without sleeping since
   nothing clears the pending flag. Moderate confidence — needs out-of-band command misuse to
   trigger today.
4. **A resumed mid-scan retry can skip creating `scanned_dir`.** `tasks/ia.py:157-162`'s
   resume branch reuses the existing `Scanned` count without the `mkdir()` the non-resume branch
   has; a concurrent `entity_classify` run pruning the now-empty directory between retry attempts
   could raise `FileNotFoundError` on the next screenshot save. Timing-dependent, lower confidence.
5. **`remove_public`'s classifier-failure branch leaves an image ambiguous.** `tasks/ollama.py:59-67`'s
   `case _: failed += 1` doesn't move or mark the image, so `gender_classify`'s next glob silently
   re-picks it up and may promote it as if access had resolved to PRIVATE. Lower confidence —
   depends on how often the access classifier actually returns a non-PRIVATE/PUBLIC value.

---

## 8. What code logic issues or bad decisions exist in the control-center repo (`ia-agent` backend + Flutter desktop app)?

**Verdict:** Nine real findings across both halves, two independently verified against the live
code; ranked by severity.

**Agent (Python backend):**
1. **Automatic self-heal restarts block the entire event loop for up to ~10s.** The manual
   `/api/services/{name}/{action}` route explicitly offloads to `asyncio.to_thread` with a comment
   explaining why ("so a slow terminate can't stall probes or the WS fan-out") — the automatic
   self-heal path inside `services/supervisor.py`'s `tick()` doesn't follow its own documented
   rule, so a wedged service's restart freezes every probe, HTTP request, and WS broadcast
   agent-wide for the duration.
2. **No desktop-only gate on `/api/services/{name}/{action}`.** Every other device-management/
   destructive route (`pair.py`, `ops.py`) follows the D51 precedent of restricting to the desktop
   token; this one doesn't — a paired phone's token can stop `adb`/`wsl-bridge` mid-pipeline with
   no confirmation. Nothing in the mobile client's actual scope needs this; looks like an
   overlooked gap, not an intentional exposure.
3. **`PairingStore.authenticate()` does a blocking full-file rewrite on every authenticated
   request from a paired device**, on the event loop (`pairing.py:119-130`, invoked from every
   `BearerAuthMiddleware.dispatch()`) — under any I/O pressure this stalls WS delivery and other
   clients' requests too.
4. **`LibraryCounts.seed()`'s periodic reseed can clobber a concurrent watcher `touch()`
   update** (`library/counts.py`) — ironic, since the periodic reseed (D126) exists specifically as
   a staleness safety net; a real write landing mid-scan can be silently discarded by the reseed's
   stale wholesale replace.
5. Lower severity: `EventBus.publish()` has no backpressure (unbounded per-subscriber queues); a
   published event's `seq` can reflect completion order rather than emission order under
   concurrent image-cache latency.

**Desktop app (Flutter):**
6. **Overview's two "Review" buttons don't work — verified.** `features/overview/hero_tile.dart:118`
   and `curation_tile.dart:61` both hardcode `ref.read(selectedFolderProvider.notifier)
   .select(curationFolders.first)` regardless of where the actual backlog is, and neither calls
   `openReviewMode`/touches `libraryReviewingProvider` — they just browse. The exact bug class
   already found and fixed for the nav rail's own Review entry (D121/V2.13.2); Overview's parallel
   buttons never got the same fix.
7. **Notification panel's focus trap likely doesn't work as D125's own checkpoint test
   expects.** `notifications/notification_center.dart:50-80` wraps the panel in a plain
   `FocusScope`, not a `showDialog` route or `FocusTraversalGroup` scoping (grepped the whole app —
   zero uses of either anywhere) — a bare `FocusScope` doesn't constrain Tab traversal to its
   subtree. Reasoned, not observed live (rule 5 — Claude doesn't drive the GUI).
8. **Unchecked JSON casts on every WS event handler**, starting at `core/agent_ws.dart:50-58`
   and repeating in six other controllers — a real Dart gotcha, since an exception thrown inside a
   stream's `onData` callback does not route to `onError`, so one malformed frame silently drops
   without triggering the reconnect path it should.
9. Lower confidence: `library_grid.dart`'s `Ctrl+A` can apply a stale selection if the folder
   switches mid-load on a large folder (`loadAllNames()`'s internal loop re-reads the selected
   folder fresh per page, not the one captured at Ctrl+A time).

---

## 9. What code logic issues or bad decisions exist in the mobile client repo (`ia_manager`)?

**Verdict:** Seven real findings, ranked by severity — the top one is the only genuine
irreversible-data-loss risk found across all three repos this session.

1. **Long-press on Apply/Delete skips the confirmation dialog entirely, in all three curation
   screens** (`entity_images_screen.dart:914-916,939-941`, `entity_combined_images_screen.dart:757,782`,
   `folder_screen.dart:1664,1690`) — `onLongPress: () => _applyAction(skipConfirm: true)` performs
   the full move/delete batch immediately, no dialog, no undo. An accidental long-press on the same
   button that normally requires a confirm tap causes irreversible data loss with zero warning — a
   systemic, repeated pattern across all three screens, not a one-off.
2. **No heartbeat/timeout on the background WebSocket** (`services/agent_ws.dart:45-76`) — mobile
   NAT/carrier gateways commonly kill idle TCP silently; nothing (foreground-service text, UI)
   tells the user notifications have actually stopped. The single highest-risk finding for the
   phone app's actual core purpose, since it fails silently rather than loudly.
3. **Thumbnail cache leaks forever and mislabels its own format.** `utils/thumbnail_cache.dart`'s
   `evict()`/`clear()` are both fully dead code — zero call sites anywhere, confirmed by grep —
   every Apply/Delete leaves an orphaned thumbnail behind, unbounded growth on a storage-limited
   device. Compounding it: thumbnails are actually PNG (`dart:ui` only encodes PNG natively) saved
   with a `.jpg` extension, several times larger than the JPEGs the class claims to produce, and a
   `_quality` setting on the request is never read by the encoder at all.
4. **`QueueScreen`'s 800ms debounced save is silently discarded on navigation.**
   `screens/queue_screen.dart:191-194,49-55` — `dispose()` cancels the pending debounce timer but
   never flushes it; a switch/limit edit followed by navigating away inside 800ms is lost with no
   save and no warning.
5. **Manual JSON parsing in WS handlers has no error handling**, unlike the equivalent REST
   paths right next to them (`services/scheduler_controller.dart:46-52`,
   `services/flow_run_controller.dart:78-86`) — a malformed live frame throws uncaught instead of
   degrading gracefully the way the REST-fetch fallback does. Same class of bug independently found
   on the desktop app (entry 8, #8).
6. **Notification-permission denial after pairing is never surfaced.**
   `requestNotificationServicePermissions()` fires once right after a successful pair and is never
   re-checked; a denial leaves pairing reporting success and the background service running with
   zero notifications ever showing, no explanation — unlike the storage-permission path elsewhere in
   the same app, which does show one.
7. Lower confidence: a run-transition race in `FlowRunController._reload()` where a live WS event
   for a new run arriving mid-fetch can be silently dropped rather than merged.

---

## 10. Follow-ups to "what am I forgetting before starting from zero" — closing context for the rewrite

**Verdict:** answered directly, five parts. This is the working agreement the rewrite proceeds
under, not a technical architecture call like entries 1-9.

1. **Data migration** — will be planned once the new schema (entry 5) is finalized, not before.
   Gaps the old pipeline history can't answer (e.g. accurate per-entity "followed" status where
   the old schema never tracked it reliably — see D49/entry 5) will be filled from Instagram's own
   downloadable personal data export, reviewed by hand, rather than approximated or left blank.
2. **Instagram-automation detection risk is the real reason the pipeline is currently stopped** —
   not a made-up example, the actual cause. The plan: fully randomize delays, schedule, and
   per-run profile counts, and spread activity across the day instead of clustering runs at fixed
   times, which is the current design's real exposure. Deliberately **out of scope for this
   review** — the user has a blueprint already in mind and wants to design it in a dedicated
   session during implementation, not fold it into an infrastructure-focused pass.
3. **The rewrite is from-scratch with zero code reuse** — the existing three repos are reference
   material only, consulted when asked, never a starting point to copy from. **Claude does not
   write implementation code for the rewrite** — output is markdown (architecture docs,
   sequencing plans, concept explanations, code review of what the user writes), and the user
   writes every line themselves. Reason stated directly: after this project's heavy use of Claude
   Code, the user lost touch with their own codebase — they know the functionality, not the code,
   which they described as genuinely discouraging as a developer. The user is an experienced
   Python developer with zero prior Flutter experience (Flutter/Dart was the actual reason Claude
   Code was brought into this project in the first place) — so going forward, expect heavier
   teaching/explanation on Flutter/Dart and lighter-touch on Python. Any new dependency gets
   discussed for pros/cons before being adopted, standing practice, not just for the rewrite.
4. **The app will be fully non-functional for the entire rewrite period, and the user is fine
   with that** — no parallel fallback kept running once implementation starts; it's already
   stopped today regardless.
5. **Still Windows** — confirmed deliberately rather than inherited by default, since entry 3
   already removed the one dependency (Kubernetes/Rancher Desktop) that used to require it; the
   remaining Windows-specific surface (ADB, scrcpy needing a real display, Win32-specific agent
   code) is a genuine requirement of the actual hardware this runs on, not a leftover assumption.

---

## 11. Should the rewrite be one monorepo or three separate repos (matching today's structure)?

**Decision:** Monorepo — one repo, three top-level folders (pipeline, control center, mobile
client).

Two questions got untangled first. The user's instinct came from missing GitLab's
groups/subgroups (an *organizational namespace* for still-separate repos) — GitHub's actual
equivalent is a **GitHub Organization** holding independent repos, not a monorepo; the two are
orthogonal and can be combined if ever wanted, but neither requires the other. The monorepo call
itself rests on this session's own evidence, not the namespace question: the code-logic audit
(entries 7-9) found a recurring, structural pattern of cross-repo drift bugs, not one-off
mistakes — a branch pushed in one repo but forgotten in the deploy step (D36), an env var set on
one pod but not its sibling (D37), a dependency-pin conflict across three repos at once (D71),
and the mobile client independently carrying the identical manual-JSON-parsing gap also found on
the desktop app (entry 9), because no single commit could ever touch both sides of a change at
once. A monorepo makes that whole bug class structurally impossible rather than just less likely.
The deployment-level reason polyrepo would otherwise earn its keep — genuinely independent release
targets/cadences — no longer applies once entries 1-6 land (no more per-repo Docker builds, no
k8s, everything ultimately running as processes on one laptop), and shared docs stop drifting
(one `docs/` folder instead of three, fixing the exact gap that made this file's own "five repos
in play" table necessary in the first place). **Pros:** eliminates the cross-repo-sync bug class,
one clone/one commit stream matching what the user wanted anyway, one home for the planning docs
Claude produces under the working agreement (entry 10). **Cons:** none that apply at this
project's scale — the usual monorepo trade-offs (CI path-scoping, independent open-sourcing of
one piece) are moot since the user runs no CI and has no plan to split any piece out
independently.

---
