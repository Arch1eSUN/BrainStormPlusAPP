# 33 Winston Ready — 1.9 Projects Edit + Member Management Foundation Notes

**Round:** `1.9 Projects Edit + Member Management Foundation`
**Prompt:** `devprompt/1.9-projects-edit-member-management-foundation.md`
**Date:** 2026-04-16
**Model:** Claude Opus 4.6

## Goal Recap

1. **Native project edit foundation** — at least one real edit entry (target both list + detail), form covering `name` / `description` / `start_date` / `end_date` / `status` / `progress`, real Supabase update, list + detail refresh on save, explicit error state on failure.
2. **Member management foundation** — visible current member state, add / remove via Web `member_ids` semantics, reuse `profiles` picker via a single batched fetch (no N+1), owner protection.
3. **State truth / access / failure isolation** — do not regress 1.5 list membership scoping, 1.6 detail membership gate, 1.7 owner hydrate, 1.8 nested-name + avatar rendering; save / picker failures must NOT pollute unrelated read-only sections; clear loading / disabled state during save; basic validation (name non-empty, progress clamped 0...100).
4. **Ledger truth** — `.projects` stays `.partial`; deltas recorded honestly.
5. Do NOT expand into project delete / AI summary / risk analysis / linked risk actions / resolution feedback / `task_count` / large UI redesign / schema changes.

## What Was Delivered

### Goal A — Native project edit foundation

**New VM** — `Brainstorm+/Features/Projects/ProjectEditViewModel.swift`:

- `@MainActor ObservableObject` seeded from an initial `Project`.
- Form state: `@Published` `name`, `descriptionText`, `status`, `progress`, `includeStartDate`/`startDate`, `includeEndDate`/`endDate`.
- Save state: `isSaving`, `errorMessage` (reserved for the save surface).
- `isSaveEnabled = !trimmedName.isEmpty && !isSaving` — trimmed-non-empty name required; Save button disabled otherwise.
- `save() async -> Project?`:

  ```swift
  let refreshed: Project = try await client
      .from("projects")
      .update(payload)
      .eq("id", value: projectId)
      .select()
      .single()
      .execute()
      .value
  ```

  `payload: ProjectUpdatePayload` — narrow Encodable with `encodeIfPresent` Optional semantics. Unset `description` / `startDate` / `endDate` fields OMIT from the JSON body, mirroring Web's `|| undefined` pattern. PostgREST leaves those columns untouched rather than NULLing them.
- `updated_at` written as ISO8601 string to mirror Web `new Date().toISOString()`.
- `startDate` / `endDate` serialized as `String?` in `YYYY-MM-DD` UTC via a POSIX `DateFormatter` inside the payload — the Supabase Swift SDK's default `Date` encoder emits ISO8601 with time, which a Postgres `date` column would coerce with potential TZ drift; avoided here by explicit pre-encoding matching Web's `<input type="date">` wire format.
- Progress clamped 0...100 both by the Slider's `in: 0...100` range and again pre-payload.

**New sheet** — `Brainstorm+/Features/Projects/ProjectEditSheet.swift`:

- SwiftUI `NavigationStack > Form`.
- Sections:
  - **Project Details**: name TextField + multi-line description TextField (`axis: .vertical`, `lineLimit(3...6)`).
  - **Schedule**: Toggle + DatePicker pairs for start + end, with an inline parity hint "Untoggling a date leaves the saved value unchanged (matches web behavior)".
  - **Status & Progress**: Picker across 5 `Project.ProjectStatus` cases + custom Slider with `in: 0...100, step: 1` and live percentage readout.
  - **Members**: see Goal B.
- Toolbar: Cancel (`.navigationBarLeading`, disabled during save) + Save (`.navigationBarTrailing`, disabled when `!isSaveEnabled`).
- `.overlay { if isSaving { Color.black.opacity(0.35) + ProgressView }}` blocks accidental taps during save.
- Error row (only rendered when `errorMessage != nil`) in `Color.Brand.warning`.
- `onSaved: (Project) -> Void` closure injected by caller; fires on successful save, then sheet dismisses.

