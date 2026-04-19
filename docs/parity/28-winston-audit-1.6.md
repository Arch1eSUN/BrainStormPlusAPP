# 28 Winston Audit — 1.6 Projects Detail Membership Gate + Ordering Alignment Foundation

**Audit Time:** 2026-04-16 16:28 GMT+8  
**Auditor:** Winston  
**Result:** PASS — `1.6 Projects Detail Membership Gate + Ordering Alignment Foundation` passes and is certified complete.

## 1. Audit Scope

Audited against:

- `devprompt/1.6-projects-detail-membership-gate-ordering-foundation.md`
- `docs/parity/27-winston-ready-1.6-notes.md`
- `docs/parity/26-winston-audit-1.5.md`
- `progress.md`
- `findings.md`
- `task_plan.md`
- `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
- `Brainstorm+/Features/Projects/ProjectDetailView.swift`
- `Brainstorm+/Features/Projects/ProjectListViewModel.swift`
- `Brainstorm+/Features/Projects/ProjectListView.swift`
- `Brainstorm+/Shared/Supabase/SessionManager.swift`
- `Brainstorm+/Shared/Security/RBACManager.swift`
- Web source of truth:
  - `../BrainStorm+-Web/src/lib/actions/projects.ts`
  - `../BrainStorm+-Web/src/lib/server-guard.ts`
  - `../BrainStorm+-Web/src/lib/role-migration.ts`
- independent `rg` scan
- independent `xcodebuild`

## 2. Independent Verification

### 2.1 Prompt Scan

Independently ran:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
rg -n 'fetchProjectDetail|fetchDetail\(|project_members|project_id|user_id|maybeSingle|currentProfile|role|created_at|updated_at|ProjectDetailViewModel|ProjectDetailView|ProjectListViewModel|projects' Brainstorm+ progress.md findings.md task_plan.md
```

Confirmed:

- `ProjectDetailViewModel.fetchDetail(role:userId:)` exists and references:
  - `project_members`
  - `project_id`
  - `user_id`
  - `AccessOutcome`
- `ProjectDetailView` resolves identity from `SessionManager.currentProfile` via `RBACManager.migrateLegacyRole(...)`.
- `ProjectDetailView` renders a dedicated denied state and no longer assumes `project` is always present.
- `ProjectListViewModel` now orders by `created_at` and no longer orders by `updated_at`.
- `maybeSingle` appears only in comments / notes as a documented SDK delta, not in Swift implementation.
- Ledger files record 1.6 as detail-gate + ordering-alignment foundation, not full Projects parity.

### 2.2 Web Source Verification

Independently re-verified Web `fetchProjectDetail(projectId)` in `BrainStorm+-Web/src/lib/actions/projects.ts`:

```ts
if (!isAdmin(guard.role)) {
  const { data: membership } = await supabase
    .from('project_members')
    .select('id')
    .eq('project_id', projectId)
    .eq('user_id', guard.userId)
    .maybeSingle()

  if (!membership) {
    return { data: null, error: '无权访问此项目' }
  }
}
```

Also re-verified list ordering source of truth:

```ts
let query = adminDb
  .from('projects')
  .select('*, profiles:owner_id(full_name, avatar_url)')
  .order('created_at', { ascending: false })
```

This confirms the two main 1.6 targets were correctly chosen and correctly compared against Web.

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

### 3.1 Goal A — Detail Membership Gate Foundation

**Status:** PASS

Verified implementation in `ProjectDetailViewModel`:

- New API:

```swift
public func fetchDetail(role: PrimaryRole?, userId: UUID?) async
```

- Admin path:
  - `.admin` / `.superadmin` / `.chairperson` bypass membership check.
  - `accessOutcome = .admin`
  - proceeds to `projects` single-row fetch.

- Non-admin path:
  - requires `userId`
  - checks `project_members` by both `project_id` and `user_id`
  - empty result causes:

```swift
self.project = nil
self.accessOutcome = .denied
isLoading = false
return
```

  - therefore non-member detail callers are no longer app-side allowed through to the `projects` fetch.

This is the key 1.6 requirement, and it is satisfied.

### 3.2 SDK Delta Handling (`maybeSingle()`)

**Status:** PASS

