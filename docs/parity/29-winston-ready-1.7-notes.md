# 29 Winston Ready — 1.7 Projects Owner Profile Join + Detail Enrichment Foundation Notes

**Round:** `1.7 Projects Owner Profile Join + Detail Enrichment Foundation`
**Prompt:** `devprompt/1.7-projects-owner-profile-join-detail-enrichment-foundation.md`
**Date:** 2026-04-16
**Model:** Claude Opus 4.6

## Goal Recap

1. **Owner profile join foundation** — list card + detail must display human-readable owner (`full_name`) instead of raw UUID, mirroring Web `select('*, profiles:owner_id(full_name, avatar_url)')`.
2. **Read-only Project detail enrichment foundation** — after the 1.6 gate passes, populate the three Web `fetchProjectDetail()` sub-lists: tasks (≤50), recent daily logs (≤10), weekly summaries (≤5).
3. **State truth** — `isLoading` / `errorMessage` / `.denied` behavior cannot regress; one failing sub-fetch must not collapse the whole detail; enrichment must not leak through `.denied`.
4. **Ledger truth** — `.projects` stays `.partial`; deltas honestly recorded.
5. Do NOT expand into CRUD / members UI / AI / risk / linked actions / resolution feedback.

## What Was Delivered

### Goal A — Owner profile join foundation

**New file:** `Brainstorm+/Features/Projects/ProjectDetailModels.swift` — hosts four lightweight DTOs. Owner summary:

```swift
public struct ProjectOwnerSummary: Identifiable, Codable, Hashable {
    public let id: UUID
    public let fullName: String?
    public let avatarUrl: String?
    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
    }
}
```

Deliberate narrow DTO, not a `Profile` alias — this keeps core `Profile` / `Project` models unchanged and keeps the Supabase decode shape flat rather than chasing nested-select decode in the Swift SDK.

**List path** — `Brainstorm+/Features/Projects/ProjectListViewModel.swift`:

- New `@Published var ownersById: [UUID: ProjectOwnerSummary] = [:]` + `ownersErrorMessage: String?`.
- New private `refreshOwnersForCurrentProjects()` runs after every successful `runProjectsQuery(...)`:

  ```swift
  let ownerIds = Array(Set(projects.compactMap { $0.ownerId }))
  let rows: [ProjectOwnerSummary] = try await client
      .from("profiles")
      .select("id, full_name, avatar_url")
      .in("id", values: ownerIds)
      .execute()
      .value
  ```

- Best-effort: any failure clears `ownersById` + sets `ownersErrorMessage`, but leaves `projects` / `errorMessage` / `scopeOutcome` untouched so the list still renders with the UUID fallback.
- `noMembership` and missing-identity short-circuits also clear owners — cannot leak cached owners from a prior admin session.

**List card** — `Brainstorm+/Features/Projects/ProjectCardView.swift`:

- New `public let owner: ProjectOwnerSummary?` parameter (default `nil` for backward compatibility).
- New `ownerByline` computed: `owner.fullName` (if non-empty) → `project.ownerId.uuidString` → nil (hidden only if the project has no `ownerId` at all).
- Rendered under the title as `person.crop.circle` icon + name.

**List wiring** — `ProjectListView.swift` passes `owner: project.ownerId.flatMap { viewModel.ownersById[$0] }` into the card.

**Detail path** — `ProjectDetailViewModel.swift` + `ProjectDetailView.swift`:

- New `@Published var owner: ProjectOwnerSummary?` populated by `fetchOwner(ownerId:)`:

  ```swift
  let rows: [ProjectOwnerSummary] = try await client
      .from("profiles")
      .select("id, full_name, avatar_url")
      .eq("id", value: ownerId)
      .limit(1)
      .execute()
      .value
  return rows.first
  ```

- `ownerMetaRow(project:)` in `ProjectDetailView` now prefers `viewModel.owner?.fullName`, falls back to UUID string, hides only when `project.ownerId == nil`. Owner join failure → `enrichmentErrors[.owner]` banner, row still renders with UUID fallback.

### Goal B — Read-only detail enrichment foundation

