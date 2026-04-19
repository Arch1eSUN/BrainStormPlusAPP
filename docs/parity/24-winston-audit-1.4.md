# 24 Winston Audit — 1.4 Projects Filter + Detail Foundation

**Audit Time:** 2026-04-16 15:42 GMT+8  
**Auditor:** Winston  
**Result:** PASS — `1.4 Projects Filter + Detail Foundation` passes and is certified complete.

## 1. Audit Scope

Audited against:

- `devprompt/1.4-projects-filter-detail-foundation.md`
- `docs/parity/23-winston-ready-1.4-notes.md`
- `docs/parity/22-winston-audit-1.3.md`
- `progress.md`
- `findings.md`
- `task_plan.md`
- `Brainstorm+/Features/Projects/ProjectListView.swift`
- `Brainstorm+/Features/Projects/ProjectListViewModel.swift`
- `Brainstorm+/Features/Projects/ProjectCardView.swift`
- `Brainstorm+/Features/Projects/ProjectDetailView.swift`
- `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
- `Brainstorm+/Core/Models/Project.swift`
- `Brainstorm+/Shared/Navigation/AppModule.swift`
- `Brainstorm+/Features/Dashboard/ActionItemHelper.swift`
- Web Projects source:
  - `../BrainStorm+-Web/src/lib/actions/projects.ts`
  - `../BrainStorm+-Web/src/app/dashboard/projects/page.tsx`
- independent `rg` scan
- independent `xcodebuild`

## 2. Independent Verification

### 2.1 Prompt Scan

Ran:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
rg -n 'ProjectDetailView|ProjectDetailViewModel|search|searchable|statusFilter|ProjectStatus|NavigationLink|onTapGesture|fetchProjectDetail|ProjectListView|ProjectListViewModel|projects' Brainstorm+ progress.md findings.md task_plan.md
```

Confirmed:

- `ProjectDetailView` exists under `Brainstorm+/Features/Projects/`.
- `ProjectDetailViewModel` exists under `Brainstorm+/Features/Projects/`.
- `ProjectListViewModel` includes `searchText`, `statusFilter`, and `filteredProjects`.
- `ProjectListView` wires `.searchable(...)` to `viewModel.searchText`.
- `ProjectListView` exposes a toolbar status filter `Menu` backed by `Project.ProjectStatus`.
- `ProjectListView` renders `viewModel.filteredProjects`, not the raw `projects` array.
- `ProjectListView` wraps each rendered row in `NavigationLink` into `ProjectDetailView`.
- `ProjectDetailViewModel.fetchDetail()` performs a real single-row Supabase re-fetch by project id.
- `ProjectDetailView` does not add a nested `NavigationStack`.
- Ledger files record that this is foundation scope, not full Web Projects parity.

### 2.2 Web Source Verification

Ran source verification against:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+
rg -n 'function fetchProjectDetail|export async function fetchProjectDetail|fetchProjectDetail|ilike\(|eq\(.status|project_members|profiles:owner_id' BrainStorm+-Web/src/lib/actions/projects.ts BrainStorm+-Web/src/app/dashboard/projects/page.tsx
```

Confirmed Web source still includes:

- server-side `ilike('name', ...)` search filtering;
- server-side `eq('status', ...)` filtering;
- non-admin project membership scoping through `project_members`;
- owner profile join via `profiles:owner_id(full_name, avatar_url)`;
- `fetchProjectDetail()` cross-module detail loading for tasks, daily logs, weekly reports, and owner profile data.

This validates the 1.4 ledger claim that iOS is still foundation scope and must remain `.partial`.

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

### 3.1 Goal A — Projects List Filter Foundation

**Status:** PASS

Verified implementation:

- `ProjectListViewModel.searchText` exists.
- `ProjectListViewModel.statusFilter` exists.
- `ProjectListViewModel.filteredProjects` combines:
  - optional exact status equality;
  - case-insensitive substring matching on `project.name`.
- `ProjectListView` uses SwiftUI `.searchable(...)`.
- `ProjectListView` includes status filter options:
  - All statuses;
  - Planning;
  - Active;
  - On Hold;
  - Completed;
  - Archived.
- `ProjectListView` handles no-match state separately from true empty project state.

Scope is correctly described as **client-side foundation**, not Web-equivalent server-side filtering.

### 3.2 Goal B — Project Detail Foundation

**Status:** PASS

Verified implementation:

- `ProjectDetailViewModel` seeds detail state from the selected list row.
- `ProjectDetailViewModel.fetchDetail()` re-fetches the single project row:

```swift
client
    .from("projects")
    .select()
    .eq("id", value: project.id)
    .single()
    .execute()
    .value
