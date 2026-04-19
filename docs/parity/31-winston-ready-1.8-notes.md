# 31 Winston Ready — 1.8 Projects Nested Profile Join + Avatar Rendering Foundation Notes

**Round:** `1.8 Projects Nested Profile Join + Avatar Rendering Foundation`
**Prompt:** `devprompt/1.8-projects-nested-profile-join-avatar-rendering-foundation.md`
**Date:** 2026-04-16
**Model:** Claude Opus 4.6

## Goal Recap

1. **Nested profile name join on detail sublists** — close Winston 1.7 audit §4.2. Web `fetchProjectDetail()` nests `profiles:assignee_id(full_name)` on tasks and `profiles:user_id(full_name)` on daily logs + weekly reports; iOS 1.7 rendered ids / unlabeled rows.
2. **Owner avatar rendering foundation** — close Winston 1.7 audit §4.3. iOS 1.7 fetched `avatar_url` but never rendered it; list card + detail header showed name + SF symbol only.
3. **State truth / failure isolation** — 1.6 gate cannot regress, 1.7 per-section error pattern cannot regress, profile hydration failure must NOT collapse sections, avatar load failure must NOT pollute `errorMessage`, denied path must not leak profile maps / avatar state.
4. **Ledger truth** — `.projects` stays `.partial`; deltas honestly recorded.
5. Do NOT expand into CRUD / members UI / AI / risk / linked actions / resolution feedback / `task_count` / schema changes.

## What Was Delivered

### Goal A — Nested profile name join on detail sublists

**DTO extension** — `Brainstorm+/Features/Projects/ProjectDetailModels.swift`:

- `ProjectDailyLogSummary` gained `userId: UUID?` (CodingKey `user_id`).
- `ProjectWeeklySummary` gained `userId: UUID?` (CodingKey `user_id`).
- `ProjectTaskSummary.assigneeId` already existed from 1.7 — unchanged.
- DTOs remain narrow; they still do NOT ingest nested `profiles` shapes directly.

**ViewModel hydrate** — `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`:

- New `@Published var profilesById: [UUID: ProjectOwnerSummary] = [:]` — reuses `ProjectOwnerSummary` since the select shape (`id, full_name, avatar_url`) is identical to owner hydrate.
- New `EnrichmentSection.sublistProfiles` case — gives the batched hydrate its own per-section error key instead of collapsing `tasks` / `dailyLogs` / `weeklySummaries`.
- `fetchDailyLogs()` select extended to `"id, date, content, progress, blockers, user_id"`.
- `fetchWeeklySummaries()` select extended to `"id, week_start, summary, highlights, challenges, user_id"`.
- New private `hydrateSublistProfiles()`:

  ```swift
  private func hydrateSublistProfiles() async {
      var ids = Set<UUID>()
      for t in tasks { if let a = t.assigneeId { ids.insert(a) } }
      for l in dailyLogs { if let u = l.userId { ids.insert(u) } }
      for w in weeklySummaries { if let u = w.userId { ids.insert(u) } }
      if let ownerId = owner?.id { ids.remove(ownerId) }
      guard !ids.isEmpty else { self.profilesById = [:]; return }
      do {
          let rows: [ProjectOwnerSummary] = try await client
              .from("profiles")
              .select("id, full_name, avatar_url")
              .in("id", values: Array(ids))
              .execute()
              .value
          var map: [UUID: ProjectOwnerSummary] = [:]
          for row in rows { map[row.id] = row }
          self.profilesById = map
      } catch {
          self.profilesById = [:]
          self.enrichmentErrors[.sublistProfiles] = error.localizedDescription
      }
  }
  ```

- Runs in `loadEnrichment(for:)` **after** `_ = await (ownerFetch, tasksFetch, dailyFetch, weeklyFetch)` — explicitly sequential relative to the parallel fan-out so we know which ids to ask about; still only ONE PostgREST round-trip, not N+1.
- New public `displayName(forUserId:)` resolver: consults `profilesById` first, then owner map as fallback (for the owner-authored case, since the owner id is removed from the batched query to avoid re-fetching), returns `nil` when neither has a name.
- `applyDeniedState()` extended to clear `profilesById` alongside the 1.7 clears.