**DTOs** — in `ProjectDetailModels.swift`:

- `ProjectTaskSummary(id, title, status, priority, assigneeId)` — `status` / `priority` as `String` for decode tolerance in a read-only section.
- `ProjectDailyLogSummary(id, date, content, progress, blockers)` — `date` as `String` (see date-only SDK note below).
- `ProjectWeeklySummary(id, weekStart, summary, highlights, challenges)` — `weekStart` as `String` for the same reason.

**ViewModel fan-out** — `ProjectDetailViewModel.loadEnrichment(for:)`:

```swift
async let ownerFetch = fetchOwner(ownerId: projectRow.ownerId)
async let tasksFetch = fetchTasks(projectId: projectRow.id)
async let dailyFetch = fetchDailyLogs(projectId: projectRow.id)
async let weeklyFetch = fetchWeeklySummaries(projectId: projectRow.id)
_ = await (ownerFetch, tasksFetch, dailyFetch, weeklyFetch)
```

Called **only after** the 1.6 access gate resolves to `.admin` or `.member` and the `projects` row refresh succeeds. `.denied` path short-circuits before enrichment and calls `applyDeniedState()` which clears `project` + `owner` + `tasks` + `dailyLogs` + `weeklySummaries` + `enrichmentErrors`.

Each sub-fetch catches its own error into `enrichmentErrors[.section]` without throwing, so one failing sub-query cannot knock out the rest.

**Query shapes** mirror Web `BrainStorm+-Web/src/lib/actions/projects.ts` `fetchProjectDetail()`:

- `tasks`: `.from("tasks").select("id, title, status, priority, assignee_id").eq("project_id", value: projectId).order("created_at", ascending: false).limit(50)`
- `daily_logs`: `.from("daily_logs").select("id, date, content, progress, blockers").eq("project_id", value: projectId).order("date", ascending: false).limit(10)`
- `weekly_reports`: `.from("weekly_reports").select("id, week_start, summary, highlights, challenges").contains("project_ids", value: [projectId.uuidString]).order("week_start", ascending: false).limit(5)`

### `project_ids @> [projectId]` in Swift

Verified parity with Web `.contains('project_ids', [projectId])`:

- `PostgrestFilterBuilder.contains(_:value:)` at `SourcePackages/checkouts/supabase-swift/Sources/PostgREST/PostgrestFilterBuilder.swift:332` emits `cs.<raw>`.
- `Array: PostgrestFilterValue where Element: PostgrestFilterValue` at `.../PostgrestFilterValue.swift:41` serializes `[String]` as `{v1,v2}`.
- Net wire format: `project_ids=cs.{uuid}` — semantically equivalent to Web.

### Date-only columns `daily_logs.date` / `weekly_reports.week_start`

Both are Postgres `date` columns (`YYYY-MM-DD`). `JSONDecoder.supabase()` at `supabase-swift/Sources/Helpers/Codable.swift:14-30` parses `String → Date` via ISO8601 with-then-without fractional seconds only; neither accepts bare `YYYY-MM-DD`, so a `Date`-typed DTO would throw at decode.

DTOs intentionally model these fields as `String` for stable decode + display. Documented in `findings.md` as a known SDK delta worth revisiting if the SDK grows date-only decoding.

### Goal C — View sections

`Brainstorm+/Features/Projects/ProjectDetailView.swift`:

- New `tasksSection` / `dailyLogsSection` / `weeklySummariesSection` rendered through shared `enrichmentCard(title:subtitle:errorMessage:content:)` helper with:
  - title + optional count subtitle
  - per-section error banner (`Couldn't load: …`) when `enrichmentErrors[.section]` is set
  - per-section empty line (`No tasks for this project yet.` etc.) when result is empty and no error
  - compact preview lists capped at 8 / 5 / 3 rows with `"+ N more"` footer
