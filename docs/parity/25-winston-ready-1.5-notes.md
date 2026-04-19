# 25 Winston Ready — 1.5 Projects Server-Side Filter + Membership Scope Foundation Notes

**Round:** `1.5 Projects Server-Side Filter + Membership Scope Foundation`
**Prompt:** `devprompt/1.5-projects-server-side-filter-membership-scope-foundation.md`
**Date:** 2026-04-16
**Model:** Claude Opus 4.6

## Goal Recap

1. Push Projects list `search` + `status` filters from client-side to server-side (Web parity: `ilike('name', %q%)`, `eq('status', s)`).
2. Introduce non-admin **membership scoping** against `project_members` (Web parity: admin sees all, non-admin scoped to their membership rows, no-membership → empty list).
3. Preserve existing 1.4 filter UX and detail foundation.
4. Keep `.projects` honestly at `.partial`.
5. Do NOT expand into CRUD / members / AI / risk / cross-module detail.

## What Was Delivered

### Goal A — Server-side filter foundation

`Brainstorm+/Features/Projects/ProjectListViewModel.swift`:

- New signature: `fetchProjects(role: PrimaryRole?, userId: UUID?) async`.
- `searchText` (whitespace-trimmed, non-empty) now produces `.ilike("name", pattern: "%\(q)%")` on the Supabase query. Mirrors Web `src/lib/actions/projects.ts` line 89:

  ```ts
  if (filters?.search) query = query.ilike('name', `%${filters.search}%`)
  ```

- `statusFilter` non-nil now produces `.eq("status", value: statusFilter.rawValue)`. Mirrors Web line 88:

  ```ts
  if (filters?.status) query = query.eq('status', filters.status)
  ```

- Supabase Swift SDK call-site verified against `supabase-swift/Sources/PostgREST/PostgrestFilterBuilder.swift:194` (`ilike(_:pattern:)`) and `:309` (`in(_:values:)`). `UUID` conforms to `PostgrestFilterValue` (`PostgrestFilterValue.swift:29`).

### Goal B — Membership scope foundation

`Brainstorm+/Features/Projects/ProjectListViewModel.swift`:

- Admin predicate `isAdmin(role:)` mirrors Web `isAdmin` in `BrainStorm+-Web/src/lib/rbac.ts:166` — true for `admin / superadmin / chairperson / super_admin`.
- On iOS, `RBACManager.migrateLegacyRole(profile.role)` is the single normalization surface. It folds legacy `super_admin` into canonical `.superadmin`, so the iOS predicate compares against the three canonical `PrimaryRole` values.
- Admin path: single `from("projects").select()` with optional `.eq`/`.ilike` — no scoping. `scopeOutcome = .admin`.
- Non-admin path — two phases:
  1. `from("project_members").select("project_id").eq("user_id", value: userId)` → decoded into `[MembershipRow]` then flattened to `[UUID]`.
  2. Empty → `projects = []`, `scopeOutcome = .noMembership`, **no second query**. Mirrors Web early-return:

     ```ts
     if (memberProjectIds.length === 0) return { data: [] as Project[], error: null }
     ```

  3. Non-empty → `from("projects").select().in("id", values: memberProjectIds)` + filters + `order("updated_at", ascending: false)`. `scopeOutcome = .member`.
- Non-admin with no `userId` (profile not yet hydrated) → empty + `.noMembership`. Refuses to fall back to `projects.select()` without scope.

**No hard-coded admin user id. No local role mock. Identity is strictly `SessionManager.currentProfile`.**

### Goal C — ViewModel / state truth

`ProjectListViewModel.ScopeOutcome`:

```swift
public enum ScopeOutcome: Equatable {
    case unknown
    case admin
    case member
    case noMembership
}
@Published public var scopeOutcome: ScopeOutcome = .unknown
```

`Brainstorm+/Features/Projects/ProjectListView.swift`:

- Adds `@Environment(SessionManager.self) private var sessionManager`.
- Centralized `reload()` helper calls `viewModel.fetchProjects(role:userId:)` with derived identity (`RBACManager.shared.migrateLegacyRole(sessionManager.currentProfile?.role).primaryRole`, `sessionManager.currentProfile?.id`).
- Re-fetch triggers:
  - `.task` — initial load
  - `.refreshable` — pull-to-refresh
  - `.onChange(of: viewModel.statusFilter)` — discrete choice, immediate re-fetch
  - `.onSubmit(of: .search)` — user pressed Search on keyboard (single committed query)
  - `.onChange(of: viewModel.searchText)` when value becomes empty — handles the `.searchable` X-clear affordance
- Empty-state disambiguation:
  - `scopeOutcome == .noMembership` → new `noMembershipStateView` ("No accessible projects / admin can add you from Web")
  - `projects.isEmpty && hasActiveFilter` → `filteredEmptyStateView` ("No matches")
  - `projects.isEmpty && !hasActiveFilter` → `emptyStateView` ("No projects yet")

Existing 1.4 UX is intact: `.searchable`, toolbar status menu, `NavigationLink` into `ProjectDetailView`, all still work.

### `.projects` implementation status

Remains `.partial`. Cross-module detail joins, detail membership gate, owner profile join, CRUD, member picker, AI, risk are all still missing. 1.5 advances only the list data-fetching semantics. Promoting to `.implemented` would materially misrepresent parity.

