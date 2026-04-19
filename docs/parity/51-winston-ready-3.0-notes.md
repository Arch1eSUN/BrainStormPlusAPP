# 51 Winston Ready — 3.0 RBAC Infrastructure Web-Parity Foundation

**Round:** `3.0 RBAC Infrastructure Web-Parity Foundation`
**Date:** `2026-04-19`
**Status:** READY — All 9 Tasks (A–I) landed against
`devprompt/3.0-rbac-infrastructure-web-parity-foundation.md`.
**Prompt:** `devprompt/3.0-rbac-infrastructure-web-parity-foundation.md`

## 1. Sprint Scope

3.0 is pure RBAC / auth-plumbing alignment. No feature work. Goal: eliminate the iOS /
Web drift on `PrimaryRole`, `Capability`, legacy-role handling, and the missing
`excluded_capabilities` subtraction — the parity-table Task #12 foundation that gates
3.1 Chat / 3.2 Dashboard Templates / 3.3 Attendance / 3.4 Reporting / 3.5 Copilot.

Web source of truth: `BrainStorm+-Web/src/lib/capabilities.ts` (Phase 2 canonical 3-role
+ 30-capability model) and `BrainStorm+-Web/src/lib/role-migration.ts` (legacy → canonical
mapping). iOS target: `Brainstorm+/Shared/Security/RBACManager.swift` +
`Brainstorm+/Core/Models/Profile.swift`.

Explicitly out of scope (3.0 prompt §2): feature UI work, schema / RLS changes, Web-side
changes, new business flows. Every feature module keeps its existing parity status.

## 2. Web Source-of-Truth Re-Read

### 2.1 `BrainStorm+-Web/src/lib/capabilities.ts` lines 10-132

Canonical 3 primary roles: `'employee' | 'admin' | 'superadmin'`. Phase 1's
`chairperson` was removed from the type union — now handled exclusively by
`role-migration.ts`.

30 capabilities in 5 semantic groups: `职能能力` (3: hr_ops / finance_ops / media_ops),
`审批能力` (11: approval_access + 10 type-specific approvals), `AI 能力` (7), `管理扩展能力`
(4: attendance_admin / leave_quota_admin / ai_evaluation_access / holiday_admin —
**these four were the gap iOS had to close**), `系统治理能力` (5).

`DEFAULT_CAPABILITIES` (lines 71-132):
- `employee: []` — zero defaults; every grant is explicit via profile row.
- `admin: 18 caps` — HR package core (6) + base approvals (4) + admin-as-fallback
  approver (3) + AI chatbot (1) + 管理扩展 (4).
- `superadmin: 30 caps` — every approval cap + every AI cap + every functional cap +
  every governance cap + every 管理扩展 cap. **Note**: 3.0 devprompt said "superadmin =
  29 caps"; Web source at head is 30. iOS mirrors Web.

`getEffectiveCapabilities(primaryRole, assignedCapabilities, excludedCapabilities)` at
lines 152-163: `(defaults ∪ assigned) − excluded`. The `excluded` subtraction is the
new Phase-2 primitive that lets an admin revoke specific caps from a single user
without demoting their role.

### 2.2 `BrainStorm+-Web/src/lib/role-migration.ts` lines 113-139

`migrateLegacyRole(oldRole)` — canonical roles pass through silently. Legacy roles log
a deprecation warning and map:
- `chairperson` → `superadmin`
- `super_admin` → `superadmin` (snake_case legacy alias)
- `manager` → `admin`
- `team_lead` → `admin`
- `hr` → `employee` + derived caps `[hr_ops, approval_access, leave_approval,
  recruitment_approval, ai_resume_screening, ai_interview_entry]`
- `finance` → `employee` + derived caps `[finance_ops, approval_access,
  purchase_approval, expense_approval, reimbursement_approval, ai_finance_docs,
  ai_finance_reports, ai_finance_data_processing]`