- Tasks row: title + `Status · Priority` with colour-coded dot via `taskStatusColor(_:)` and `Self.humanize(_:)` (`in_progress` → `In Progress`).
- Daily logs row: date string + content + optional blockers.
- Weekly summaries row: `Week of <weekStart>` + summary + optional highlights.
- `ownerMetaRow(project:)` rewrites the owner row to prefer `viewModel.owner?.fullName`.
- `foundationScopeNote` rewritten — no longer claims tasks / daily / weekly are deferred; now lists only the genuinely-deferred: editing, member management, AI summary, risk analysis, linked actions, resolution feedback.
- `deniedStateView` unchanged; still full-screen; comment updated to record enrichment is cleared on denied.

### `.projects` implementation status

Remains `.partial`. Promoting to `.implemented` would overstate parity because CRUD, member picker, AI summary, risk analysis, linked risk actions, and resolution feedback are all still missing. 1.7 closes Winston 1.6 audit §4.2 ("Cross-Module Detail Is Still Missing") and §4.3 ("Owner Profile Join Still Missing") but adds no editing / AI / risk surface.

## Ledger

- `progress.md` retitled to Sprint 1.7; captures deliverables, skills used, and remaining gaps.
- `findings.md` replaced with 1.7 scope; detail-delta and list-delta tables updated; `Owner profile join`, `Tasks sub-list`, `Recent daily logs`, `Weekly summaries`, `Per-section failure isolation` rows flipped to **Delivered (1.7)**.
- `task_plan.md` marks `1.7 Projects Owner Profile Join + Detail Enrichment Foundation completed` and next-step Winston 1.7 audit.
- This notes file at `docs/parity/29-winston-ready-1.7-notes.md`.

## Skills

- `planning-with-files` — single coordinated ledger pass across findings / progress / task_plan / notes.
- `verification-before-completion` — independent `rg` scan + `xcodebuild` before claiming done.
- `systematic-debugging` — read Web `fetchProjectDetail()` in `BrainStorm+-Web/src/lib/actions/projects.ts` line-by-line to mirror the four parallel queries; verified Swift SDK `.contains(_:value:)` + `PostgrestFilterValue` Array conformance at `SourcePackages/checkouts/supabase-swift/Sources/PostgREST/PostgrestFilterBuilder.swift:332` and `.../PostgrestFilterValue.swift:41`; verified `JSONDecoder.supabase()` date decoding at `supabase-swift/Sources/Helpers/Codable.swift:16-28` — only handles ISO8601 with/without fractional seconds, so `date` / `week_start` modeled as `String`.
- `receiving-code-review` — Winston 1.6 audit §4.2 and §4.3 are the exact gaps 1.7 closes.
- `supabase-postgres-best-practices` substituted by in-repo SDK pattern review — `.select("id, field1, field2")` + `.eq(_:value:)` + `.contains(_:value:)` + `.order(_:ascending:)` + `.limit(_:)` + `.in(_:values:)`. Skill file not present under `~/.claude/skills/`.
- `ios-development-best-practices` and `native-data-fetching` skill files not present under `~/.claude/skills/` — substituted by in-repo patterns: `@MainActor` `ObservableObject`, `@Environment(SessionManager.self)`, `@StateObject` view-model ownership, `async let` fan-out, per-section error capture via `[EnrichmentSection: String]`, `Color.Brand` tokens, `Outfit`/`Inter` fonts.

## Prohibited Things NOT Done

- No create / update / delete project flows added.
- No member picker / membership management UI.
- No AI summary / risk analysis / linked risk actions / resolution feedback UI.
- No nested-join decode in the core `Project` model — owner join delivered via companion DTO + separate batched query.
- No nested `profiles:assignee_id(full_name)` / `profiles:user_id(full_name)` joins on task / daily / weekly sub-lists (would require per-section batched `.in("id", [...])` — deliberately out of scope for 1.7).
- No avatar rendering (URL fetched but not rendered).
- No `task_count` on list card.
- Database schema untouched.
- No string-primary routing reintroduced.
- No existing working destinations (`.tasks`, `.daily`, `.weekly`, `.schedules`, `.attendance`, `.chat`, `.knowledge`, `.notifications`, `.payroll`, `.settings`) downgraded.
- `.projects` not promoted to `.implemented`.
- No hard-coded admin user id / role. No fake local mocks substituted for real `SessionManager` / `project_members` / `profiles` / `tasks` / `daily_logs` / `weekly_reports` data.
- Navigation architecture not rewritten — 1.5 / 1.6 list → detail wiring preserved intact.
- No bypass / regression of 1.6 detail membership gate — enrichment runs strictly after `.admin` / `.member` resolution; `.denied` path clears all enrichment via `applyDeniedState()`.

