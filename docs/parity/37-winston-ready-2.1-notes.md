# Winston-Ready Notes — Sprint 2.1 (Projects Task Count List Parity)

**Execution model**: Claude Opus 4.6.
**Build status**: `** BUILD SUCCEEDED **` on `iPhone 17 Pro Max`, `CODE_SIGNING_ALLOWED=NO`.
**Audit target**: `docs/parity/38-winston-audit-2.1.md` (to be written by Winston).

## 1. Round Scope

Close the next narrow Projects list-card parity gap flagged by Winston 2.0 audit:

- **Task count on list card** — 1.3 through 2.0 shipped Projects list + scoping + owner join + avatar + edit + member + delete without ever surfacing a per-project task count.
- **Web source-of-truth discrepancy** — Web's `Project` TypeScript interface declares `task_count?: number` but `fetchProjects()` does NOT select it and the Projects list page does NOT render it. 2.1 records this as an explicit source-of-truth discrepancy and delivers the minimum auditable iOS foundation (devprompt §3.A path 3): a batched aggregate so the iOS list can meaningfully display a count without waiting for Web to be changed first.

Explicitly **out of scope** (devprompt §3.D):

- AI summary, risk analysis, linked risk actions, resolution feedback.
- Create/edit/delete/member redesign.
- Task CRUD from the list, analytics, schema changes, new columns/indexes/views, RLS changes.
- Status-filtered counts (e.g. "3 open / 5 done"), locale-aware pluralization.

## 2. Web Source of Truth Re-read

### 2.1 `BrainStorm+-Web/src/lib/actions/projects.ts`

```ts
// line 22 — declared on the interface
export interface Project {
  // …
  task_count?: number
}

// lines 66-69 — fetchProjects() select
let query = adminDb
  .from('projects')
  .select('*, profiles:owner_id(full_name, avatar_url)')
  .order('created_at', { ascending: false })
// ↑ NO task_count, NO nested tasks(count) aggregate
```

### 2.2 `BrainStorm+-Web/src/app/dashboard/projects/page.tsx`

Card markup (lines 451-491) renders: owner + end date + progress bar + status badge. **No** JSX expression references `task_count`.

### 2.3 Key observations

- `task_count` is a **vestigial typed field** on Web: declared on the TS interface but never populated over the wire, never rendered in the DOM.
- Parity ledger (through 2.0) treats "task count on list card" as a known Projects gap anyway — mirroring expected UX, not current Web behavior.
- Devprompt §3.A path 3 applies exactly: "If Web UI does not actually display task count but parity docs/ledger mark it as a gap, record source-of-truth discrepancy and ship the minimum auditable foundation: batched `tasks` count by project ids for list card display."
- Deliberate consequence: **iOS is ahead of Web on this list-card capability by design**, not by accident. A future Web-side round can realign by adding a nested `tasks(count)` aggregate to `fetchProjects()` or a Postgres computed `task_count` view.

## 3. iOS 2.1 Deliverables

### 3.1 View-model additions

`ProjectListViewModel.swift`:

- `@Published public var taskCountsByProject: [UUID: Int] = [:]` — keyed by `project.id`.
- `@Published public var taskCountsErrorMessage: String? = nil` — isolated from `errorMessage` (list fetch), `ownersErrorMessage` (owner hydrate), and `deleteErrorMessage` (destructive action).
- Private `TaskProjectIdRow: Decodable { let projectId: UUID }` DTO — minimal wire payload (no task bodies).
- Private `func refreshTaskCountsForCurrentProjects() async`:
  - Single batched `.from("tasks").select("project_id").in("project_id", values: projectIds).execute().value`.
  - Initializes every project id at `0` so "no tasks" → "0 tasks" (not a hidden label).
  - Groups returned rows via `counts[row.projectId, default: 0] += 1`.
  - Gated on `!projectIds.isEmpty`.
  - On failure: clears `taskCountsByProject`, sets `taskCountsErrorMessage`; does NOT touch `projects`, `errorMessage`, `ownersById`, `deleteErrorMessage`.
- `fetchProjects(...)` calls `await refreshTaskCountsForCurrentProjects()` after `refreshOwnersForCurrentProjects()`, inside the same `do` block.
- Both no-membership early-returns (missing `userId`, empty `memberProjectIds`) also clear `taskCountsByProject = [:]` + `taskCountsErrorMessage = nil`, matching the existing 1.7 `ownersById` cleanup pattern.

