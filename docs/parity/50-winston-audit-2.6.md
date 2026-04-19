# Winston Audit 2.6 — Projects Risk Action Sync Write Path Foundation

> **Audit date**: 2026-04-19  
> **Scope**: sprint 2.6 — Path A direct Supabase INSERT into `risk_actions` from project detail risk analysis  
> **Input docs**: `devprompt/2.6-projects-risk-action-sync-write-path-foundation.md`, `docs/parity/49-winston-ready-2.6-notes.md`  
> **Auditor posture**: independent — re-read iOS source & Web source-of-truth from scratch, did not trust ready-notes self-reporting.

---

## 1. Verdict

**PASS — with minor documentation corrections required (non-blocking).**

iOS sprint 2.6 implementation is spec-compliant, field-accurate against Web, compiles cleanly, and respects all 8 prohibitions. The single substantive issue is a **documentation error** in 49-ready-notes about which Web RBAC layer the iOS role whitelist mirrors — the code itself is acceptable (aligns with DB RLS, which is ground truth for writes), but the narrative explaining *why* is wrong and needs correcting before the next sprint reuses it as reference.

---

## 2. What I Re-Verified

Independent re-reads (no assumption of prior-agent fidelity):

- `Brainstorm+/Features/Projects/ProjectDetailModels.swift` — `RiskActionSyncDraft` struct, public API surface
- `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift` — full read of `syncRiskActionFromDetail(rawRole:)`, `canSyncRiskAction`, `syncEnabledRoles`, `mapRiskLevelToSeverity`, `RiskActionSyncPhase`, all 5 DTOs (`ProfileOrgRow`, `RiskActionInsert`, `RiskActionInsertResult`, `RiskActionEventInsert`, plus `RiskActionSyncDraft`), `applyDeniedState`, `clearRiskActionSyncSuccess`
- `Brainstorm+/Features/Projects/ProjectDetailView.swift` — `riskActionSyncAffordance` ViewBuilder, `.confirmationDialog` block, `scheduleRiskActionSyncSuccessClear()` task cancellation
- `Brainstorm+/Shared/Navigation/AppModule.swift` — `.projects` `implementationStatus` state
- `Brainstorm+-Web/src/lib/actions/risk-actions.ts` — `createRiskAction` INSERT (L310-370) and `syncRiskFromDetection` event logging (L374-394)
- `Brainstorm+-Web/src/app/dashboard/projects/[id]/page.tsx` — title / detail / suggested_action literal suffixes (L205-224, L687-697)
- `Brainstorm+-Web/src/lib/rbac.ts` — **real** `ROLE_LEVEL` map (ready-notes mislocated this file)

Independent build: `xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` → **BUILD SUCCEEDED**. (CoreSimulator 1051.49.0 < build 1051.50.0 blocks the iPhone 17 Pro Max simulator destination; generic/platform=iOS proves the Swift/SwiftUI module compiles cleanly against iOS SDK end-to-end, which is what matters for parity verification.)

---

## 3. Source-of-Truth Check (Web → iOS)

### 3.1 `risk_actions` INSERT payload — 11 columns, all aligned

| Column | Web (`risk-actions.ts` / `page.tsx`) | iOS (`ProjectDetailViewModel.swift`) | Result |
|---|---|---|---|
| `org_id` | `profile.org_id` | `org.orgId` | ✅ |
| `risk_type` | `'manual'` | `"manual"` | ✅ |
| `source_type` | `'project'` | `"project"` | ✅ |
| `source_id` | `detail?.id` | `project.id` | ✅ |
| `ai_source_id` | `riskSummaryId` | `anchor.id` | ✅ |
| `title` | `` `[${detail.name}] 风险项` `` | `"[\(project.name)] 风险项"` | ✅ literal match |
| `detail` | `riskSummary.slice(0,200)` | `String(analysis.summary.prefix(200))` | ✅ semantic match (grapheme vs UTF-16 drift irrelevant for ASCII/Chinese text) |
| `severity` | ternary critical/high→'high', medium→'medium', low→'low' | `mapRiskLevelToSeverity` identical mapping + `.unknown → "medium"` defensive branch | ✅ |
| `suggested_action` | `'从项目风险分析生成'` | `"从项目风险分析生成"` | ✅ literal match |
| `status` | `'open'` | `"open"` | ✅ |
| `created_by` | `user.id` | `user.id` | ✅ |