- `contractor` / `intern` → `employee` (no derived caps)
- unknown → `employee` + separate corrupt-profile warning

The deprecation warnings are intentional — they surface profile rows that Supabase
migration 049 should have normalized but missed, so ops can find and fix the stragglers.

### 2.3 `BrainStorm+-Web/supabase/migrations/059_profiles_excluded_caps.sql`

Adds `profiles.excluded_capabilities jsonb` (nullable, default `null`). Read by
`getEffectiveCapabilities` as the subtraction input. iOS mirrors this via
`Profile.excludedCapabilities: [String]?` decoded from `excluded_capabilities`.

### 2.4 DB RLS for `risk_actions` (migrations 014 + 037)

Write-permissive role set is `['super_admin', 'admin', 'hr_admin', 'manager']`.
Intentionally narrower than Web server guard (which admits 6 roles at level ≥ 2 via
`getRoleLevel`). This is the gate Task G folds into `RBACManager.canManageRiskActions`.

## 3. Deltas Landed

### 3.1 `RBACManager.swift`

**`PrimaryRole` enum (Task A)** — now exactly `{ employee, admin, superadmin }`. The
doc comment explicitly documents that legacy roles fold via `migrateLegacyRole` and
forbids re-introducing references in new code.

**`Capability` enum (Task B)** — 30 cases, ordered to mirror Web's semantic groups.
The 4 new `管理扩展` caps are inserted after `ai_interview_entry` and before the
governance block.

**`defaultCapabilities` dictionary (Task C)** — complete rewrite. `.employee: []` +
`.admin: 18 caps` + `.superadmin: 30 caps`. Grouping comments match Web's source
structure. The `.chairperson` key is gone (enum no longer has the case).

**`migrateLegacyRole(_:)` (Task D)** — complete rewrite. Introduces
`logLegacyRoleWarning(_:mappedTo:)` helper. Canonical roles return without logging
(`superadmin` / `admin` / `employee`). Legacy roles log `⚠️ [role-migration]` before
returning the canonical shape. `chairperson` now folds to `.superadmin` (previously had
its own `PrimaryRole` case — removed this sprint). Unknown roles return `.employee`
with a separate "possible corrupt profile row" warning.

**`getEffectiveCapabilities(for profile:)` (Task F)** — now computes `(defaults ∪
migration-derived ∪ DB-assigned) − excluded`. Reads `profile.excludedCapabilities`,
compactMaps to `Capability`, subtracts from the merged set. Matches Web's set-union
minus-set algorithm exactly.

**`canManageRiskActions(rawRole:) / canManageRiskActions(profile:)` (Task G)** — new
public API. DB-RLS-mirror whitelist: `['super_admin', 'superadmin', 'admin', 'hr_admin',
'manager']`. `profile:` overload forwards to `rawRole:` variant. Documented as
intentionally narrower than Web server guard; the iOS client mirrors the authoritative
DB layer because writes are RLS-gated regardless of client.

### 3.2 `Profile.swift` (Task E)

`public let excludedCapabilities: [String]?` added at line 15 with `case
excludedCapabilities = "excluded_capabilities"` in `CodingKeys`. Synthesized Codable
handles the JSON round-trip automatically — no call-site updates needed (every
existing `Profile` creation path goes through the decoder).

### 3.3 Projects module consumer cleanup (Task B.2–B.4, Task G.2–G.3)

- `ProjectListViewModel.isAdmin(role:)` — switch drops `.chairperson`. Doc comment
  re-grounded against current Web `isAdmin()` (2-role canonical set).
- `ProjectDetailViewModel.isAdmin(role:)` — switch drops `.chairperson`.
- `ProjectDetailViewModel` — deletes local `canSyncRiskAction(role:)` + `syncEnabledRoles`
  (the raw-string whitelist that 2.6 introduced). `syncRiskActionFromDetail(rawRole:)`
  gate now calls `RBACManager.shared.canManageRiskActions(rawRole:)`. Doc comments for
  the gate preconditions updated accordingly.
