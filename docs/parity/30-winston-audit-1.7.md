# 30 Winston Audit — 1.7 Projects Owner Profile Join + Detail Enrichment Foundation

**Audit Time:** 2026-04-16 16:53 GMT+8  
**Auditor:** Winston  
**Result:** PASS — `1.7 Projects Owner Profile Join + Detail Enrichment Foundation` passes and is certified complete.

## 1. Audit Scope

Audited against:

- `devprompt/1.7-projects-owner-profile-join-detail-enrichment-foundation.md`
- `docs/parity/29-winston-ready-1.7-notes.md`
- `docs/parity/28-winston-audit-1.6.md`
- `progress.md`
- `findings.md`
- `task_plan.md`
- `Brainstorm+/Features/Projects/ProjectDetailModels.swift`
- `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
- `Brainstorm+/Features/Projects/ProjectDetailView.swift`
- `Brainstorm+/Features/Projects/ProjectListViewModel.swift`
- `Brainstorm+/Features/Projects/ProjectListView.swift`
- `Brainstorm+/Features/Projects/ProjectCardView.swift`
- `Brainstorm+/Shared/Navigation/AppModule.swift`
- Web source of truth:
  - `../BrainStorm+-Web/src/lib/actions/projects.ts`
- independent `rg` scan
- independent `xcodebuild`

## 2. Independent Verification

### 2.1 Prompt Scan

Independently ran:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
rg -n 'profiles:owner_id|owner_id|full_name|avatar_url|ProjectOwner|ProjectDetail|ProjectTask|daily_logs|weekly_reports|project_ids|fetchDetail\(|project_members|AccessOutcome|created_at|week_start|ProjectDetailViewModel|ProjectDetailView|ProjectListViewModel|projects' Brainstorm+ progress.md findings.md task_plan.md
```

Confirmed:

- `ProjectDetailModels.swift` defines:
  - `ProjectOwnerSummary`
  - `ProjectTaskSummary`
  - `ProjectDailyLogSummary`
  - `ProjectWeeklySummary`
- `ProjectListViewModel` references:
  - `ownersById`
  - `refreshOwnersForCurrentProjects()`
  - `profiles`
  - `full_name`
  - `avatar_url`
  - `created_at`
- `ProjectDetailViewModel.fetchDetail(role:userId:)` still references:
  - `project_members`
  - `project_id`
  - `user_id`
  - `AccessOutcome`
- `ProjectDetailViewModel` now additionally references:
  - `tasks`
  - `daily_logs`
  - `weekly_reports`
  - `project_ids`
  - `week_start`
  - `enrichmentErrors`
  - `loadEnrichment`
  - `applyDeniedState()`
- `ProjectDetailView` now renders dedicated read-only sections for:
  - tasks
  - recent daily logs
  - weekly summaries
- `updated_at` does not reappear in the main Projects ordering path; it remains only in historical documentation comments.
- Ledger files continue to state `.projects` is `.partial`, not full parity.

### 2.2 Web Source Verification

Independently re-verified Web `fetchProjectDetail(projectId)` in `BrainStorm+-Web/src/lib/actions/projects.ts`.

Confirmed the Web detail query surface still contains:

```ts
adminDb.from('projects')
  .select('*, profiles:owner_id(full_name, avatar_url)')
  .eq('id', projectId)
  .single()

adminDb.from('tasks')
  .select('id, title, status, priority, assignee_id, profiles:assignee_id(full_name)')
  .eq('project_id', projectId)
  .order('created_at', { ascending: false })
  .limit(50)

adminDb.from('daily_logs')
  .select('id, date, content, progress, blockers, profiles:user_id(full_name)')
  .eq('project_id', projectId)
  .order('date', { ascending: false })
  .limit(10)

adminDb.from('weekly_reports')
  .select('id, week_start, summary, highlights, challenges, profiles:user_id(full_name)')
  .contains('project_ids', [projectId])
  .order('week_start', { ascending: false })
  .limit(5)
```

This confirms 1.7 selected the correct next parity target after 1.6: owner profile readability plus read-only detail enrichment.

### 2.3 Build