**View wiring** — `Brainstorm+/Features/Projects/ProjectDetailView.swift`:

- New `taskMetaLine(for:)` — returns `"Status · Priority · Assignee"` when a name is resolvable, `"Status · Priority"` otherwise.
- New `authorLine(forUserId:)` — returns `"By <full_name>"` for daily log / weekly summary headers, `nil` when the name can't be resolved.
- Daily-log row: date line carries `· By <name>` inline when resolvable; silent drop otherwise.
- Weekly-summary row: `Week of <week_start>` line carries `· By <name>` inline when resolvable; silent drop otherwise.

### Goal B — Owner avatar rendering foundation

**List card** — `Brainstorm+/Features/Projects/ProjectCardView.swift`:

- Owner byline row replaces the static `person.crop.circle` SF symbol with a 16 pt `AsyncImage` circle when `owner.avatarUrl` resolves to a valid URL.
- New `avatarView(urlString:diameter:)` helper with explicit `AsyncImagePhase` switch; phases `.success` / `.failure` / `.empty` / `@unknown default` all handled.
- Fallback chain: nil / empty / invalid URL → `person.crop.circle.fill` placeholder; load failure or `.empty` phase → same placeholder.
- Thin `Color.Brand.primaryLight.opacity(0.35)` stroke overlay keeps the circle visible against `Color.Brand.paper` cards.
- Card layout / visual footprint preserved.

**Detail header** — `Brainstorm+/Features/Projects/ProjectDetailView.swift`:

- New `ownerMetaRowLayout(label:value:avatarUrl:)` replaces the icon-only owner metadata row with an inline 22 pt `AsyncImage` circle.
- New `ownerAvatarView(urlString:diameter:)` + `ownerAvatarPlaceholder` with the same explicit phase switch.
- Placeholder = `person.crop.circle.fill` tinted with `Color.Brand.textSecondary.opacity(0.7)`.
- No new global image-loading dependency; pure SwiftUI `AsyncImage`.

### Goal C — State truth / failure isolation

- `applyDeniedState()` now clears: `project`, `owner`, `tasks`, `dailyLogs`, `weeklySummaries`, `profilesById`, `enrichmentErrors`. All 1.7 + 1.8 enrichment wiped on denial.
- `hydrateSublistProfiles()` is reachable ONLY through `loadEnrichment()`, which is only invoked on `.admin` / `.member` branches of `fetchDetail(...)`. Non-member callers take the `applyDeniedState()` path and never hit the profiles hydrate.
- Sublist-hydrate failure writes to `enrichmentErrors[.sublistProfiles]` only — does NOT touch `errorMessage` and does NOT empty `tasks` / `dailyLogs` / `weeklySummaries`. Rows keep their base content (date / content / blockers / etc.); only the assignee / author token silently drops.
- `AsyncImage` failure lives entirely in the `View` layer — the view-model is never informed of an avatar failure, so it cannot pollute `errorMessage`.
- `@unknown default` phase explicitly handled in both avatar helpers for forward compatibility with new `AsyncImagePhase` cases.

### Web parity mapping

Web `BrainStorm+-Web/src/lib/actions/projects.ts` `fetchProjectDetail()` uses three nested sub-selects:

- `tasks`: `profiles:assignee_id(full_name)`
- `daily_logs`: `profiles:user_id(full_name)`
- `weekly_reports`: `profiles:user_id(full_name)`

iOS architecturally substitutes ONE batched `profiles.in("id", values: ids)` query after the parallel section fetches resolve because the Swift SDK's flat `Codable` decode doesn't ergonomically absorb nested-select shapes without mutating every summary DTO to embed a `profiles` block. For a read-only display layer the trade-off is favorable: same fields resolved to the same display names, architecturally different but semantically equivalent. Per-page cost is `4 + (1 iff ids.nonEmpty)` PostgREST round-trips, independent of row count — explicitly NOT N+1.

### `.projects` implementation status

Remains `.partial`. Promoting would overstate parity because CRUD, member picker, AI summary, risk analysis, linked risk actions, resolution feedback, and `task_count` on list are all still missing. 1.8 closes Winston 1.7 audit §4.2 (nested profile joins missing on sublists) and §4.3 (avatar rendering missing) but adds no editing / AI / risk surface.