- `ProjectDetailView.canSyncRiskAction` computed property — delegates to
  `RBACManager.shared.canManageRiskActions(rawRole:)`. Doc comment re-grounded against
  the 5-role DB RLS whitelist (added `superadmin` canonical alias to the documented
  set).

### 3.4 Docs correction (Task H)

`docs/parity/49-winston-ready-2.6-notes.md` §2.3 + §2.4 RBAC passage was wrong in three
ways — all three closed:
1. Path `src/lib/security/rbac.ts` → `src/lib/rbac.ts` (target file exists at the
   corrected path).
2. `serverGuard({requiredRole:'manager'})` role set documented as `{super_admin, admin,
   hr_admin, manager}` was wrong. `ROLE_LEVEL` has no `hr_admin`; level ≥ 2 resolves
   to `{manager, team_lead, admin, super_admin, superadmin, chairperson}` — a 6-role
   set. Corrected.
3. iOS 4-role whitelist re-contextualized as **DB RLS mirror** (migrations 014 + 037),
   strictly narrower than Web server guard. The code was always safe (RLS is the
   authoritative write gate); the narrative just told the wrong story.

## 4. Verification

`xcodebuild build -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO` → `** BUILD SUCCEEDED **`.

`xcodebuild test -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"Brainstorm+Tests/RBAC_Sprint30_Tests"`
→ `** TEST SUCCEEDED **`. 7/7 assertions green (twice, parallel destination clones):

| # | Assertion | Pins |
|---|-----------|------|
| 1 | `defaultCapabilitiesAdminCount` | `defaultCapabilities[.admin]!.count == 18` |
| 2 | `defaultCapabilitiesSuperadminCount` | `defaultCapabilities[.superadmin]!.count == 30` |
| 3 | `migrateLegacyChairpersonFoldsToSuperadmin` | `migrateLegacyRole("chairperson").primaryRole == .superadmin` |
| 4 | `migrateLegacyHrDerivesCapabilities` | `migrateLegacyRole("hr")` → `.employee` + `hr_ops` + `ai_resume_screening` |
| 5 | `profileDecodesExcludedCapabilities` | JSON `excluded_capabilities: ["holiday_admin"]` round-trips |
| 6 | `effectiveCapabilitiesSubtractsExcluded` | admin profile with `excluded: [holiday_admin]` → result omits it |
| 7 | `riskActionsGateMirrorsDbRls` | 5-member whitelist accepted; employee / nil rejected |

Tests live in `Brainstorm+Tests/Brainstorm_Tests.swift` under `struct
RBAC_Sprint30_Tests`. Swift Testing framework (`@Test` + `#expect`). Adding a new test
file would require pbxproj edits; appending into the existing compile-list file
sidesteps that tax.

## 5. Audit Checklist for Winston

Verify — should all trivially pass:

- [ ] `PrimaryRole` enum has exactly 3 cases: `employee` / `admin` / `superadmin`.
  (Grep `case chairperson` across `Brainstorm+/` → 0 matches expected.)
