# 27 Winston Ready — 1.6 Projects Detail Membership Gate + Ordering Alignment Foundation Notes

**Round:** `1.6 Projects Detail Membership Gate + Ordering Alignment Foundation`
**Prompt:** `devprompt/1.6-projects-detail-membership-gate-ordering-foundation.md`
**Date:** 2026-04-16
**Model:** Claude Opus 4.6

## Goal Recap

1. Add a real, auditable **detail-level membership gate** to `ProjectDetailViewModel` — admin sees all, non-admin member sees assigned, non-admin non-member denied.
2. Align Projects list ordering from `updated_at DESC` to Web's `created_at DESC`.
3. Preserve 1.4 / 1.5 foundation (list filter + membership scope, detail seeded render, navigation).
4. Keep `.projects` honestly at `.partial`.
5. Do NOT expand into detail enrichment / CRUD / members / AI / risk.

## What Was Delivered

### Goal A — Project detail membership gate foundation

`Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`:

- New signature: `fetchDetail(role: PrimaryRole?, userId: UUID?) async`.
- Admin predicate `isAdmin(role:)` reuses the same three-way switch from 1.5 (`.admin` / `.superadmin` / `.chairperson`). `RBACManager.migrateLegacyRole` has already folded legacy `super_admin` into `.superadmin` before the value reaches this predicate.
- **Admin path**: skip gate → `accessOutcome = .admin` → `.eq("id", value: projectId).single()` fetch. No extra query.
- **Non-admin path**:

  ```swift
  let rows: [MembershipCheckRow] = try await client
      .from("project_members")
      .select("id")
      .eq("project_id", value: projectId)
      .eq("user_id", value: userId)
      .execute()
      .value
  return !rows.isEmpty
  ```

  Empty rows → `project = nil`, `accessOutcome = .denied`, **no subsequent `projects` fetch**. Mirrors Web `BrainStorm+-Web/src/lib/actions/projects.ts`:

  ```ts
  if (!isAdmin(guard.role)) {
    const { data: membership } = await supabase
      .from('project_members').select('id')
      .eq('project_id', projectId).eq('user_id', guard.userId)
      .maybeSingle()
    if (!membership) return { data: null, error: '无权访问此项目' }
  }
  ```

  Non-empty rows → `accessOutcome = .member` → proceed to the single-row `projects` fetch.
- **Missing identity** (non-admin with `userId == nil`, e.g. profile not hydrated yet) → same `.denied` path. Conservative posture — refuses to fall back to the pre-1.6 ungated read.

### `maybeSingle()` substitution

The Supabase Swift SDK at the pinned version does not expose `maybeSingle()`; `single()` enforces exactly one row and throws on zero.

iOS uses a plain `.select("id")` with both `.eq(...)` filters, decoded into `[MembershipCheckRow]`, and checks `rows.isEmpty`. Semantically equivalent to Web's `maybeSingle()` + `!membership`. Documented in `findings.md` as a known minor SDK delta worth migrating if the Swift SDK later exposes `maybeSingle()`.

Confirmed SDK surface via `supabase-swift/Sources/PostgREST/PostgrestTransformBuilder.swift:114` (`public func single() -> PostgrestTransformBuilder`).

### Goal B — Project list ordering alignment

`Brainstorm+/Features/Projects/ProjectListViewModel.swift`:

- `runProjectsQuery(...)` changed from `.order("updated_at", ascending: false)` to `.order("created_at", ascending: false)`. Comment at the call site cross-links to Web source for future auditors.
- Applies to both admin and membership-scoped paths because both funnel through the shared `runProjectsQuery`.
- Mirrors `BrainStorm+-Web/src/lib/actions/projects.ts`:

  ```ts
  .order('created_at', { ascending: false })
  ```

### Goal C — ViewModel / state truth

`ProjectDetailViewModel.AccessOutcome`:

```swift
public enum AccessOutcome: Equatable {
    case unknown
    case admin
    case member
    case denied
}
@Published public var accessOutcome: AccessOutcome = .unknown
```

`project` changed from non-optional to `Project?`. `projectId: UUID` held separately so retry / logging paths know what was requested even after the seed is cleared on `.denied`.

`Brainstorm+/Features/Projects/ProjectDetailView.swift`:

- Added `@Environment(SessionManager.self) private var sessionManager` — same identity source as `ProjectListView`.
- Centralized `reload()` helper calls `viewModel.fetchDetail(role:userId:)` with derived identity.
- `.task` / `.refreshable` both funnel through `reload()`.
- State routing:
  - `.denied` → full-screen `deniedStateView` (lock-shield icon, "Access restricted" copy, workspace-admin hint; NO project field leak).
  - `project == nil && isLoading` → `ProgressView`.
  - `project == nil && errorMessage != nil` → full-screen `errorStateView(message:)` with Retry button.
  - `project != nil` → seeded detail layout (header / metadata / progress / optional description), with transient inline `errorBanner` for refresh failures atop the existing 1.4 UX.