## Verification

- Scan executed per prompt §4.1:

  ```bash
  cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
  rg -n 'profiles:owner_id|owner_id|full_name|avatar_url|ProjectOwner|ProjectDetail|ProjectTask|daily_logs|weekly_reports|project_ids|fetchDetail\(|project_members|AccessOutcome|created_at|week_start|ProjectDetailViewModel|ProjectDetailView|ProjectListViewModel|projects' Brainstorm+ progress.md findings.md task_plan.md
  ```

  Expected to confirm:
  - `ProjectDetailModels.swift` defines `ProjectOwnerSummary` / `ProjectTaskSummary` / `ProjectDailyLogSummary` / `ProjectWeeklySummary`.
  - `ProjectDetailViewModel.fetchDetail(role:userId:)` references `project_members`, `project_id`, `user_id`, `AccessOutcome`; `loadEnrichment` references `owner_id`, `tasks`, `daily_logs`, `weekly_reports`, `week_start`, `project_ids`, `created_at`.
  - `ProjectDetailView` references `tasksSection` / `dailyLogsSection` / `weeklySummariesSection` / `ownerMetaRow` / `enrichmentCard`.
  - `ProjectListViewModel` references `ownersById`, `refreshOwnersForCurrentProjects`, `profiles`, `full_name`, `avatar_url`, `created_at` (still), `updated_at` absent from the main `projects` query.
  - `ProjectCardView` references `ProjectOwnerSummary`, `owner`, `ownerByline`.
  - Ledger files record owner join + detail enrichment without overclaiming (`.projects` still `.partial`; deferred list: CRUD / members UI / AI / risk / linked actions / resolution feedback / avatar / `task_count` / nested sub-list profiles join).

- Build executed per prompt §4.2:

  ```bash
  cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
  xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
  ```

  Expected result: `** BUILD SUCCEEDED **`.

## Remaining Debt (Honest)

- **Client vs server guard** (unchanged from 1.5 / 1.6) — iOS admin / membership checks run client-side against `SessionManager.currentProfile`. Real enforcement is Supabase RLS. The iOS 1.7 detail enrichment is a UX / data-fetch shaping layer, not a standalone enforcement surface.
- **`maybeSingle()` absent in Swift SDK** — iOS membership gate still uses `.select("id")` + empty-rows check (unchanged from 1.6).
- **Nested-join decode** — iOS owner hydration runs as a separate `.in("id", ownerIds)` batch (list) and a single-row profile fetch (detail) rather than a nested Supabase select. Semantically equivalent for display; future round may revisit if SDK ergonomics improve.
- **Avatar rendering** — owner `avatar_url` is fetched but not rendered; list / detail currently show name only.
- **Nested profiles on tasks / daily_logs / weekly_reports** — Web joins `profiles:assignee_id(full_name)` and `profiles:user_id(full_name)` for these sub-lists; iOS deliberately did not add N+1 lookups in 1.7 to keep enrichment costs bounded. Can be added with a second batched `profiles.in("id", [...])` call per section if needed.
- **Date-only decode** — `daily_logs.date` and `weekly_reports.week_start` modeled as `String` because the SDK's default decoder rejects `YYYY-MM-DD`. UI formats with the raw string.
- **CRUD / members UI / AI / risk / linked actions / resolution feedback** remain deferred.
- **`task_count`** on list card is not fetched.
- **`filteredProjects` retained** on the list as defensive smoother — a subsequent round may remove it.
- **Nested `NavigationStack`** in `ProjectListView` still present (inherited from 1.3 pattern; 1.4 / 1.5 / 1.6 / 1.7 all confirm detail doesn't compound it).
- 13 modules still on `ParityBacklogDestination`.
- Assignee picker still deferred from 1.1.

## Recommendation

建议进入 Winston 1.7 审计.