Independently ran:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
```

Result:

```text
** BUILD SUCCEEDED **
```

## 3. Findings

### 3.1 Goal A — Owner Profile Join Foundation

**Status:** PASS

Verified list path in `ProjectListViewModel`:

- `ownersById: [UUID: ProjectOwnerSummary]`
- `refreshOwnersForCurrentProjects()` batches distinct `ownerId`s through:

```swift
.from("profiles")
.select("id, full_name, avatar_url")
.in("id", values: ownerIds)
```

Verified card wiring in `ProjectListView`:

```swift
owner: project.ownerId.flatMap { viewModel.ownersById[$0] }
```

Verified display logic in `ProjectCardView`:

- priority order is:
  1. `owner.fullName`
  2. `project.ownerId.uuidString`
  3. hidden only if `ownerId == nil`

This is a correct foundation-grade replacement for the prior raw-UUID-only display.

Verified detail path in `ProjectDetailViewModel`:

- `fetchOwner(ownerId:)` reads `profiles.id, full_name, avatar_url`
- result stored in `owner`
- failure captured in `enrichmentErrors[.owner]`
- project base content remains intact

Verified detail render in `ProjectDetailView.ownerMetaRow(project:)`:

- prefers `viewModel.owner?.fullName`
- falls back to raw UUID if join missing / failed

This satisfies the 1.7 owner readability target.

### 3.2 Goal B — Read-Only Detail Enrichment Foundation

**Status:** PASS

Verified four lightweight DTOs in `ProjectDetailModels.swift`:

- `ProjectOwnerSummary`
- `ProjectTaskSummary`
- `ProjectDailyLogSummary`
- `ProjectWeeklySummary`

This is the correct architectural choice here. It avoids mutating core app models to chase nested Web query shapes.

Verified `ProjectDetailViewModel.loadEnrichment(for:)` fans out parallel sub-fetches only after the 1.6 gate passes and the base `projects` row is refreshed:

```swift
async let ownerFetch: Void = fetchOwner(ownerId: project.ownerId)
async let tasksFetch: Void = fetchTasks()
async let dailyFetch: Void = fetchDailyLogs()
async let weeklyFetch: Void = fetchWeeklySummaries()
```

Verified query semantics:

- tasks:
  - `.eq("project_id", value: projectId)`
  - `.order("created_at", ascending: false)`
  - `.limit(50)`
- daily logs:
  - `.eq("project_id", value: projectId)`
  - `.order("date", ascending: false)`
  - `.limit(10)`
- weekly summaries:
  - `.contains("project_ids", value: [projectId.uuidString])`
  - `.order("week_start", ascending: false)`
  - `.limit(5)`

This is materially aligned with Web detail semantics.

### 3.3 Goal C — State Truth / Denied Path Isolation

**Status:** PASS

Most important verification: 1.7 does **not** regress the 1.6 gate.

Confirmed:

- non-admin non-member callers still hit `.denied`
- denied path still clears `project`
- `applyDeniedState()` additionally clears:
  - `owner`
  - `tasks`
  - `dailyLogs`
  - `weeklySummaries`
  - `enrichmentErrors`
- enrichment is not triggered before gate success

This prevents stale or prior-session enrichment from leaking through a denied detail route.

That is the key 1.7 correctness condition, and it is satisfied.

### 3.4 Goal D — View Foundation

**Status:** PASS

Verified `ProjectDetailView` now contains compact read-only sections for:

- `tasksSection`
- `dailyLogsSection`
- `weeklySummariesSection`

Each section has:

- title
- optional count subtitle
- empty state
- preview cap
- `+ N more` footer
- per-section error banner via `enrichmentCard(...)`

This is the right scope level: real data foundation, not overbuilt UI.

### 3.5 Date-Only Decode Handling

**Status:** PASS

The ready notes and code both document an actual Swift SDK constraint:

- `daily_logs.date`
- `weekly_reports.week_start`

are Postgres `date` columns (`YYYY-MM-DD`), while the current decoder path expects ISO8601 datetime strings.

Modeling these fields as `String` in the read-only DTO layer is honest and technically correct at this stage. No false claim of full type parity was made.

### 3.6 Ledger Truth

**Status:** PASS with minor wording caveat

Verified:

- `findings.md` correctly flips owner profile join, tasks, daily logs, and weekly summaries to delivered
- `progress.md` records 1.7 as foundation work, not full Projects parity
- `task_plan.md` now points to Winston 1.7 audit
- `AppModule.projects` remains `.partial`

Minor caveat:

- `docs/parity/29-winston-ready-1.7-notes.md` phrases the owner failure path as an `enrichmentErrors[.owner]` banner, but the actual UI behavior is softer: owner failure is captured in state and the row falls back to UUID; there is no dedicated owner-specific visible banner block in `ProjectDetailView`.

This does **not** fail the round because the prompt only required controlled failure without collapsing detail. That requirement is satisfied. But future notes should describe this more precisely.

## 4. Risk Notes

### 4.1 Client-Side Gate Is Still Not ServerGuard

Unchanged from 1.5 / 1.6:

- iOS role derivation and membership shaping remain client-side UX/data-fetch logic
- true enforcement still depends on Supabase auth + RLS

This does not fail 1.7 because 1.7 did not promise server-side enforcement.

### 4.2 Nested Profile Joins Are Still Missing on Detail Sublists

Web still includes:

- `profiles:assignee_id(full_name)` on tasks
- `profiles:user_id(full_name)` on daily logs
- `profiles:user_id(full_name)` on weekly reports

iOS 1.7 intentionally does not hydrate these names yet.

This is now the most visible remaining read-only detail parity gap.

### 4.3 Avatar Rendering Is Still Missing

iOS now fetches `avatar_url` for owner summaries, but does not render avatar UI in:

- `ProjectCardView`
- `ProjectDetailView`

Not a 1.7 fail, but still a real parity gap.

### 4.4 `task_count` on List Still Missing

Web may expose `task_count` in project list contexts. iOS still does not surface it.

Not a 1.7 fail, but worth tracking.

## 5. Final Verdict

**PASS**

`1.7 Projects Owner Profile Join + Detail Enrichment Foundation` is complete enough to certify.

What was actually delivered and verified:

- owner profile readability on list and detail
- read-only detail enrichment for tasks, recent daily logs, weekly summaries
- no regression of the 1.6 detail membership gate
- enrichment failure isolation
- build success
- ledger remains honest that `.projects` is still `.partial`

What is **not** yet delivered and must not be overstated:

- CRUD
- member management UI
- avatar rendering
- nested sublist profile joins
- AI summary
- risk analysis
- linked actions
- resolution feedback
- full Projects parity

## 6. Next Recommended Round

The next highest-value narrow round is:

**`1.8 Projects Nested Profile Join + Avatar Rendering Foundation`**

Reason:

1. 1.7 already established the read-only sublists.
2. The next most user-visible parity gap is that those sublists still show ids / anonymous context instead of human names.
3. Owner `avatar_url` is already fetched, so rendering owner avatar on card/detail is a contained follow-up.
4. This remains safely within read-only foundation scope and does not explode into CRUD or AI/risk surfaces.

**Recommendation: proceed directly to Winston 1.8 prompt creation.**
