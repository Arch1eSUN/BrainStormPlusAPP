# 21 Winston Ready — 1.3 Projects List Foundation Notes

**Round:** `1.3 Projects List Foundation`
**Prompt:** `devprompt/1.3-projects-list-foundation.md`
**Date:** 2026-04-16
**Model:** Claude Opus 4.6

## Goal Recap
Establish a real, Supabase-backed Projects list foundation and wire `AppModule.projects` typed routing off `ParityBacklogDestination`. Do NOT deliver full Web Projects parity.

## What Was Delivered

### Goal A — Projects list foundation
Three new files in `Brainstorm+/Features/Projects/`:

1. `ProjectListViewModel.swift`
   - `@MainActor` `ObservableObject` — matches existing `TaskListViewModel` / `KnowledgeListViewModel` pattern.
   - `fetchProjects()` uses shared `supabase` client: `client.from("projects").select().order("updated_at", ascending: false).execute().value`.
   - Exposes `projects: [Project]`, `isLoading: Bool`, `errorMessage: String?`.
   - Reuses existing `Project` model at `Brainstorm+/Core/Models/Project.swift` — no duplicate type.

2. `ProjectCardView.swift`
   - Row: name, optional description (2-line truncation), status badge, optional end date, progress bar.
   - Status badge maps `Project.ProjectStatus` (planning / active / on_hold / completed / archived) to labels and `Color.Brand` colors, matching Web `STATUS_CFG` status set.
   - Uses existing `Outfit-SemiBold` / `Inter-*` fonts and `Color.Brand.paper|text|textSecondary|primary|primaryLight|warning` tokens.

3. `ProjectListView.swift`
   - `NavigationStack`, navigation title "Projects".
   - `if viewModel.isLoading && viewModel.projects.isEmpty` → `ProgressView`.
   - `else if let error = errorMessage, projects.isEmpty` → retry-able error card.
   - `else if projects.isEmpty` → "No projects yet" empty state card.
   - `else` → `ScrollView` + `LazyVStack` of `ProjectCardView`s.
   - `.refreshable { await fetchProjects() }` and `.task { await fetchProjects() }` initial load — matches `KnowledgeListView` pattern.

### Goal B — Typed routing
`Brainstorm+/Features/Dashboard/ActionItemHelper.swift` now contains:

```swift
case .projects:
    ProjectListView(viewModel: ProjectListViewModel(client: supabase))
```

No regression on existing `.tasks`, `.daily`, `.weekly`, `.schedules`, `.attendance`, `.chat`, `.knowledge`, `.notifications`, `.payroll`, `.settings` cases. No string-primary routing reintroduced.

### `AppModule.implementationStatus`
Kept `.projects` as `.partial`. The list foundation is real, but Web Projects has create / update / delete / detail / members / activity / AI summary / risk analysis / resolution feedback — none of which are implemented on iOS. Promoting to `.implemented` would be dishonest. `.partial` remains more accurate. See `findings.md` scope boundaries table.

### Goal C — Ledger truth
Updated:
- `progress.md` — now titled `Sprint 1.3 (Projects List Foundation)` with completed + blocked lists.
- `findings.md` — replaced with 1.3 coverage (`11/24` modules typed, `13/24` still backlog) and explicit scope-boundaries table listing every Web Projects capability that was NOT delivered.
- `task_plan.md` — appended `1.3 Projects List Foundation completed` and updated next step to Winston 1.3 audit.
- This notes file created at `docs/parity/21-winston-ready-1.3-notes.md`.

## Skills Used
- `planning-with-files` — all ledger edits followed a single planned pass.
- `verification-before-completion` — independent `rg` scan + `xcodebuild` run before claiming done.
- `systematic-debugging` — traced existing Supabase fetch pattern in `TaskListViewModel.fetchProjects()` (which reads the same `projects` table) and reused it, rather than inventing a new access pattern.
- `receiving-code-review` — Winston 1.2 audit (`docs/parity/20-winston-audit-1.2.md`) named `.projects` as a remaining debt; 1.3 responds directly.
- Skill `ios-development-best-practices` is not present under `~/.claude/skills/`. Substituted by following established in-repo iOS patterns: `@MainActor` `ObservableObject`, `@StateObject` view-model ownership in `View`, `.task {}` initial-load, `.refreshable {}` pull-to-refresh, `Color.Brand.*` tokens, `Outfit`/`Inter` fonts.

## Prohibited Things NOT Done
- Did not fabricate full Projects CRUD.
- Did not touch database schema.
- Did not delete or downgrade existing Tasks / Dashboard / Notifications routing.
- Did not reintroduce string-primary routing on Dashboard paths.
- Did not promote `.projects` to `.implemented`.
- Did not build out OKR / Deliverables / Approvals / Admin.

## Verification

### Scan
Ran the scan from §4.1 of the prompt (see `build-verification.log` below for build portion):

```
rg -n 'ProjectListView|ProjectListViewModel|case \.projects|ParityBacklogDestination|implementationStatus|projects' Brainstorm+ progress.md findings.md task_plan.md
```

Result confirmed:
- `ProjectListView` / `ProjectListViewModel` defined in `Brainstorm+/Features/Projects/`.
- `case .projects:` present in `Brainstorm+/Features/Dashboard/ActionItemHelper.swift` mapping to `ProjectListView`.
- `ParityBacklogDestination` still referenced only as the default fallback in `ActionItemHelper` and as the placeholder definition in `DashboardView.swift` — NOT used by `.projects` anymore.
- `implementationStatus` for `.projects` remains `.partial` in `AppModule.swift`.
- `progress.md`, `findings.md`, `task_plan.md` all mention the new 1.3 work truthfully.

### Build
Ran:

```
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
```

Result: `** BUILD SUCCEEDED **`.

## Remaining Debt (Honest)
- 13 modules still on `ParityBacklogDestination`.
- Projects parity beyond list: detail screen, create / update / delete, member picker, status / search filters, AI summary, risk analysis, linked risk actions, resolution feedback — all deferred.
- Assignee picker from 1.1 still deferred.
- Legacy `destination(for title: String)` deprecated path still exists; not used on Dashboard main paths per 1.2 audit.

## Recommendation
建议进入 Winston 1.3 审计.