**Detail entry** — `Brainstorm+/Features/Projects/ProjectDetailView.swift`:

- New `@State private var isShowingEditSheet: Bool = false`.
- New `private let onProjectUpdated: ((Project) -> Void)?` + extended `public init(viewModel:onProjectUpdated:)` (default nil).
- New toolbar `.topBarTrailing` button (`Image(systemName: "pencil")`, `.accessibilityLabel("Edit project")`) gated behind `accessOutcome != .denied && project != nil` so non-member readers blocked by the 1.6 gate can't even see an edit affordance.
- `.sheet(isPresented: $isShowingEditSheet) { ProjectEditSheet(client: supabase, project: ..., onSaved: { refreshed in onProjectUpdated?(refreshed); Task { await reload() } }) }`.
- On save, detail re-runs its own `fetchDetail` AND propagates the refreshed project to the parent list via the new closure.
- `foundationScopeNote` text updated to remove "editing, member management" from the deferred list (those are now delivered).

**List entry** — `Brainstorm+/Features/Projects/ProjectListView.swift`:

- New `@State private var projectBeingEdited: Project? = nil`. Identifiable binding so rapid row-switching creates a fresh sheet + VM each time (not a stale one).
- Row-level `.contextMenu { Button("Edit", systemImage: "pencil") { projectBeingEdited = project } }` — long-press the row surfaces a secondary edit entry.
- `.sheet(item: $projectBeingEdited) { project in ProjectEditSheet(client: supabase, project: project, onSaved: { _ in Task { await reload() } }) }`.
- NavigationLink's `ProjectDetailView(...)` now receives `onProjectUpdated: { _ in Task { await reload() } }` so detail-initiated edits also refresh the list.

### Goal B — Member management foundation

**New DTO** — `Brainstorm+/Features/Projects/ProjectMemberCandidate.swift`:

```swift
public struct ProjectMemberCandidate: Identifiable, Codable, Hashable {
    public let id: UUID
    public let fullName: String?
    public let avatarUrl: String?
    public let role: String?
    public let department: String?
    // ... snake_case CodingKeys, displayName helper
}
```

Narrow feature-local DTO mirroring Web `fetchAllUsersForPicker()` select shape — `id, full_name, avatar_url, role, department`. Kept separate from core `Profile` to preserve the "one fetch, one shape" 1.7 pattern and avoid decoder failures on sparse rows.

**Batched picker load** — `ProjectEditViewModel.load()`:

- Parallel `async let` fan-out of:
  - `runCandidatesFetch()` → `profiles.select("id, full_name, avatar_url, role, department").eq("status", "active").order("full_name")` — ONE call, not N+1.
  - `runMembersFetch()` → `project_members.select("user_id").eq("project_id", projectId)` — ONE call.
- Results fold into `candidates`, `selectedMemberIds`, `originalMemberIds`.
- Owner id forcibly inserted into `selectedMemberIds` whether or not the member fetch succeeds.
- Picker-fetch failure → `candidatesErrorMessage` (isolated from `errorMessage`) + soft banner inside the Members section. In-progress form edits NOT wiped.

**Per-page picker cost:** `2` PostgREST round-trips to open the sheet, independent of candidate count. Explicitly **NOT N+1**.

**Toggle + search:**

- `toggleMember(_ id:)` short-circuits on owner id.
- `filteredCandidates` computed property filters `candidates` by `full_name` / `department` / `role` case-insensitive substring — client-side, no extra round-trips.

**Member rewrite** — `ProjectEditViewModel.rewriteMembers()`, runs only when `candidatesErrorMessage == nil && selectedMemberIds != originalMemberIds`:

```swift
if let ownerId {
    _ = try await client
        .from("project_members")
        .delete()
        .eq("project_id", value: projectId)
        .neq("user_id", value: ownerId)
        .execute()
}
let newMembers = selectedMemberIds
    .filter { id in if let ownerId { return id != ownerId }; return true }
    .map { uid in ProjectMemberInsert(project_id: projectId, user_id: uid, role: "member") }
if !newMembers.isEmpty {
    _ = try await client.from("project_members").insert(newMembers).execute()
}
```