- `navigationTitle` falls back to `"Project"` whenever `project` is not available or `accessOutcome == .denied`, so the nav bar cannot leak a project name into a denied screen.

Existing 1.4 UX preserved: statusBadge, metaRow, progress bar, description, foundation-scope footer note all remain in the seeded detail layout.

### `.projects` implementation status

Remains `.partial`. Detail enrichment (tasks / daily_logs / weekly_reports), owner profile join, CRUD, member picker, AI, risk, linked actions, resolution feedback are all still missing. 1.6 closes Winston 1.5 audit §4.2 (detail gate) and §4.3 (ordering delta) but adds no detail content.

## Ledger

- `progress.md` retitled to Sprint 1.6; captures deliverables, skills used, and remaining gaps.
- `findings.md` replaced with 1.6 scope; detail-delta and list-delta tables updated; `Non-admin membership gate` and `Order by` rows flipped to Delivered.
- `task_plan.md` marks `1.6 Projects Detail Membership Gate + Ordering Alignment Foundation completed` and next-step Winston 1.6 audit.
- This notes file at `docs/parity/27-winston-ready-1.6-notes.md`.

## Skills

- `planning-with-files` — single coordinated ledger pass across findings / progress / task_plan / notes.
- `verification-before-completion` — independent `rg` scan + `xcodebuild` before claiming done.
- `systematic-debugging` — read Web `fetchProjectDetail()` in `BrainStorm+-Web/src/lib/actions/projects.ts` line-by-line, mirrored admin predicate + membership-check branches exactly; verified Swift SDK lacks `maybeSingle()` at the pinned version via `supabase-swift/Sources/PostgREST/PostgrestTransformBuilder.swift:114` inspection.
- `receiving-code-review` — Winston 1.5 audit §4.2 ("Detail Path Still Lacks Membership Gate") and §4.3 ("Ordering Delta Remains") are the exact gaps 1.6 closes.
- `supabase-postgres-best-practices` substituted by in-repo SDK pattern review — `.eq(_:value:)` + `.select("id")` + post-decode `.isEmpty` check. Skill file not present under `~/.claude/skills/`.
- `ios-development-best-practices` and `native-data-fetching` skill files not present under `~/.claude/skills/` — substituted by in-repo patterns: `@MainActor` `ObservableObject`, `@Environment(SessionManager.self)`, `@StateObject` view-model ownership, `.task` / `.refreshable`, `Color.Brand` tokens, `Outfit`/`Inter` fonts.

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
- Navigation architecture not rewritten — the 1.5 list → detail wiring is preserved intact.

## Verification

- Scan executed per prompt §4.1:

  ```
  cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
  rg -n 'fetchProjectDetail|fetchDetail\(|project_members|project_id|user_id|maybeSingle|currentProfile|role|created_at|updated_at|ProjectDetailViewModel|ProjectDetailView|ProjectListViewModel|projects' Brainstorm+ progress.md findings.md task_plan.md
  ```

  Expected to confirm:
  - `ProjectDetailViewModel.fetchDetail(role:userId:)` references `project_members`, `project_id`, `user_id`, `accessOutcome`.
  - `ProjectDetailView` references `sessionManager`, `currentProfile`, `deniedStateView`, `reload()`.
  - `ProjectListViewModel` references `created_at` and no longer references `updated_at`.
  - `maybeSingle` appears in notes / findings as a documented SDK delta only, never in Swift code.
  - Ledger files record detail membership gate foundation + ordering alignment without overclaiming.

- Build executed per prompt §4.2:

  ```
  cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
  xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
  ```

  Expected result: `** BUILD SUCCEEDED **`.

## Remaining Debt (Honest)

- **Client vs server guard** (unchanged from 1.5) — iOS admin / membership checks run client-side against `SessionManager.currentProfile`. Real enforcement is Supabase RLS. The iOS 1.6 detail gate is a UX / data-fetch shaping layer that is as trustworthy as the JWT + RLS behind it.
- **`maybeSingle()` absent in Swift SDK** — iOS substitutes empty-rows check. Semantically equivalent; worth migrating if the SDK later exposes `maybeSingle()`.
- **Owner profile join still missing** — list / card / detail all still display owner as a raw UUID.
- **Cross-module detail** — tasks / daily_logs / weekly_reports joins remain deferred.
- **CRUD / members UI / AI / risk / resolution feedback** remain deferred.
- **`filteredProjects` retained** on the list as defensive smoother — a subsequent round may remove it.
- **Nested `NavigationStack`** in `ProjectListView` still present (inherited from 1.3 pattern; 1.4/1.5/1.6 all confirm detail doesn't compound it).
- 13 modules still on `ParityBacklogDestination`.
- Assignee picker still deferred from 1.1.

## Recommendation

建议进入 Winston 1.6 审计.