- [ ] `Capability` enum has exactly 30 cases. (Count via grep.)
- [ ] `defaultCapabilities[.admin]` count is 18. (Static count + test #1.)
- [ ] `defaultCapabilities[.superadmin]` count is 30. (Static count + test #2.)
- [ ] Every capability in Web `src/lib/capabilities.ts:18-51` has a matching iOS case
  with the same raw string. (Web 30 = iOS 30, no extras either side.)
- [ ] `migrateLegacyRole("chairperson")` returns `.superadmin` + logs deprecation. (Test
  #3 + `logLegacyRoleWarning` definition.)
- [ ] `migrateLegacyRole("hr")` returns `.employee` + HR-derived capability set. (Test
  #4.)
- [ ] `Profile` has `excludedCapabilities: [String]?` with `excluded_capabilities` JSON
  key. (Model source + test #5.)
- [ ] `getEffectiveCapabilities` subtracts `profile.excludedCapabilities`. (Test #6 +
  source at RBACManager.swift:195.)
- [ ] `RBACManager.canManageRiskActions` exists in both `rawRole:` and `profile:`
  shapes and mirrors the 5-role DB RLS whitelist. (Source + test #7.)
- [ ] No Projects-module file still defines its own role whitelist for risk-action
  writes. (Grep `syncEnabledRoles` / `updateEnabledRoles` → 0 matches expected.)
- [ ] `xcodebuild build` → BUILD SUCCEEDED.
- [ ] `xcodebuild test -only-testing:"Brainstorm+Tests/RBAC_Sprint30_Tests"` → TEST
  SUCCEEDED, 7/7.

Look for scope creep — should find nothing. If the audit finds:

- Feature behavior changes outside Projects consumer cleanup → out of scope.
- Schema / RLS / migration / Web-side changes → out of scope.
- Capability additions beyond the 4 specified → out of scope.
- New deprecation warnings on canonical roles (`superadmin` / `admin` / `employee`) →
  regression; those must pass through silently.

## 6. Debt Carry-Forward (open after 3.0)

- **Dashboard, Chat, Attendance, Reporting, Copilot capability gates**: iOS feature
  code still reads `PrimaryRole` or raw role strings at call sites rather than checking
  `Capability` via `getEffectiveCapabilities`. 3.0 built the infrastructure; consumer
  migration to capability-based gates belongs with each XL-tier sprint.
- **Capability package resolver**: Web exposes `resolvePackages(packageIds:)` in
  `capabilities.ts:305-312` (HR / Finance / Media packages that expand into flat
  capability lists). iOS has no equivalent. Needed when Admin UI lets a manager assign
  packages (deferred with 3.6+ Admin module).
- **Capability-package UI**: admin-facing "assign package to user" view is Web-only.
  Deferred.
- **Role-level comparisons** (`hasPrimaryRoleLevel`): Web exposes at
  `capabilities.ts:195-203`; iOS has no equivalent. Only needed if a flow compares
  roles numerically (none do on iOS yet). Deferred.
- **`ALL_APPROVAL_CAPABILITIES` / `APPROVAL_TYPE_CAPABILITY_MAP`
  (capabilities.ts:210-237)**: iOS has no equivalent. Needed when Approval module
  (#Task 5 parity) gates per-type routing. Deferred with 3.x Approval sprint.
- **Three 2.6 doc corrections from `50-winston-audit-2.6.md` §8**: corrections #1 and
  #2 (path and role set) closed by 3.0 Task H. Correction #3 (`lastSyncedRiskActionId`
  unconsumed by View) remains open — acceptable as intentional extension point for the
  deferred Resolution Write-Back sprint.
- **Dropped `.chairperson` PrimaryRole case**: any Swift code in a target NOT rebuilt
  by 3.0 (unlikely — iOS is single-target) would emit an exhaustive-switch warning.
  Build verification confirmed no such warnings; noted here for audit closure.

## 7. Artifacts

- Source: `Brainstorm+/Shared/Security/RBACManager.swift`,
  `Brainstorm+/Core/Models/Profile.swift`,
  `Brainstorm+/Features/Projects/ProjectListViewModel.swift`,
  `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`,
  `Brainstorm+/Features/Projects/ProjectDetailView.swift`.
- Tests: `Brainstorm+Tests/Brainstorm_Tests.swift` (appended `RBAC_Sprint30_Tests`).
- Docs corrected: `docs/parity/49-winston-ready-2.6-notes.md`.
- Devprompt: `devprompt/3.0-rbac-infrastructure-web-parity-foundation.md`.
- Ledger sync: `findings.md`, `progress.md`, `task_plan.md`.