Mirrors Web `updateProject`'s member rewrite step exactly: delete-everyone-except-owner, insert-all-except-owner. Delete gated on `ownerId != nil` so a missing owner doesn't nuke the last membership row (matches Web's `if (ownerId)` guard).

### Owner protection (three layers)

1. **VM toggle layer**: `toggleMember(_ id:)` short-circuits when `id == ownerId`.
2. **UI layer**: member row `.disabled(isOwner || viewModel.isSaving)` + "Owner" capsule badge.
3. **Wire layer**: `rewriteMembers` uses `.neq("user_id", ownerId)` for delete AND filters ownerId out of the insert list.

Additionally, `selectedMemberIds` always contains ownerId (force-inserted in `load()` even when member fetch fails) so the VM model never represents an owner-deselected state.

### Goal C — State truth / access / failure isolation

- Edit-sheet access gated on `accessOutcome != .denied && project != nil` (detail) — non-member users blocked by the 1.6 gate never see the edit affordance.
- Error surfaces isolated:
  - `errorMessage` → save failures only.
  - `candidatesErrorMessage` → picker failures only.
  - Read-only enrichment state from 1.7 / 1.8 (`profilesById`, `tasks`, `dailyLogs`, `weeklySummaries`, `enrichmentErrors`, avatars) — NOT touched by edit flow.
- `isSaving` drives `.disabled` on every input (TextFields, Toggles, DatePickers, Pickers, Slider, member rows, Cancel button, Save button); dimmed overlay prevents accidental background taps.
- Save success → `onSaved(refreshed)` fires, sheet dismisses, caller reloads. Save failure → sheet stays open, error row visible, user can retry.
- Partial-success case: project update succeeds but member rewrite fails → `errorMessage` set to "Project saved, but member update failed: ..."; save still returns the refreshed project so list/detail still reload.
- 1.5 list membership scoping, 1.6 detail membership gate, 1.7 owner hydrate, 1.8 nested profile join + avatar rendering: all intact. The 1.9 change set touches no existing ViewModel code paths.
- Validation: name trimmed-non-empty required; progress clamped 0...100 at slider bounds and again pre-payload.

### Web parity mapping

Web `updateProject(id, updates)` in `BrainStorm+-Web/src/lib/actions/projects.ts`:

```ts
const res = await supabase.from('projects')
  .update({ ...projectUpdates, updated_at: new Date().toISOString() })
  .eq('id', id)
  .select(`*, profiles:owner_id(full_name, avatar_url)`)
  .single()
if (member_ids !== undefined) {
  const ownerId = res.data?.owner_id
  if (ownerId) {
    await supabase.from('project_members').delete()
      .eq('project_id', id).neq('user_id', ownerId)
  }
  const newMembers = member_ids.filter(uid => uid !== ownerId)
    .map(uid => ({ project_id: id, user_id: uid, role: 'member' }))
  if (newMembers.length) await supabase.from('project_members').insert(newMembers)
}
```

iOS 1.9:

- Project update: same column set, same `updated_at` clock, same `.eq('id', id)`. iOS `.select()` does NOT nest `profiles:owner_id(...)` because the sheet returns just the `Project` row; caller reloads the list / detail to re-hydrate owner via the 1.7 batched `ownersById` / `fetchOwner` path. Architecturally different, semantically equivalent.
- Member rewrite: same delete-then-insert sequence, same owner guard, same owner-excluded insert filter. Extra iOS guard: rewrite skipped if picker fetch failed.

Web `fetchAllUsersForPicker()`:

```ts
.from('profiles').select('id, full_name, avatar_url, role, department')
  .eq('status', 'active').order('full_name')
```

iOS mirrors the exact select list, filter, and order.

### `.projects` implementation status

Remains `.partial`. Promoting would overstate parity because project delete, AI summary, risk analysis, linked risk actions, resolution feedback, and `task_count` on list are all still missing. 1.9 closes edit + member-management gaps — not full Projects parity.

## Ledger

- `progress.md` retitled to Sprint 1.9; captures deliverables, skills used, and remaining gaps.
- `findings.md` replaced with 1.9 scope; detail-delta and list-delta tables flip edit-capability, member-picker, member-update, owner-protection, list-row-edit-entry, and list-refresh-after-save rows to **Delivered (1.9)**. Still-deferred (delete, AI summary, risk analysis, linked risk actions, resolution feedback, `task_count`) honestly recorded.
- `task_plan.md` marks `1.9 Projects Edit + Member Management Foundation completed` and next-step Winston 1.9 audit.
- This notes file at `docs/parity/33-winston-ready-1.9-notes.md`.

## Skills

- `planning-with-files` — single coordinated ledger pass across findings / progress / task_plan / notes after code settled.
- `verification-before-completion` — independent `rg` scan + interim + final `xcodebuild` before claiming done.
- `systematic-debugging` — read Web `updateProject(id, updates)` + `fetchAllUsersForPicker()` in `BrainStorm+-Web/src/lib/actions/projects.ts` line-by-line, plus `showEdit` / `handleUpdateProject` in `BrainStorm+-Web/src/app/dashboard/projects/page.tsx`, to understand exactly which columns get written, in what order the delete-then-insert member rewrite runs, and how owner protection is enforced on the server side. Confirmed the PostgREST `|| undefined` pattern maps onto Swift's synthesized Codable `encodeIfPresent` for Optional fields.
- `receiving-code-review` — Winston 1.8 audit's forward-guidance called out edit + member management as the highest-value remaining Projects gap; 1.9 closes that gap without expanding into AI / risk / delete.
- `supabase-postgres-best-practices` substituted by in-repo SDK pattern review — `.select(...)` + `.eq(_:value:)` + `.neq(_:value:)` + `.in(_:values:)` + `.update(_:).select().single()` + `.delete()` + `.insert([rows])`. Skill file not present under `~/.claude/skills/`.
- `ios-development-best-practices` and `native-data-fetching` skill files not present under `~/.claude/skills/` — substituted by in-repo patterns: `@MainActor` `ObservableObject`, `@StateObject` view-model ownership inside the sheet, `@Environment(\.dismiss)` for sheet close, `.sheet(item:)` identifiable binding so rapid row-switching creates a fresh VM, parallel `async let` + `Result<_, Error>` for dual picker/member fetch, narrow feature-local DTOs (`ProjectMemberCandidate`, `ProjectUpdatePayload`, `ProjectMemberInsert`), `Color.Brand` tokens, `Outfit`/`Inter` fonts.

## Prohibited Things NOT Done

- **No project delete flow.** 1.9 explicitly scope-controlled.
- **No create-flow redesign.**
- **No AI summary / risk analysis / linked risk actions / resolution feedback UI.**
- **No `task_count` on list card.**
- **No N+1 picker queries.** Per-sheet cost is exactly 2 PostgREST round-trips (candidates + current members), independent of candidate count.
- **No owner removal path.** Three-layer owner protection: VM short-circuit + UI disabled row + wire-layer `.neq('user_id', ownerId)` + owner-excluded insert filter.
- **No fake local save.** Every save goes through real Supabase `projects.update(...).select().single()`.
- **No database schema changes.**
- **No string-primary routing reintroduced.**
- **No existing working destination downgraded** (`.tasks`, `.daily`, `.weekly`, `.schedules`, `.attendance`, `.chat`, `.knowledge`, `.notifications`, `.payroll`, `.settings`).
- **`.projects` NOT promoted to `.implemented`.**
- **No hard-coded admin user id / role.** No fake mocks substituted for real `SessionManager` / `project_members` / `profiles` / `tasks` / `daily_logs` / `weekly_reports` data.
- **No bypass of 1.5 list membership scoping** — `ProjectListViewModel` untouched.
- **No bypass of 1.6 detail membership gate** — `ProjectDetailViewModel` untouched; edit toolbar gated on `accessOutcome != .denied`.
- **No regression to 1.7 / 1.8 read-only enrichment** — `profilesById`, `tasks`, `dailyLogs`, `weeklySummaries`, avatar rendering all preserved exactly as 1.8 certified.
- **Save / picker failure does NOT pollute unrelated read-only sections** — errors live on isolated `errorMessage` / `candidatesErrorMessage` surfaces.

## Verification

- Scan executed per prompt §4.1:

  ```bash
  cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
  rg -n 'updateProject|fetchProjectMembers|fetchAllUsersForPicker|member_ids|owner_id|project_members|ProjectDetailView|ProjectListView|sheet|Dialog|progress|status|start_date|end_date|name|description|save|retry|isSaving|selectedMemberIds|profiles|full_name|avatar_url|AccessOutcome|fetchDetail\(|fetchProjects\(' Brainstorm+ progress.md findings.md task_plan.md
  ```

  Expected to confirm:
  - `ProjectMemberCandidate.swift` defines the narrow picker DTO.
  - `ProjectEditViewModel.swift` references `project_members`, `owner_id`, `profiles`, `full_name`, `avatar_url`, `selectedMemberIds`, `isSaving`, `save`, `retry`-path (`errorMessage`), `member_ids`-equivalent rewrite.
  - `ProjectEditSheet.swift` references `sheet`, `Save`/`Cancel` toolbar, `isSaveEnabled`, `ProgressView` overlay, Members section with `toggleMember`.
  - `ProjectDetailView.swift` references `ProjectEditSheet`, `isShowingEditSheet`, `onProjectUpdated`, toolbar pencil button gated by `accessOutcome`.
  - `ProjectListView.swift` references `projectBeingEdited`, `.contextMenu` "Edit", `.sheet(item:)`, `onProjectUpdated` passthrough to detail.
  - Ledger files record edit + member management without overclaiming (`.projects` still `.partial`; deferred list: delete, AI summary, risk analysis, linked risk actions, resolution feedback, `task_count`).

- Build executed per prompt §4.2:

  ```bash
  cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
  xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
  ```

  Expected result: `** BUILD SUCCEEDED **`.

## Remaining Debt (Honest)

- **Client vs server guard** (unchanged from 1.5 / 1.6 / 1.7 / 1.8) — iOS admin / membership checks run client-side against `SessionManager.currentProfile`. Real enforcement is Supabase RLS. The iOS 1.9 edit gate + member rewrite is a UX / data-shaping layer, not a standalone enforcement surface.
- **`maybeSingle()` absent in Swift SDK** — iOS membership gate still uses `.select("id")` + empty-rows check (unchanged from 1.6).
- **Nested-join decode** — iOS still runs batched `.in("id", values: ids)` hydrates rather than true nested Supabase selects for owner (1.7) and sublist profiles (1.8). The edit update uses `.select().single()` flat; caller reloads to re-hydrate owner.
- **Avatar caching** — `AsyncImage` doesn't persist across view lifecycle (unchanged from 1.8).
- **Date-only decode** — `daily_logs.date` and `weekly_reports.week_start` still modeled as `String` (unchanged from 1.7).
- **Untoggle-date semantics** — untoggling a date in the sheet leaves the saved value unchanged (matches Web `|| undefined`); it does NOT clear the column. Documented inline in the sheet as a small hint.
- **Save-state cache coherence** — list + detail refresh via full reload after save. A later round may replace the reload with in-place row patching once we trust the server echo is authoritative for all fields.
- **Partial-success save** — if project update succeeds but member rewrite fails, the sheet reports "Project saved, but member update failed: ..." and dismisses via `onSaved(refreshedProject)`. A later round may redesign this into a two-step progress / retry-member-only affordance.
- **`task_count`** on list card is not fetched.
- **Project delete / AI / risk / linked actions / resolution feedback** remain deferred.
- **`filteredProjects` retained** on the list as defensive smoother — a subsequent round may remove it.
- **Nested `NavigationStack`** in `ProjectListView` still present (inherited from 1.3 pattern; 1.4 / 1.5 / 1.6 / 1.7 / 1.8 / 1.9 all confirm detail + edit sheet don't compound it).
- **Assignee picker** still deferred from 1.1 — 1.9 added project-level edit, not task-level assignee editing.
- 13 modules still on `ParityBacklogDestination`.

## Recommendation

建议进入 Winston 1.9 审计.