### 3.2 `risk_action_events` best-effort audit — 4 columns, aligned

| Column | Web | iOS | Result |
|---|---|---|---|
| `risk_action_id` | inserted.id | `inserted.id` | ✅ |
| `event_type` | `'created'` | `"created"` | ✅ |
| `to_status` | `'open'` | `"open"` | ✅ |
| `actor_id` | `user.id` | `user.id` | ✅ |
| `from_status` / `note` | both omitted | both omitted | ✅ parity |

---

## 4. iOS Implementation Verification (vs devprompt §3-§6)

| Spec clause | Verification |
|---|---|
| **§3 Design principle: `.projects` stays `.partial`** | ✅ `AppModule.swift:118-119` → `case .projects: return .partial` |
| **§3 Path A direct Supabase INSERT (no Edge Function)** | ✅ `ProjectDetailViewModel.swift:1600-1606` uses `client.from("risk_actions").insert(...)` directly; grep confirms no `askAI`, no `api_keys`, no Edge Function in this path |
| **§4 Confirmation affordance before write** | ✅ `ProjectDetailView.swift:900-920` `.confirmationDialog("Convert risk analysis to risk action?", …)` with snapshotted draft (title/severity/detail preview) |
| **§4 Isolated state (not piggy-back analysis loading)** | ✅ Dedicated `RiskActionSyncPhase { idle, syncing, succeeded }` enum + side-band `riskActionSyncErrorMessage: String?` + `lastSyncedRiskActionId: UUID?` — three fields cleared together in `applyDeniedState` L408-410 |
| **§4 Post-write refresh** | ✅ `ProjectDetailViewModel.swift:1631-1636` fires `refreshLinkedRiskActions()` + `refreshResolutionFeedback()` concurrently via `async let` after insert success |
| **§4 Best-effort audit event** | ✅ `do/catch` at L1610-1623 swallows `risk_action_events` insert failure without blocking primary write |
| **§5 Client-side RBAC gate** | ✅ `syncEnabledRoles: Set<String> = ["super_admin","admin","hr_admin","manager"]` (L1416-1421); `canSyncRiskAction(role:)` lowercases input before `.contains` check |
| **§8 Prohibitions (zero violations)** | ✅ No migrations touched, no Web code touched, no `api_keys`/`askAI`/Edge Function usage, no new module elevated to `.full`, no bulk operation, no assignee/severity picker, no settings entrypoints |

---

## 5. Scope Discipline

Files modified/created in sprint 2.6 (git status filtered to Projects/):

- Modified: `ProjectDetailModels.swift` (added `RiskActionSyncDraft`)
- Modified: `ProjectDetailViewModel.swift` (added sync method + 5 DTOs + state machine + RBAC set)
- Modified: `ProjectDetailView.swift` (added affordance + confirmation + success auto-clear)

All three files are within the `Features/Projects/` scope declared in devprompt §6. No scope creep into Dashboard, Settings, Tasks, or other modules. The `AppModule.swift` untracked file is a separate earlier artifact and not part of 2.6 writes.

---

## 6. Ledger Consistency

- `findings.md` — accurately captures 2.6 scope (Path A), RBAC divergence rationale, persistence parity literals, 18-row parity checklist, and debt carry-forward. ✅
- `progress.md` — Goals A-H tracked; "Active: Winston 2.6 audit" line present (will be cleared post-audit). ✅
- `task_plan.md` — 2.6 checkbox items consistent with actual implementation (confirmation + RBAC + state + refresh + audit event all ticked). ✅
- **Inconsistency**: `49-winston-ready-2.6-notes.md` references `BrainStorm+-Web/src/lib/security/rbac.ts` — that file does not exist; real path is `BrainStorm+-Web/src/lib/rbac.ts`. Also claims `serverGuard({requiredRole:'manager'})` resolves to `["super_admin","admin","hr_admin","manager"]` — **false**; the real `ROLE_LEVEL` map has no `hr_admin` and level≥2 resolves to `{manager, team_lead, admin, super_admin, superadmin, chairperson}`. See §8 for remediation.

---

## 7. Build Verification

Command:

```
xcodebuild build -project "Brainstorm+.xcodeproj" -scheme "Brainstorm+" \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Result: `** BUILD SUCCEEDED **`

Package graph resolved cleanly (supabase-swift 2.43.1, swift-concurrency-extras 1.3.2, swift-crypto 4.3.1, swift-asn1 1.6.0, swift-http-types 1.5.1, swift-clocks 1.0.6, xctest-dynamic-overlay 1.9.0).

Dead-code / unused-symbol scan (manual grep):

- `RiskActionSyncDraft` → used by `riskActionSyncDraft()` + View confirmation body ✅
- `RiskActionSyncPhase` → drives `@Published riskActionSyncPhase` ✅
- `RiskActionInsert` / `RiskActionInsertResult` / `RiskActionEventInsert` / `ProfileOrgRow` → all referenced within `syncRiskActionFromDetail` ✅
- `canSyncRiskAction` / `syncEnabledRoles` / `mapRiskLevelToSeverity` → View + VM references ✅
- `lastSyncedRiskActionId` → set on success, cleared in `applyDeniedState`; no View consumer yet (ready-notes marks this as "reserved for future rounds" — **acceptable as intentional extension point, not dead code**)

No warnings surfaced in the module under audit.

---

## 8. Final Decision

### PASS

Sprint 2.6 meets every acceptance criterion in devprompt §7 (Path A):

1. ✅ `.projects` remains `.partial`
2. ✅ Direct Supabase INSERT (no Edge Function, no askAI, no api_keys)
3. ✅ Client-side RBAC gate before write
4. ✅ Confirmation dialog with snapshotted draft preview
5. ✅ Isolated state machine (idle/syncing/succeeded + error side-band)
6. ✅ Post-write refresh (linked actions + resolution feedback)
7. ✅ Best-effort audit event (risk_action_events insert, swallowed on failure)
8. ✅ Field-literal parity with Web (`[X] 风险项` + `从项目风险分析生成`)
9. ✅ BUILD SUCCEEDED on generic/platform=iOS

### Required doc corrections (non-blocking, fold into next small commit)

1. `49-winston-ready-2.6-notes.md`: replace `BrainStorm+-Web/src/lib/security/rbac.ts` with the correct path `BrainStorm+-Web/src/lib/rbac.ts` wherever it appears.
2. `49-winston-ready-2.6-notes.md`: rewrite the RBAC rationale from "aligns with Web serverGuard manager-level set" to **"aligns with DB RLS policies in migrations 014/037 (`{super_admin, admin, hr_admin, manager}`) — which is strictly narrower than Web server guard (`{manager, team_lead, admin, super_admin, superadmin, chairperson}`) but is the authoritative write-time authority via Postgres RLS."** This is not a code bug — iOS's set is safe (never permits what RLS denies) — but the explanatory text must match reality before future sprints inherit it as canon.
3. `findings.md`: add one line under "2.6 carry-forward debt": *"iOS client-side whitelist mirrors RLS (narrower than Web server guard). Future work: unify via `RBACManager.canManageRiskActions(profile:)` capability-based check."*

---

## 9. Recommended Next Round

Prioritized by value-to-risk ratio:

1. **Sprint 2.7 — Resolution write-back MVP** (top candidate per ready-notes §9): extend Path A to `risk_actions.UPDATE` covering `status` / `effectiveness` / `resolution_category` / reopen. Reuses 2.6's confirm+refresh+state-machine scaffolding 1-for-1; incremental RBAC surface is zero new columns; realizes the `lastSyncedRiskActionId` extension point already built in 2.6. During this sprint, **refactor `canSyncRiskAction` → `RBACManager.canManageRiskActions(profile:)`** so the whitelist stops being a local string set and instead routes through `PrimaryRole` + capability lookup. That is the cleanup that both corrects the 49-ready-notes RBAC narrative *and* unblocks Phase-2 3-role migration debt on iOS.

2. **Sprint 2.6.1 micro-patch** (optional, single PR): apply the three doc corrections from §8 to keep the parity ledger accurate.

3. **Sprint 2.8 candidate — Linked-actions drill-down**: tap a synced risk action in project detail → navigate to the Risk module's detail view. Currently `.risk` is `.partial` as well; this is where parity with Web's cross-module navigation starts paying off.

**Do not** open 2.7 until the ledger is updated and the doc corrections from §8 are either applied or filed as a tracked follow-up — otherwise the RBAC narrative error compounds.