```

- `ProjectDetailView` displays:
  - project name;
  - status;
  - start date, when present;
  - end date, when present;
  - owner id, when present;
  - created date, when present;
  - progress;
  - description, when present.
- `ProjectDetailView` supports `.task` initial refresh and `.refreshable` manual refresh.
- refresh errors render as a non-destructive inline banner while seeded detail content remains visible.
- `ProjectDetailView` includes an explicit foundation-scope footer note.
- `ProjectDetailView` does not introduce a nested `NavigationStack`.

This satisfies the prompt's minimum detail foundation requirement.

### 3.3 Goal C — Ledger Truth

**Status:** PASS

Verified ledger files:

- `progress.md`
- `findings.md`
- `task_plan.md`
- `docs/parity/23-winston-ready-1.4-notes.md`

They accurately record:

- filter is client-side in-memory foundation;
- Web uses server-side `ilike` and `eq` filtering;
- iOS has no membership scoping yet;
- iOS detail only re-fetches the `projects` row;
- iOS detail does not include owner profile join, tasks, daily logs, weekly summaries, AI summary, risk analysis, linked risk actions, or resolution feedback;
- `.projects` remains `.partial`.

## 4. Risk Notes

### 4.1 `ProjectListView` Still Owns an Inner `NavigationStack`

`ProjectDetailView` correctly avoids adding its own `NavigationStack`, but `ProjectListView` still wraps its body in `NavigationStack`.

This is not a 1.4 failure because:

- it was inherited from 1.3 patterns;
- the prompt only required detail not to compound the issue;
- build succeeds;
- navigation is wired and type-safe.

However, a future navigation cleanup round should consider whether feature root views should own `NavigationStack` or inherit from the call site consistently.

### 4.2 `task_plan.md` Subsequent Features Text Is Now Coarse

`task_plan.md` still says future Projects parity includes `detail screen` and `status & search filters`, but 1.4 delivered foundation versions of those items.

This is not a fail because the same document also marks `1.4 Projects Filter + Detail Foundation completed`; however, future planning should distinguish:

- foundation delivered;
- full parity still missing.

### 4.3 Client-Side Filter Is Not Web Parity

This is correctly recorded and does not fail 1.4. The remaining parity gap is real:

- Web filters server-side;
- Web membership-scopes non-admin users;
- iOS currently fetches projects directly and filters the loaded array.

## 5. Final Verdict

`1.4 Projects Filter + Detail Foundation` meets the prompt requirements:

- Projects list has a real search + status filter foundation.
- Project detail has a real, enterable foundation.
- List-to-detail navigation is wired.
- Ledger truth is mostly accurate and does not overclaim full parity.
- `.projects` correctly remains `.partial`.
- Independent scan passed.
- Independent build passed.

**Result:** PASS — `1.4 Projects Filter + Detail Foundation` is certified complete.

## 6. Recommended Next Formal Round

Proceed to the next formal development round only after updating `devprompt/README.md`.

Recommended next direction:

- `1.5 Projects Server-Side Filter + Membership Scope Foundation`, or
- `1.5 Projects Detail Enrichment Foundation`.

Do not batch multiple future prompts at once. Follow `devprompt/README.md`: one active round only.