## Ledger

- `progress.md` retitled to Sprint 1.8; captures 1.8 deliverables, skills used, and remaining gaps.
- `findings.md` replaced with 1.8 scope; detail-delta and list-delta tables updated; `Nested profiles:assignee_id on tasks`, `Nested profiles:user_id on daily logs`, `Nested profiles:user_id on weekly reports`, and both avatar-rendering rows flipped to **Delivered (1.8)**.
- `task_plan.md` marks `1.8 Projects Nested Profile Join + Avatar Rendering Foundation completed` and next-step Winston 1.8 audit.
- This notes file at `docs/parity/31-winston-ready-1.8-notes.md`.

## Skills

- `planning-with-files` — single coordinated ledger pass across findings / progress / task_plan / notes.
- `verification-before-completion` — independent `rg` scan + `xcodebuild` before claiming done.
- `systematic-debugging` — read Web `fetchProjectDetail()` nested sub-selects in `BrainStorm+-Web/src/lib/actions/projects.ts` line-by-line; verified that mutating `ProjectTaskSummary` / `ProjectDailyLogSummary` / `ProjectWeeklySummary` to embed a nested `profiles` block would spread nested-decode complexity across three DTOs whereas a single batched `profiles.in("id", values: ids)` query resolves the same fields for ≤65 ids (50 tasks + 10 daily + 5 weekly), justifying the substitution for a read-only display layer.
- `receiving-code-review` — Winston 1.7 audit §4.2 ("Nested Profile Joins Are Still Missing on Detail Sublists") and §4.3 ("Avatar Rendering Is Still Missing") are the exact gaps 1.8 closes.
- `supabase-postgres-best-practices` substituted by in-repo SDK pattern review — `.select("id, field1, field2")` + `.eq(_:value:)` + `.in(_:values:)` + `.contains(_:value:)` + `.order(_:ascending:)` + `.limit(_:)`. Skill file not present under `~/.claude/skills/`.
- `ios-development-best-practices` and `native-data-fetching` skill files not present under `~/.claude/skills/` — substituted by in-repo patterns: `@MainActor` `ObservableObject`, `@Environment(SessionManager.self)`, `@StateObject` view-model ownership, two-phase async enrichment (`async let` parallel fan-out followed by a single batched profile hydrate), per-section error capture via `[EnrichmentSection: String]`, SwiftUI-native `AsyncImage` with explicit phase switching and SF-symbol fallback, `Color.Brand` tokens, `Outfit` / `Inter` fonts.

## Prohibited Things NOT Done

- No create / update / delete project flows added.
- No member picker / membership management UI.
- No AI summary / risk analysis / linked risk actions / resolution feedback UI.
- No nested-select decode rewriting — summary DTOs kept flat; sublist profile hydration runs as ONE batched `profiles.in("id", values: ids)` query, not per-row lookups.
- No N+1 profile queries — per-page cost remains bounded at `4 + (1 iff ids.nonEmpty)` independent of row count.
- No `task_count` on list card.
- Database schema untouched.
- No string-primary routing reintroduced.
- No existing working destinations (`.tasks`, `.daily`, `.weekly`, `.schedules`, `.attendance`, `.chat`, `.knowledge`, `.notifications`, `.payroll`, `.settings`) downgraded.
- `.projects` not promoted to `.implemented`.
- No hard-coded admin user id / role. No fake local mocks substituted for real `SessionManager` / `project_members` / `profiles` / `tasks` / `daily_logs` / `weekly_reports` data.
- Navigation architecture not rewritten — 1.5 / 1.6 / 1.7 list → detail wiring preserved intact.
- No bypass / regression of 1.6 detail membership gate — sublist profile hydration runs strictly inside `loadEnrichment()`, which is only reachable on `.admin` / `.member` resolution; `.denied` path clears `profilesById` via `applyDeniedState()`.
- Avatar load failure does NOT pollute `errorMessage` — `AsyncImage` failure is view-scoped, invisible to the view-model.
- 1.7 per-section error pattern preserved — sublist-hydrate failure lives on its own key (`.sublistProfiles`), does not collapse tasks / daily / weekly rows.

