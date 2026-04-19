# 26 Winston Audit — 1.5 Projects Server-Side Filter + Membership Scope Foundation

**Audit Time:** 2026-04-16 16:15 GMT+8  
**Auditor:** Winston  
**Result:** PASS — `1.5 Projects Server-Side Filter + Membership Scope Foundation` passes and is certified complete.

## 1. Audit Scope

Audited against:

- `devprompt/1.5-projects-server-side-filter-membership-scope-foundation.md`
- `docs/parity/25-winston-ready-1.5-notes.md`
- `docs/parity/24-winston-audit-1.4.md`
- `progress.md`
- `findings.md`
- `task_plan.md`
- `Brainstorm+/Features/Projects/ProjectListView.swift`
- `Brainstorm+/Features/Projects/ProjectListViewModel.swift`
- `Brainstorm+/Features/Projects/ProjectDetailView.swift`
- `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
- `Brainstorm+/Shared/Supabase/SessionManager.swift`
- `Brainstorm+/Shared/Security/RBACManager.swift`
- `Brainstorm+/App/BrainStormApp.swift`
- Web source of truth:
  - `../BrainStorm+-Web/src/lib/actions/projects.ts`
  - `../BrainStorm+-Web/src/lib/rbac.ts`
  - `../BrainStorm+-Web/src/lib/server-guard.ts`
  - `../BrainStorm+-Web/src/lib/role-migration.ts`
- independent `rg` scans
- independent `xcodebuild`

## 2. Independent Verification

### 2.1 Build

The pending independent build session completed with:

```text
** BUILD SUCCEEDED **
```

Command audited:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
```

This satisfies the prompt's build requirement.

### 2.2 App Environment Injection

Verified actual app entry:

- `Brainstorm+/App/BrainStormApp.swift` is the active `@main` app.
- It creates a single `@State private var sessionManager = SessionManager()`.
- Authenticated path injects `.environment(sessionManager)` into `MainTabView()`.
- Login path injects the same `sessionManager` into `LoginView()`.
- `.task { await sessionManager.checkSession() }` hydrates auth state and profile before entering the authenticated app path.

This means `ProjectListView`'s `@Environment(SessionManager.self)` can resolve the same app-level session manager. The inactive `Brainstorm_App.swift` has `// @main` commented out and is not the runtime entry.

### 2.3 Web Projects Source Verification

Verified Web `fetchProjects()` in `BrainStorm+-Web/src/lib/actions/projects.ts`:

```ts
const guard = await serverGuard()
const userRole = guard.role
const userId = guard.userId

let query = adminDb
  .from('projects')
  .select('*, profiles:owner_id(full_name, avatar_url)')
  .order('created_at', { ascending: false })

if (!isAdmin(userRole)) {
  const { data: memberships } = await supabase
    .from('project_members')
    .select('project_id')
    .eq('user_id', userId)

  const memberProjectIds = (memberships ?? []).map(m => m.project_id)

  if (memberProjectIds.length === 0) {
    return { data: [] as Project[], error: null }
  }

  query = query.in('id', memberProjectIds)
}

if (filters?.status) query = query.eq('status', filters.status)
if (filters?.search) query = query.ilike('name', `%${filters.search}%`)
```

Verified `isAdmin()` in `BrainStorm+-Web/src/lib/rbac.ts`:

```ts
export function isAdmin(role: Role): boolean {
  return ['admin', 'superadmin', 'chairperson', 'super_admin'].includes(role)
}
```

Important nuance checked: Web `serverGuard()` returns `role: legacyRole`, but Web also has `role-migration.ts`, where `manager` and `team_lead` migrate to `primaryRole: 'admin'`. iOS uses the same migration concept through `RBACManager.migrateLegacyRole(...)`. Therefore iOS treating `manager` / `team_lead` as `.admin` is consistent with the app's broader role-migration model and is not a 1.5 failure.

## 3. Findings

### 3.1 Goal A — Server-Side Filter Foundation

**Status:** PASS

Verified in `ProjectListViewModel.fetchProjects(role:userId:)`:

- `searchText` is trimmed.
- Non-empty search is pushed to Supabase query through:

```swift
query = query.ilike("name", pattern: "%\(trimmedSearch)%")
```

- Non-nil status filter is pushed through:

```swift
query = query.eq("status", value: statusFilter.rawValue)
```

- The server-side filters are applied inside the shared `runProjectsQuery(...)`, so they apply to both:
  - admin full-list path;
  - non-admin membership-scoped path.

`filteredProjects` still exists, but its role is now explicitly documented as a defensive display-layer smoother. The primary fetch semantics are no longer pure client-side filtering.

### 3.2 Goal B — Membership Scope Foundation

**Status:** PASS

Verified implementation:

- Admin path:
  - `PrimaryRole.admin`, `.superadmin`, `.chairperson` bypass membership scoping.
  - Fetches `projects` with optional server-side filters.
  - Sets `scopeOutcome = .admin`.

- Non-admin path:
  - Requires `userId`.
  - Queries `project_members`:

```swift
client
    .from("project_members")
    .select("project_id")
    .eq("user_id", value: userId)
```

  - Empty membership list returns `projects = []`, sets `.noMembership`, and does **not** fall back to `projects.select()`.
  - Non-empty membership list scopes the project query:

```swift
query = query.in("id", values: scopedIds)
```

This satisfies the prompt's requirement that non-admin users no longer read all projects indiscriminately.

### 3.3 Role / Identity Source

**Status:** PASS with foundation caveat

Verified in `ProjectListView`:

```swift
@Environment(SessionManager.self) private var sessionManager

private var primaryRole: PrimaryRole? {
    RBACManager.shared.migrateLegacyRole(sessionManager.currentProfile?.role).primaryRole
}

private var userId: UUID? {
    sessionManager.currentProfile?.id
}
```

This is a real app-side identity source, not a hard-coded role or local mock.

Caveat: this is still client-side role derivation. Web has `serverGuard()` in a server action; iOS does not. Real enforcement still depends on Supabase auth and RLS. This is acceptable for 1.5 foundation, but must remain documented debt.

### 3.4 ViewModel / State Truth

**Status:** PASS

Verified:

- `isLoading` and `errorMessage` remain intact.
- `ScopeOutcome` distinguishes:
  - `.unknown`
  - `.admin`
  - `.member`
  - `.noMembership`
- `ProjectListView` distinguishes:
  - no membership;
  - filtered no-match;
  - truly empty project list;
  - error state;
  - initial loading state.
- Search triggers avoid a query storm:
  - `.onSubmit(of: .search)` submits server-side search.
  - clearing search re-fetches without `ilike`.
  - status changes re-fetch immediately because they are discrete menu selections.
- Existing list → detail `NavigationLink` still works.

### 3.5 Ledger Truth

**Status:** PASS

Verified `progress.md`, `findings.md`, `task_plan.md`, and `docs/parity/25-winston-ready-1.5-notes.md` accurately record:

- server-side `ilike` and `eq` are now implemented for list fetching;
- membership scoping is implemented for Projects list;
- no-membership short-circuit is implemented;
- `.projects` remains `.partial`;
- detail-level membership gate remains missing;
- owner profile join, task count, CRUD, members UI, AI, risk, linked actions, and resolution feedback remain missing;
- iOS order remains `updated_at DESC` while Web uses `created_at DESC`.

No material overclaim found.

## 4. Risk Notes

### 4.1 Client-Side Guard Is Not ServerGuard

iOS now applies a real client-side role/user-derived scope, but it is not equivalent to Web `serverGuard()` as an enforcement boundary.

Required future stance:

- Treat iOS app logic as UX/data-fetch shaping.
- Treat Supabase RLS as the real security boundary.
- Do not claim full authorization parity until RLS policies and detail-level guards are audited.

### 4.2 Detail Path Still Lacks Membership Gate

`ProjectDetailViewModel.fetchDetail()` still fetches a single `projects` row by id and does not replicate Web `fetchProjectDetail()` authorization behavior for non-admin non-members.

Not a 1.5 failure because the prompt scoped this round to list filtering and list membership scoping. But it is now the highest-priority Projects security/parity gap.

### 4.3 Ordering Delta Remains

Web orders Projects by `created_at DESC`; iOS orders by `updated_at DESC`.

This was inherited from prior rounds and documented. It does not fail 1.5, but a future parity cleanup should align ordering or explicitly justify the product difference.

### 4.4 Owner Profile Join Still Missing

Web list query joins `profiles:owner_id(full_name, avatar_url)`; iOS still fetches `projects.*` and displays owner id as raw UUID when shown.

This does not fail 1.5 because owner rendering was explicitly out of scope, but it remains visible product debt.

### 4.5 Nested `NavigationStack` Still Present

`ProjectListView` still owns a `NavigationStack`, inherited from 1.3. `ProjectDetailView` does not add another one.

Not a 1.5 failure, but broader navigation architecture should eventually decide whether feature root views or call sites own navigation stacks.

## 5. Final Verdict

`1.5 Projects Server-Side Filter + Membership Scope Foundation` meets the prompt requirements:

- Search filtering is pushed to server-side `ilike`.
- Status filtering is pushed to server-side `eq`.
- Non-admin Projects list is scoped through `project_members`.
- Non-admin no-membership returns empty instead of leaking all projects.
- Admin path remains unscoped, consistent with Web source.
- Identity is sourced from `SessionManager.currentProfile` and normalized through `RBACManager`, not hard-coded.
- Existing 1.4 search/status/detail UX remains intact.
- Ledger truth is accurate and does not claim full Projects parity.
- `.projects` correctly remains `.partial`.
- Independent build passed.

**Result:** PASS — `1.5 Projects Server-Side Filter + Membership Scope Foundation` is certified complete.

## 6. Recommended Next Formal Round

Recommended next round:

- `1.6 Projects Detail Membership Gate + Ordering Alignment Foundation`

Reason:

1. Detail path is now the most important remaining Projects security/parity gap.
2. Web `fetchProjectDetail()` rejects non-admin non-members; iOS does not yet implement an app-level equivalent.
3. The list path now has membership scoping, but a user who can obtain or retain a project id should not get misleading detail behavior.
4. Ordering alignment (`created_at DESC`) is small and can be included if kept strictly minimal.

Do not expand 1.6 into full detail enrichment, CRUD, AI, risk, or members UI unless explicitly scoped in the next prompt.