## Client-side `filteredProjects` — retained, justified

With 1.5 the server is authoritative. `filteredProjects` is a **thin defensive display-layer smoother** kept for:

1. Resilience if a server-side filter regresses or returns a superset during a fetch race.
2. Instant visual feedback while a new `.ilike` query is in flight.

It is NOT a Web parity claim. Subsequent rounds may remove it once the server-side semantics are broadly exercised.

## Ledger

- `progress.md` retitled to Sprint 1.5; captures deliverables, skills used, and remaining gaps.
- `findings.md` replaced with 1.5 scope with explicit filter/scope-delta tables vs Web.
- `task_plan.md` marks `1.5 Projects Server-Side Filter + Membership Scope Foundation completed` and next-step Winston 1.5 audit.
- This notes file at `docs/parity/25-winston-ready-1.5-notes.md`.

## Skills

- `planning-with-files` — single coordinated ledger pass across findings / progress / task_plan / notes.
- `verification-before-completion` — independent `rg` scan + `xcodebuild` before claiming done.
- `systematic-debugging` — read Web `fetchProjects()` in `BrainStorm+-Web/src/lib/actions/projects.ts` and `isAdmin()` in `BrainStorm+-Web/src/lib/rbac.ts:166` line-by-line, then aligned iOS predicate and two-phase query semantics exactly.
- `receiving-code-review` — Winston 1.4 audit §4.3 "Client-Side Filter Is Not Web Parity" is the exact gap 1.5 closes for the list path.
- `supabase-postgres-best-practices` substituted by in-repo SDK verification — inspected `PostgrestFilterBuilder.swift:194` (`ilike`) / `:309` (`in`), `PostgrestFilterValue.swift:29` (UUID conformance). Skill file not present under `~/.claude/skills/`.
- `ios-development-best-practices` and `native-data-fetching` skill files not present under `~/.claude/skills/` — substituted by in-repo `@MainActor` `ObservableObject` + `.task` / `.refreshable` / `.onChange` / `.onSubmit(of: .search)` SwiftUI patterns matching `TaskListView` and `KnowledgeListView`.

## Prohibited Things NOT Done

- No create / update / delete project flows added.
- No member picker / membership management UI.
- No AI summary / risk analysis / linked actions / resolution feedback UI.
- No detail enrichment (tasks / daily logs / weekly reports / owner profile join) touched.
- Database schema untouched.
- No string-primary routing reintroduced.
- No existing working destinations (`.tasks`, `.daily`, `.weekly`, `.schedules`, `.attendance`, `.chat`, `.knowledge`, `.notifications`, `.payroll`, `.settings`) downgraded.
- `.projects` not promoted to `.implemented`.
- No hard-coded admin user id / role. No fake local mocks substituted for real `SessionManager` / `project_members` data.

## Verification

- Scan executed per prompt §4.1:

  ```
  cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
  rg -n 'fetchProjects\(|searchText|statusFilter|ilike|project_members|currentProfile|role|NavigationLink|ProjectDetailView|ProjectListViewModel|ProjectListView|projects' Brainstorm+ progress.md findings.md task_plan.md
  ```

  Confirmed:
  - `ProjectListViewModel.fetchProjects(role:userId:)` references `ilike`, `in`, `project_members`.
  - `ProjectListView` references `sessionManager`, `currentProfile`, `statusFilter`, `searchText`, `.onSubmit(of: .search)`, `.onChange`.
  - `ProjectDetailView` / `ProjectDetailViewModel` unchanged (1.4 foundation intact).
  - `ProjectDetailView` still has no internal `NavigationStack`.
  - Ledger files record server-side filter + membership scope foundation without overclaiming.

- Build executed per prompt §4.2:

  ```
  cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
  xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
  ```

  Result: `** BUILD SUCCEEDED **`.

## Remaining Debt (Honest)

- **Client vs server guard** — iOS enforces admin check client-side from `SessionManager.currentProfile`. The real guard is Supabase RLS. Web additionally uses `serverGuard()` against a session cookie server-side. iOS does not yet have an equivalent.
- **Detail-level membership gate** — `ProjectDetailViewModel.fetchDetail()` still has no membership check; Web `fetchProjectDetail()` rejects non-admin non-members with `'无权访问此项目'`. Only RLS currently blocks unauthorized detail reads on iOS.
- **Owner profile join** — list / card rows still show owner as a raw UUID. Web joins `profiles:owner_id(full_name, avatar_url)`.
- **`task_count`** — not fetched; Web exposes it when present.
- **Order by** — iOS orders by `updated_at DESC`; Web orders by `created_at DESC`. Inherited from 1.3, not introduced by 1.5.
- **Cross-module detail** — tasks / daily_logs / weekly_reports joins remain deferred.
- **CRUD / members UI / AI / risk / resolution feedback** remain deferred.
- **`filteredProjects` retained** as defensive smoother — a subsequent round may remove it.
- **Nested `NavigationStack`** in `ProjectListView` still present (inherited from 1.3 pattern; 1.4 confirmed detail doesn't compound it; 1.5 unchanged).
- 13 modules still on `ParityBacklogDestination`.
- Assignee picker still deferred from 1.1.

## Recommendation

建议进入 Winston 1.5 审计.