## Verification

- Scan executed per prompt §4.1:

  ```bash
  cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
  rg -n 'profiles:assignee_id|profiles:user_id|assignee_id|user_id|full_name|avatar_url|AsyncImage|ProjectOwner|ProjectTask|ProjectDailyLog|ProjectWeekly|profilesById|taskAssigneesById|dailyLogUsersById|weeklySummaryUsersById|fetchDetail\(|project_members|AccessOutcome|loadEnrichment|applyDeniedState|ProjectDetailView|ProjectCardView|ProjectListViewModel|projects' Brainstorm+ progress.md findings.md task_plan.md
  ```

  Expected to confirm:
  - `ProjectDetailModels.swift` defines `ProjectOwnerSummary` / `ProjectTaskSummary` / `ProjectDailyLogSummary` / `ProjectWeeklySummary`; daily + weekly now include `userId` with CodingKey `user_id`.
  - `ProjectDetailViewModel.fetchDetail(role:userId:)` references `project_members`, `project_id`, `user_id`, `AccessOutcome`; `loadEnrichment` references `owner_id`, `tasks`, `daily_logs`, `weekly_reports`, `week_start`, `project_ids`, `created_at`; `hydrateSublistProfiles()` references `profilesById`, `profiles.in("id", values: ...)`, `EnrichmentSection.sublistProfiles`.
  - `applyDeniedState()` clears `profilesById` alongside the 1.7 clears.
  - `ProjectDetailView` references `ownerMetaRowLayout`, `ownerAvatarView`, `taskMetaLine(for:)`, `authorLine(forUserId:)`, `AsyncImage` with phase switch.
  - `ProjectCardView` references `avatarView(urlString:diameter:)`, `avatarPlaceholder`, `AsyncImage` with phase switch; `ProjectOwnerSummary` / `owner` / `ownerByline` still present from 1.7.
  - `ProjectListViewModel` references `ownersById`, `refreshOwnersForCurrentProjects`, `profiles`, `full_name`, `avatar_url`, `created_at`.
  - Ledger files record nested-profile join + avatar rendering without overclaiming (`.projects` still `.partial`; deferred list: CRUD / members UI / AI / risk / linked actions / resolution feedback / `task_count`).

- Build executed per prompt §4.2:

  ```bash
  cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
  xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
  ```

  Expected result: `** BUILD SUCCEEDED **`.

## Remaining Debt (Honest)

- **Client vs server guard** (unchanged from 1.5 / 1.6 / 1.7) — iOS admin / membership checks run client-side against `SessionManager.currentProfile`. Real enforcement is Supabase RLS. The iOS 1.8 nested-name hydrate + avatar rendering is a UX / data-fetch shaping layer, not a standalone enforcement surface.
- **`maybeSingle()` absent in Swift SDK** — iOS membership gate still uses `.select("id")` + empty-rows check (unchanged from 1.6).
- **Nested-join decode** — iOS runs a batched `profiles.in("id", values: ids)` hydrate rather than a true nested Supabase select for BOTH owner (1.7) and sublist profiles (1.8). Semantically equivalent for display; future round may revisit if SDK ergonomics improve.
- **Avatar caching** — `AsyncImage` doesn't persist across view lifecycle; scrolling list cards may re-issue image loads. Foundation-acceptable; a later round may introduce a lightweight image cache if it becomes visible.
- **Date-only decode** — `daily_logs.date` and `weekly_reports.week_start` modeled as `String` because the SDK's default decoder rejects `YYYY-MM-DD` (unchanged from 1.7).
- **`task_count`** on list card is not fetched.
- **CRUD / members UI / AI / risk / linked actions / resolution feedback** remain deferred.
- **`filteredProjects` retained** on the list as defensive smoother — a subsequent round may remove it.
- **Nested `NavigationStack`** in `ProjectListView` still present (inherited from 1.3 pattern; 1.4 / 1.5 / 1.6 / 1.7 / 1.8 all confirm detail doesn't compound it).
- **Assignee picker** still deferred from 1.1 — 1.8 added read-only assignee display, not an editor.
- 13 modules still on `ParityBacklogDestination`.

## Recommendation

建议进入 Winston 1.8 审计.