### 3.2 Card additions

`ProjectCardView.swift`:

- New `public let taskCount: Int?`. `nil` = "unknown / failed" → label hidden. `0` = "resolved, zero tasks" → label shown as "0 tasks".
- Extended init: `public init(project: Project, owner: ProjectOwnerSummary? = nil, taskCount: Int? = nil)` — additive default so existing construction sites outside `ProjectListView` compile unchanged.
- Label rendered in existing bottom HStack between end-date and progress:

```swift
if let taskCount {
    Label(Self.taskCountLabel(taskCount), systemImage: "checklist")
        .font(.custom("Inter-Medium", size: 12))
        .foregroundColor(Color.Brand.textSecondary)
}
```

- Helper: `private static func taskCountLabel(_ count: Int) -> String { count == 1 ? "1 task" : "\(count) tasks" }`.
- No change to `statusBadge`, `progress`, owner byline, avatar, title, description, or card layering.

### 3.3 List wiring

`ProjectListView.swift`:

- NavigationLink label construction now passes `taskCount: viewModel.taskCountsByProject[project.id]`. Dictionary subscript returns `Int?`, which matches `ProjectCardView.taskCount`'s expected type and semantics directly.
- No other changes: search / status filter / context menu (edit + delete from 1.9/2.0) / confirmation dialog / alert / NavigationLink `onProjectUpdated` + `onProjectDeleted` closures untouched.

### 3.4 Files NOT modified

- `Brainstorm+/Core/Models/Project.swift` — unchanged. `Project` stays flat; `task_count` NOT added to decoded model because Web doesn't populate it. Treating it as view-model-owned keeps the shape aligned with Web's actual wire format.
- `ProjectDetailModels.swift`, `ProjectDetailViewModel.swift`, `ProjectDetailView.swift` — unchanged. Detail view already lists tasks directly; a scalar count there would be redundant.
- `ProjectEditViewModel.swift`, `ProjectEditSheet.swift`, `ProjectMemberCandidate.swift` — unchanged.
- `Brainstorm+/Shared/Navigation/AppModule.swift` — unchanged; `.projects` stays `.partial`.
- Database schema — untouched.

### 3.5 Parity checklist

| Requirement (devprompt §6) | Delivered | Evidence |
|---|---|---|
| Task count surfaced on list card | Yes | `ProjectCardView.taskCount` rendered when non-nil |
| Batched non-N+1 fetch | Yes | Single `.from("tasks").select("project_id").in("project_id", values: projectIds)` round-trip |
| Initialize all ids at 0 so "0 tasks" renders | Yes | Loop `for id in projectIds { counts[id] = 0 }` before grouping |
| Isolated failure surface | Yes | `taskCountsErrorMessage` separate from `errorMessage`/`ownersErrorMessage`/`deleteErrorMessage` |
| Failure does not clobber list | Yes | Catch only clears `taskCountsByProject` + sets `taskCountsErrorMessage` |
| No-membership paths clear count state | Yes | Both early-returns reset `taskCountsByProject` + `taskCountsErrorMessage` |
| Source-of-truth discrepancy recorded | Yes | `findings.md` §"Web source-of-truth discrepancy (explicit)" + `progress.md` Goal A |
| 1.5–2.0 preserved | Yes | No regression to scope / ordering / owner hydrate / avatar / edit / delete paths |
| Ledger updated | Yes | `findings.md` + `progress.md` + `task_plan.md` + this file |
| `.projects` still `.partial` | Yes | `AppModule.swift` unchanged |
| Scan complete | Yes | See §4.1 |
| Build passes | Yes | See §4.2 |

## 4. Verification

### 4.1 Scan

Ran the devprompt §4.1 pattern across the Projects feature folder:

```bash
rg -n 'task_count|taskCount|taskCounts|tasksCount|count\(|head:|ProjectCardView|ProjectListViewModel|ProjectListView|ownersErrorMessage|deleteErrorMessage|errorMessage|projects|tasks|AppModule|implementationStatus' Brainstorm+/Features/Projects
```

Counts per file (foundation scope intact; no stray references):

