# 23 Winston Ready — 1.4 Projects Filter + Detail Foundation Notes

**Round:** `1.4 Projects Filter + Detail Foundation`
**Prompt:** `devprompt/1.4-projects-filter-detail-foundation.md`
**Date:** 2026-04-16
**Model:** Claude Opus 4.6

## Goal Recap
1. Advance iOS `ProjectListView` from bare list to minimum-usable filter foundation (search + status).
2. Introduce a real, enterable `ProjectDetailView` foundation — not full Web detail parity.
3. Keep `.projects` honestly at `.partial`.
4. Do NOT expand into CRUD / members / AI / risk / cross-module detail.

## What Was Delivered

### Goal A — Projects list filter foundation
`Brainstorm+/Features/Projects/ProjectListViewModel.swift`:
- Added `@Published var searchText: String = ""`.
- Added `@Published var statusFilter: Project.ProjectStatus? = nil`.
- Added derived `filteredProjects: [Project]` that combines case-insensitive substring match on `name` with optional equality match on `status`.

`Brainstorm+/Features/Projects/ProjectListView.swift`:
- Uses `.searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search projects")` — native SwiftUI.
- Toolbar status filter `Menu` with options All / Planning / Active / On Hold / Completed / Archived (exactly matching `Project.ProjectStatus`).
- Renders `viewModel.filteredProjects` instead of raw `viewModel.projects`.
- New sub-empty state "No matches" for the case where filters hide every row but the underlying list is populated.

**Filter semantics, intentionally client-side for foundation scope.** Web does `ilike('name', %q%)` and `eq('status', s)` server-side. iOS 1.4 fetches with the existing `.select()` call and filters in-memory. The gap is documented explicitly in `findings.md` and `progress.md`, and is deliberate because widening to server-side filtering would risk breaking membership-scoping assumptions that iOS does not yet implement.

### Goal B — Project detail foundation
`Brainstorm+/Features/Projects/ProjectDetailViewModel.swift` (new):
- Seeds from tapped row's `Project`, then calls `fetchDetail()` on entry.
- `fetchDetail()` uses `client.from("projects").select().eq("id", value: project.id).single().execute().value` — a real re-fetch, not row re-display.
- Scope comment in the file states explicitly that this is the `projects` row only — not Web `fetchProjectDetail()`'s cross-module tasks / daily_logs / weekly_reports / AI / risk / profile joins.

`Brainstorm+/Features/Projects/ProjectDetailView.swift` (new):
- Renders: name, status badge, start / end / created-at (when present), owner id (raw UUID — owner profile join is deferred), progress bar, optional description.
- `.task { await fetchDetail() }` + `.refreshable`.
- Error state is an inline banner — doesn't blank the screen because the seeded row stays rendered.
- Includes a foundation-scope footer note so end users understand the screen is partial.
- **Does NOT wrap in `NavigationStack`** — this directly addresses Winston 1.3 audit §4.4 ("NavigationStack Layering Should Be Watched"). Navigation is inherited from the list's stack via `NavigationLink`.

### Goal C — List → Detail wiring
`ProjectListView` row is now:
```swift
NavigationLink {
    ProjectDetailView(
        viewModel: ProjectDetailViewModel(
            client: supabase,
            initialProject: project
        )
    )
} label: {
    ProjectCardView(project: project)
        .padding(.horizontal, 20)
}
.buttonStyle(.plain)
```

### `.projects` implementation status
Remains `.partial`. Filter is client-side (not server-side), membership scoping is absent, detail omits Web's task/log/summary/AI/risk joins and the membership gate. Promoting to `.implemented` would materially misrepresent parity.

## Ledger
- `progress.md` retitled to Sprint 1.4; captures deliverables, skills used, and remaining gaps.
- `findings.md` replaced with 1.4 scope with explicit filter-delta and detail-delta tables vs Web.
- `task_plan.md` marks `1.4 Projects Filter + Detail Foundation completed` and next-step Winston 1.4 audit.
- This notes file added at `docs/parity/23-winston-ready-1.4-notes.md`.

## Skills
- `planning-with-files` — single coordinated ledger pass.
- `verification-before-completion` — independent `rg` scan + `xcodebuild` before claiming done.
- `systematic-debugging` — read Web `BrainStorm+-Web/src/lib/actions/projects.ts` to determine filter and detail parity boundaries before writing Swift.
- `receiving-code-review` — 1.3 audit flagged §4.2 "no search / status filter yet", §4.3 "no detail screen yet", §4.4 nested-NavigationStack watchpoint. 1.4 addresses §4.2, §4.3, and the detail half of §4.4 (detail view has no inner `NavigationStack`). The list's own inner `NavigationStack` is kept for now, matching `TaskListView` / `KnowledgeListView`.
- Skills `ios-development-best-practices` and `native-data-fetching` are not present under `~/.claude/skills/`. Substituted by following established in-repo iOS patterns: `@MainActor` `ObservableObject`, `@StateObject` view-model ownership, `.task`/`.refreshable`, `Color.Brand` tokens, `Outfit`/`Inter` fonts, `.searchable` native SwiftUI, `.eq(_:value:).single()` single-row Supabase fetch already used in `Settings` and `Session` managers.

## Prohibited Things NOT Done
- No create / update / delete project flows added.
- No member picker / membership management.
- No AI summary / risk analysis / linked actions / resolution feedback UI.
- Database schema untouched.
- No string-primary routing reintroduced.
- No existing working destinations (`.tasks`, `.daily`, `.weekly`, `.schedules`, `.attendance`, `.chat`, `.knowledge`, `.notifications`, `.payroll`, `.settings`) downgraded.
- `.projects` not promoted to `.implemented`.

## Verification
- Scan executed per prompt §4.1:
```
rg -n 'ProjectDetailView|ProjectDetailViewModel|search|searchable|statusFilter|ProjectStatus|NavigationLink|onTapGesture|fetchProjectDetail|ProjectListView|ProjectListViewModel|projects' Brainstorm+ progress.md findings.md task_plan.md
```
  Confirmed:
  - `ProjectDetailView` + `ProjectDetailViewModel` live under `Brainstorm+/Features/Projects/`.
  - `.searchable` is wired to `viewModel.searchText`; `statusFilter` is used in both view model and view.
  - `NavigationLink { ProjectDetailView(...) }` is present in the list.
  - `ProjectListView` / `ProjectListViewModel` unchanged for routing surface.
  - `fetchProjectDetail` (Web symbol) appears only in `findings.md`/notes as a reference; no iOS code claims to reproduce it fully.
- Build executed per prompt §4.2:
```
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
```
  Result: `** BUILD SUCCEEDED **`.

## Remaining Debt (Honest)
- Projects: server-side filter semantics, membership scoping, owner profile join, cross-module detail (tasks / daily_logs / weekly_reports), CRUD, members, AI summary, risk analysis, linked actions, resolution feedback.
- Nested `NavigationStack` inside `ProjectListView` still present from 1.3 pattern.
- 13 modules still on `ParityBacklogDestination`.
- Assignee picker still deferred from 1.1.

## Recommendation
建议进入 Winston 1.4 审计.