Web uses `maybeSingle()`.

Swift implementation does not fake this and does not claim exact API equivalence. Instead it documents the SDK delta and implements a semantically equivalent pattern:

- `.select("id")`
- scoped by both equality filters
- decode into `[MembershipCheckRow]`
- treat `rows.isEmpty` as denied

This is honest and technically acceptable at current SDK constraints.

### 3.3 Goal B — Ordering Alignment

**Status:** PASS

Verified in `ProjectListViewModel.runProjectsQuery(...)`:

```swift
.order("created_at", ascending: false)
```

This replaces the previous `updated_at DESC` behavior and now matches Web list ordering semantics for both:

- admin path
- membership-scoped path

because both flow through the same helper.

### 3.4 Goal C — ViewModel / State Truth

**Status:** PASS

Verified:

- `ProjectDetailViewModel.project` is now optional, which is necessary to clear seeded data on deny.
- `projectId` is retained independently so denial does not destroy target identity.
- `AccessOutcome` cleanly separates:
  - `.unknown`
  - `.admin`
  - `.member`
  - `.denied`
- `errorMessage` remains distinct from access control state.
- `ProjectDetailView` distinguishes:
  - denied state
  - initial loading
  - first-load error
  - seeded-content + transient refresh error
- `navigationTitle` falls back to `Project` on denied / no project, preventing nav-bar leakage of project name.

This is the right state model for foundation-stage detail access control.

### 3.5 Ledger Truth

**Status:** PASS

Verified `progress.md`, `findings.md`, `task_plan.md`, and `docs/parity/27-winston-ready-1.6-notes.md` are materially honest:

- detail membership gate is recorded as delivered;
- order-by alignment is recorded as delivered;
- `.projects` remains `.partial`;
- cross-module detail, owner profile join, CRUD, members UI, AI, risk, linked actions, resolution feedback remain deferred;
- client-vs-server guard caveat remains documented.

Only minor ledger issue:

- `task_plan.md` still says “Next step is Winston 1.6 audit.”

That is now stale after this audit and should be updated immediately. This is not a round-failing issue.

## 4. Risk Notes

### 4.1 Client-Side Gate Is Still Not ServerGuard

As already documented, iOS is doing app-side shaping, not server-side enforcement. Real security still depends on Supabase auth + RLS.

This does **not** fail 1.6, because 1.6 only promised foundation parity on app-side access semantics. But future parity language must stay precise.

### 4.2 Cross-Module Detail Is Still Missing

Web detail still includes:

- owner profile join
- tasks
- recent daily logs
- weekly summaries

iOS still only re-fetches the `projects` row after the gate passes.

This is now the most valuable remaining Projects detail gap.

### 4.3 Owner Profile Join Still Missing

Web already joins:

```ts
profiles:owner_id(full_name, avatar_url)
```

iOS still shows raw owner UUID. This is user-visible debt and a good candidate for the next round.

### 4.4 `task_plan.md` Needs Post-Audit Sync

The implementation passed, but the plan ledger still points to entering Winston 1.6 audit instead of recording that the audit has completed. Must be corrected in the next sync step.

## 5. Final Verdict

`1.6 Projects Detail Membership Gate + Ordering Alignment Foundation` meets the prompt requirements:

- detail access now has a real, auditable membership gate foundation;
- non-admin non-members no longer pass through to direct detail row fetch;
- admin / member / denied semantics are real and stateful;
- list ordering is aligned to Web `created_at DESC`;
- 1.4 and 1.5 foundations remain intact;
- ledger truth is materially accurate;
- independent scan passed;
- independent build passed.

**Result:** PASS — `1.6 Projects Detail Membership Gate + Ordering Alignment Foundation` is certified complete.

## 6. Recommended Next Formal Round

Recommended next round:

- `1.7 Projects Owner Profile Join + Detail Enrichment Foundation`

Reason:

1. access semantics are now sufficiently closed at list + detail foundation level;
2. the next highest-value visible gap is not more gating, but richer read-only detail parity;
3. Web already exposes owner profile, tasks, recent daily logs, and weekly summaries in detail;
4. this can be advanced without prematurely expanding into CRUD / member management / AI / risk.

Keep 1.7 strictly read-only foundation scope.