- `ProjectMemberCandidate.swift`: unchanged 1.9 file.
- `ProjectDetailModels.swift`: unchanged.
- `ProjectListView.swift`: 2.1 adds one `taskCount:` argument on the NavigationLink label.
- `ProjectListViewModel.swift`: 2.1 adds `taskCountsByProject`, `taskCountsErrorMessage`, `TaskProjectIdRow`, `refreshTaskCountsForCurrentProjects()`, and two no-membership cleanup branches.
- `ProjectEditSheet.swift`: unchanged 1.9 file.
- `ProjectDetailViewModel.swift`: unchanged 2.0 file.
- `ProjectEditViewModel.swift`: unchanged 1.9 file.
- `ProjectCardView.swift`: 2.1 adds `taskCount: Int?`, init default, bottom-HStack label, and `taskCountLabel(_:)` helper.
- `ProjectDetailView.swift`: unchanged 2.0 file.

Total: 207 occurrences across 9 files.

### 4.2 Build

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  CODE_SIGNING_ALLOWED=NO
```

Result: `** BUILD SUCCEEDED **`.

## 5. What 2.1 Did NOT Do (By Design)

- **AI summary / risk analysis / linked risk actions / resolution feedback** — all still web-only. 2.1 did not expand into these surfaces.
- **Task CRUD from the list** — out of scope.
- **Status-filtered counts** (e.g. "3 open / 5 done") — 2.1 counts ALL tasks. Simpler total-tasks semantics matches foundation posture.
- **Locale-aware pluralization** — simple English "1 task" / "N tasks". Localization pass belongs with broader iOS i18n.
- **Auto-refresh on task create/delete elsewhere in iOS** — 2.1 hydrates counts as part of `fetchProjects()`. User sees updates on next pull-to-refresh / tab re-visit. Foundation-acceptable.
- **Flat `task_count` on `Project` decoded model** — not added. Web doesn't populate `task_count`, so mirroring Web would yield permanent `nil`. Treating count as view-model enrichment keeps `Project` aligned with Web's actual wire format.
- **Nested `tasks(count)` Supabase select** — not used. Kept to batched `.in("project_id", values:)` aggregate with client-side grouping, matching the 1.7/1.8 hydrate idiom. Nested-select upgrade deferred to a later SDK-capability round.
- **Schema changes** — none.
- **Nested `NavigationStack` refactor** — 1.3-era nested stack still present; 2.1's card-label change does not compound it.

## 6. Known Debt Carried Forward

- **Source-of-truth divergence** — iOS list card now shows task count; Web does not. Recorded honestly in `findings.md`. Realignment is a Web-side follow-up (nested `tasks(count)` select or Postgres computed column).
- Client-side `AccessOutcome` + enrichment rely on client-side role normalization (same caveat as 1.5 / 1.6 / 1.7 / 1.8 / 1.9 / 2.0). Real enforcement is Supabase RLS.
- `maybeSingle()` absent in the Swift SDK — iOS membership gate still uses `.select("id")` + empty-rows check.
- Avatar caching via `AsyncImage` doesn't persist across view lifecycle.
- Date-only decode modeled as `String` because SDK's default decoder rejects `YYYY-MM-DD`.
- Save-state cache coherence on edit still uses full reload; delete + task-count hydrate use local mutation where semantics allow.
- `filteredProjects` retained as defensive smoother.
- Assignee picker still deferred from 1.1.
- Confirmation-dialog race from 2.0 persists (acceptable foundation posture).
- Task-count query scaling: at very large per-project task volumes the aggregate pulls all `project_id` values. Future optimization deferred.
- Status-filtered counts deferred.
- Locale-aware pluralization deferred.

## 7. Recommended Next Round (Hypothesis, not commitment)

- **AI summary foundation** — Web ships a `/api/ai/project-summary` flow surfaced on the Projects detail page; iOS does not. A narrow iOS foundation (button → request → read-only display, no editing, no persistence) would be the next minimum auditable gap.
- Alternatives Winston may prefer: risk analysis foundation (pulls in a Risk entity shape decision, bigger than summary), resolution feedback (smallest but depends on risk-analysis scaffolding), or realigning Web by adding a nested `tasks(count)` aggregate server-side (cross-stack, closes the 2.1 discrepancy but doesn't move iOS parity forward).

## 8. Handoff

- Findings: `findings.md`
- Progress: `progress.md`
- Task plan: `task_plan.md`
- Winston-ready notes: this file
- Expected audit output: `docs/parity/38-winston-audit-2.1.md`

建议进入 Winston 2.1 审计.
