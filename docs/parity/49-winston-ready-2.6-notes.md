# 49 Winston Ready — 2.6 Projects Risk Action Sync Write Path Foundation

**Round:** `2.6 Projects Risk Action Sync Write Path Foundation`
**Date:** `2026-04-17`
**Status:** READY — Path A (direct Supabase INSERT) delivered against
`devprompt/2.6-projects-risk-action-sync-write-path-foundation.md`.
**Prompt:** `devprompt/2.6-projects-risk-action-sync-write-path-foundation.md`

## 1. Sprint Scope

2.6 introduces the first iOS write path on the Projects module by mirroring Web's
"转为风险动作" / `syncRiskFromDetection` flow. Single affordance, confirmation-gated,
RBAC-gated client-side, RLS-gated server-side, with a best-effort audit event and a
post-write refresh of `linkedRiskActions` + `resolutionFeedback`.

Devprompt §7 offered two completion paths:

- **Path A — Direct write feasible**. Chosen. Every column in `risk_actions` is UI-
  supplied or auth-derived. No `askAI()` / `decryptApiKey()` / `api_keys`. RBAC gate
  mirrored client-side; RLS gate unchanged server-side.
- **Path B — Direct write not safe/feasible**. Ruled out after explicit audit.

Out of scope and explicitly forbidden by the 2.6 prompt: schema / RLS changes, Web
code changes, risk-action update / close / reopen / effectiveness write, governance
note write, bulk convert, assignee picker, due-date picker, risk-action detail modal,
generate-risk-from-iOS, LLM narrative on summary, full risk action management module,
i18n refactor, visual redesign, auto-fetch on detail load.

`.projects` stays `.partial` (no virtual promotion).

## 2. Web Source-of-Truth Re-Read

### 2.1 `BrainStorm+-Web/src/lib/actions/risk-actions.ts` lines 310-394

`createRiskAction(params)` at lines 310-370:

```ts
'use server'
export async function createRiskAction(params: CreateRiskActionInput) {
  const guard = await serverGuard({ requiredRole: 'manager' })
  if (!guard.ok) return { success: false, error: guard.error }
  const { user } = guard

  if (!params.title?.trim()) return { success: false, error: '标题不能为空' }

  const supabase = await getSupabaseServer()
  const { data: profile } = await supabase
    .from('profiles').select('org_id')
    .eq('id', user.id).single()
  if (!profile?.org_id) return { success: false, error: '无法解析组织' }

  const { data: action, error } = await supabase
    .from('risk_actions')
    .insert({
      org_id: profile.org_id,
      risk_type: params.type ?? 'manual',
      source_type: params.sourceType,
      source_id: params.sourceId,
      ai_source_id: params.aiSourceId,
      title: params.title.trim(),
      detail: params.detail,
      severity: params.severity ?? 'medium',
      suggested_action: params.suggestedAction,
      status: 'open',
      created_by: user.id,
    })
    .select().single()
  if (error) return { success: false, error: error.message }

  // Best-effort audit
  await logRiskEvent(action.id, 'created', { toStatus: 'open', actor: user.id })
    .catch(() => {})
  return { success: true, data: action }
}
```

`syncRiskFromDetection(params)` at lines 374-394 is a thin wrapper forwarding args
verbatim into `createRiskAction(params)`.

### 2.2 `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` lines 205-224 + 687-697

Call site payload:

```tsx
const handleSyncToRiskAction = async (title, riskDetail, severity) => {
  setSyncMsg(null)
  const res = await syncRiskFromDetection({
    type: 'manual',
    title,                       // `[${detail.name}] 风险项`
    detail: riskDetail,          // riskSummary.slice(0, 200)
    severity,                    // pre-mapped: critical|high → 'high'; medium → 'medium'; low → 'low'
    suggestedAction: '从项目风险分析生成',
    sourceType: 'project',
    sourceId: detail?.id ?? '',
    aiSourceId: riskSummaryId ?? undefined,
  })
  setSyncMsg(res.success ? '✅ 已转为风险动作（已建立 AI 链路）' : `❌ ${res.error}`)
  if (res.success && detail) {
    const linked = await getLinkedRiskActions(detail.id)
    if (linked.data) setLinkedActions(linked.data)
  }
  setTimeout(() => setSyncMsg(null), 3000)
}
```

No client-side RBAC pre-check on Web — Web relies on RLS post-error.

### 2.3 `BrainStorm+-Web/src/lib/rbac.ts`

`serverGuard({ requiredRole: 'manager' })` resolves via the `getRoleLevel`
hierarchy — `manager` is level 2, so the guard admits every role at level ≥ 2:
`['manager', 'team_lead', 'admin', 'super_admin', 'superadmin', 'chairperson']`
(6 roles total).

The narrower 4-role set `['super_admin', 'admin', 'hr_admin', 'manager']` that
iOS 2.6 uses for its client-side pre-gate is **not** a mirror of Web's
server-guard hierarchy — it is a mirror of the DB RLS policy on `risk_actions`
(see §2.4). iOS is intentionally aligning with the server-side ground truth
(RLS) rather than Web's looser server-guard allow-list, so the client pre-gate
never produces a false positive that RLS would subsequently reject.

### 2.4 Supabase migrations

- `risk_actions.INSERT` RLS policy (Supabase migrations 014 + 037) gates the
  role set `['super_admin', 'admin', 'hr_admin', 'manager']`. This is
  security-equivalent to — and strictly narrower than — Web's
  `serverGuard('manager')` hierarchy; `team_lead` / `chairperson` pass the Web
  server guard but are rejected by RLS on the INSERT.
- FK constraints on `org_id`, `source_id` (project UUID), `ai_source_id`
  (`project_risk_summaries.id`), `created_by` (`auth.users.id`) all satisfiable from
  client-side data.
- `risk_items` JSONB column exists on `risk_actions` but is optional — Web's sync flow
  does not populate it either.
- `risk_action_events` columns: `action_id, event_type, from_status, to_status,
  actor_id, note, created_at`. Web writes `action_id, event_type: 'created',
  to_status: 'open', actor_id` on the initial create; `from_status` and `note` omitted.

## 3. iOS 2.6 Deliverables

### 3.1 `Brainstorm+/Features/Projects/ProjectDetailModels.swift`

New public type:

```swift
public struct RiskActionSyncDraft: Equatable {
    public let title: String
    public let detail: String
    public let severity: String
}
```

Persistence parity doc block records: `title` carries the Chinese `风险项` suffix and
`suggested_action` carries the Chinese `从项目风险分析生成` verbatim; UI dialog copy
(English) is separate from these persisted literals.

### 3.2 `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`

New public nested enum + three @Published properties + extended `applyDeniedState()`:

```swift
public enum RiskActionSyncPhase: Equatable {
    case idle
    case syncing
    case succeeded
}

@Published public var riskActionSyncPhase: RiskActionSyncPhase = .idle
@Published public var riskActionSyncErrorMessage: String? = nil
@Published public var lastSyncedRiskActionId: UUID? = nil
```

`applyDeniedState()` resets all three fields alongside the existing 2.4 / 2.5
cleanup.

Private DTOs:

```swift
private struct ProfileOrgRow: Decodable {
    let orgId: UUID
    enum CodingKeys: String, CodingKey { case orgId = "org_id" }
}

private struct RiskActionInsert: Encodable {
    let orgId, riskType, sourceType, sourceId, aiSourceId, title, detail,
        severity, suggestedAction, status, createdBy  // snake_case CodingKeys
}

private struct RiskActionInsertResult: Decodable { let id: UUID }

private struct RiskActionEventInsert: Encodable {
    let actionId, eventType, toStatus, actorId  // snake_case CodingKeys
}
```

RBAC gate:

```swift
public static func canSyncRiskAction(role: String?) -> Bool {
    guard let role else { return false }
    return syncEnabledRoles.contains(role.lowercased())
}

private static let syncEnabledRoles: Set<String> = [
    "super_admin", "admin", "hr_admin", "manager"
]
```

Severity mapping:

```swift
private static func mapRiskLevelToSeverity(_ level: ProjectRiskAnalysis.RiskLevel) -> String {
    switch level {
    case .critical, .high: return "high"
    case .medium:          return "medium"
    case .low:             return "low"
    case .unknown:         return "medium"   // iOS defensive; Web never hits this
    }
}
```

Confirmation-preview builder:

```swift
public func riskActionSyncDraft() -> RiskActionSyncDraft? {
    guard let project, let analysis = riskAnalysis else { return nil }
    return RiskActionSyncDraft(
        title: "[\(project.name)] 风险项",
        detail: String(analysis.summary.prefix(200)),
        severity: Self.mapRiskLevelToSeverity(analysis.riskLevel)
    )
}
```

Write flow:

```swift
public func syncRiskActionFromDetail(rawRole: String?) async -> Bool {
    // 1. Client RBAC gate
    guard Self.canSyncRiskAction(role: rawRole) else {
        self.riskActionSyncErrorMessage =
            "Converting a risk into a risk action requires admin or manager privileges."
        return false
    }
    // 2. Precondition re-check (race against applyDeniedState)
    guard let project, let analysis = riskAnalysis else { ...; return false }
    // 3. Rebuild draft inside VM; trim + empty-title defense
    let trimmedTitle = "[\(project.name)] 风险项"
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { ...; return false }

    riskActionSyncPhase = .syncing
    riskActionSyncErrorMessage = nil

    do {
        // 4. Re-fetch anchor
        let anchorRows: [LinkedRiskAnchorRow] = try await client
            .from("project_risk_summaries").select("id")
            .eq("project_id", value: projectId).limit(1).execute().value
        guard let anchor = anchorRows.first else {
            self.riskActionSyncErrorMessage = "No risk analysis exists..."
            self.riskActionSyncPhase = .idle
            return false
        }
        // 5. Resolve auth user + org
        let user = try await client.auth.session.user
        let orgRows: [ProfileOrgRow] = try await client
            .from("profiles").select("org_id")
            .eq("id", value: user.id).limit(1).execute().value
        guard let org = orgRows.first else { ...; return false }
        // 6. Primary insert
        let inserted: RiskActionInsertResult = try await client
            .from("risk_actions")
            .insert(RiskActionInsert(
                orgId: org.orgId, riskType: "manual", sourceType: "project",
                sourceId: project.id, aiSourceId: anchor.id,
                title: trimmedTitle,
                detail: draft.detail.isEmpty ? nil : draft.detail,
                severity: draft.severity,
                suggestedAction: "从项目风险分析生成",
                status: "open", createdBy: user.id
            ))
            .select("id").single().execute().value
        // 7. Best-effort audit log — silent swallow on failure
        do {
            try await client.from("risk_action_events").insert(
                RiskActionEventInsert(actionId: inserted.id,
                                      eventType: "created",
                                      toStatus: "open",
                                      actorId: user.id)
            ).execute()
        } catch { /* swallow */ }
        // 8. Post-success
        self.lastSyncedRiskActionId = inserted.id
        self.riskActionSyncPhase = .succeeded
        Task { [weak self] in await self?.refreshLinkedRiskActions() }
        Task { [weak self] in await self?.refreshResolutionFeedback() }
        return true
    } catch {
        self.riskActionSyncErrorMessage = error.localizedDescription
        self.riskActionSyncPhase = .idle
        return false
    }
}

public func clearRiskActionSyncSuccess() {
    guard riskActionSyncPhase == .succeeded else { return }
    riskActionSyncPhase = .idle
}
```

### 3.3 `Brainstorm+/Features/Projects/ProjectDetailView.swift`

New `@State`:

```swift
@State private var isShowingRiskActionSyncConfirm: Bool = false
@State private var pendingRiskActionDraft: RiskActionSyncDraft? = nil
```

New computed properties:

```swift
private var rawRole: String? { sessionManager.currentProfile?.role }
private var canSyncRiskAction: Bool {
    ProjectDetailViewModel.canSyncRiskAction(role: rawRole)
}
```

New `@ViewBuilder riskActionSyncAffordance` (inside `riskAnalysisSection`, rendered
only when `riskAnalysis != nil`):

- Warning-tinted capsule button "Convert to risk action" → disabled + gray + hint
  "Converting a risk into a risk action requires admin or manager privileges." when
  `canSyncRiskAction == false`.
- `ProgressView` + "Converting…" label while `.syncing`.
- Scoped error row via `summaryErrorRow(message:)` when `riskActionSyncErrorMessage`
  is set.
- Green success banner "Risk action created and linked to this analysis." when
  `.succeeded`; auto-clears after 3s via `scheduleRiskActionSyncSuccessClear()`.

`.confirmationDialog("Convert risk analysis to risk action?", ...)` attached to the
`riskAnalysisSection` card with preview message listing title + severity label +
detail. Confirm → `await viewModel.syncRiskActionFromDetail(rawRole: rawRole)`.

`scheduleRiskActionSyncSuccessClear()` spawns a `Task` that sleeps 3s then calls
`viewModel.clearRiskActionSyncSuccess()` — VM guards against stomping a newer
in-flight sync.

Copy updates:

- `linkedRiskActionsSection` subtitle (pre-2.6): "Read-only · converting a risk
  into an action is only available on the web." → (post-2.6): "Linked to the
  current risk analysis. Convert a new risk action above; resolution write-backs
  (close / reopen / effectiveness) remain on the web for now."
- `foundationScopeNote` (pre-2.6): "Converting risks into actions and generating
  new risk analyses from iOS are available on the web and will arrive in later iOS
  rounds." → (post-2.6): "Generating fresh risk analyses and writing resolution
  outcomes (close / reopen / effectiveness) remain on the web and will arrive in
  later iOS rounds."

### 3.4 Ledger

- `findings.md` — prepended 2.6 scope header + Path A decision + RBAC divergence
  + persistence parity + parity checklist + debt carry-forward; 2.5.1 retrospective
  preserved verbatim beneath.
- `progress.md` — appended 2.6 delivery block (Goals A-H + Verification); Active
  updated to point at Winston 2.6 audit.
- `task_plan.md` — `2.6 Projects Risk Action Sync Write Path Foundation completed.`
  added; next-step updated to Winston 2.6 audit; Phase 1.x summary extended with the
  2.6 description (RBAC divergence, Path A flow, persistence parity, 3-phase enum).
- `docs/parity/49-winston-ready-2.6-notes.md` — this file.

## 4. Parity Checklist

| Dimension | Web behavior | iOS after 2.6 | Parity |
|---|---|---|---|
| Client-side RBAC pre-gate | Absent (RLS post-error only) | Raw-string check against Web's exact role set | iOS stronger (parity-plus) |
| Confirmation affordance | Absent (one-click) | `.confirmationDialog` with payload preview | iOS stronger (parity-plus) |
| Primary insert columns (11) | `risk_actions` with 11 columns | Identical 11-column Encodable DTO | Parity |
| Hard-coded `risk_type = 'manual'` | Yes | Yes | Parity |
| Hard-coded `source_type = 'project'` | Yes | Yes | Parity |
| Hard-coded `status = 'open'` | Yes | Yes | Parity |
| Hard-coded `suggested_action = '从项目风险分析生成'` | Yes | Yes | Parity |
| `title` template = `` `[${name}] 风险项` `` | Yes | `"[\(project.name)] 风险项"` | Parity |
| `detail = riskSummary.slice(0, 200)` | UTF-16 code units | `String.prefix(200)` (grapheme clusters) | Parity (cluster-safe slice — diverges only on emoji / combining marks) |
| Severity ternary (critical/high → high; medium → medium; low → low) | Yes | Yes + defensive `.unknown → "medium"` branch | Parity (iOS fallback Web never reaches) |
| Title trim-and-reject | Yes | Yes | Parity |
| `org_id` resolution via `profiles.select('org_id')` | Yes | Identical PostgREST call via `ProfileOrgRow` DTO | Parity |
| `ai_source_id` anchor resolution | Caller passes `riskSummaryId` state | iOS re-fetches anchor inside write method (+1 round-trip) | Parity (iOS self-contained) |
| Best-effort audit log | `logRiskEvent` silent-swallow | Inline `do/catch` silent-swallow on `risk_action_events` | Parity |
| Post-write refresh | `await getLinkedRiskActions(detail.id)` | Parallel `Task { refreshLinkedRiskActions() }` + `Task { refreshResolutionFeedback() }` | Parity-plus |
| 3-second success auto-clear | `setTimeout(..., 3000)` | `Task.sleep` + VM `clearRiskActionSyncSuccess()` | Parity |
| Error isolation | Shared `syncMsg` string | Dedicated `riskActionSyncErrorMessage` | iOS stronger (parity-plus) |
| Phase modeling | Implicit via `syncMsg` content | Explicit `RiskActionSyncPhase { idle, syncing, succeeded }` | Parity-plus |
| `lastSyncedRiskActionId` | Absent | Published `UUID?` for future rounds | iOS extension (parity-neutral) |
| Resolution write-back | Web only | Still absent on iOS | Deferred by scope |
| Governance intervention write | Web only | Still absent on iOS | Deferred by scope |
| Generate risk from iOS | Web only | Still absent on iOS | Deferred by scope (needs Web HTTP endpoint) |
| Auto-fetch on detail load | Web auto-fetches | iOS explicit button | Foundation divergence (carried from 2.2/2.3/2.4/2.5) |
| `.projects` parity | — | `.partial` (unchanged) | Parity (no virtual promotion) |

## 5. State Machine

```
idle (or succeeded via auto-clear)
   ↓ user taps "Convert to risk action"
       (View snapshots draft, opens .confirmationDialog)
       ↓ user confirms
   ↓
syncing  ─ error ─▶  idle + riskActionSyncErrorMessage (prior snapshot preserved)
   ↓ success
succeeded (lastSyncedRiskActionId = newId)
       ↓ dispatch refreshLinkedRiskActions() + refreshResolutionFeedback() in parallel
       ↓ 3s auto-clear via scheduleRiskActionSyncSuccessClear()
   ↓
idle
```

VM guards against `clearRiskActionSyncSuccess()` stomping a newer in-flight sync —
the clear only runs when the current phase is still `.succeeded`.

## 6. Verification

- Build command:
  `xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO`
- Build result: **`** BUILD SUCCEEDED **`** (captured 2026-04-17 on `iPhone 17 Pro
  Max` destination with `CODE_SIGNING_ALLOWED=NO`).
- Scan pattern (devprompt §7.A intent):
  `'riskActionSync|RiskActionSync|canSyncRiskAction|syncRiskActionFromDetail|RiskActionInsert|RiskActionEventInsert|mapRiskLevelToSeverity|clearRiskActionSyncSuccess|syncEnabledRoles|RiskActionSyncDraft|RiskActionSyncPhase|lastSyncedRiskActionId'`
- Code hit count: **78 total across 3 files** inside `Brainstorm+/Features/Projects/`:
  - `ProjectDetailModels.swift`: 2
  - `ProjectDetailViewModel.swift`: 53
  - `ProjectDetailView.swift`: 23
- Scope sweep:
  - No `askAI(` / `decryptApiKey(` / `api_keys` access in any 2.6 code path.
  - No schema migration, no RLS change, no Web code change, no new Edge Function,
    no new HTTP endpoint.
  - No new risk-action-update / close / reopen / effectiveness write / governance
    note write paths.
  - No auto-fetch added to `fetchDetail(...)` — sync remains explicit-button-only.
  - No change to `PrimaryRole` / `RBACManager.migrateLegacyRole(_:)` / session
    plumbing — the RBAC divergence is isolated to the 2.6 raw-string check.

## 7. Known Debt (carried + updated)

Carried from 2.5.1 unchanged unless noted:

- Resolution write-back (close / reopen / effectiveness / governance note): still
  absent on iOS.
- ~~"转为风险动作" sync from iOS~~: **Delivered in 2.6** with RBAC gate + confirmation
  + post-write refresh. Debt line closed.
- Generate risk analysis from iOS (2.3 carry-over): still deferred. Needs
  `/api/ai/project-risk` HTTP endpoint or Supabase Edge Function.
- LLM-generated narrative on AI summary (2.2 carry-over): still deferred behind
  `/api/ai/project-summary`.
- Auto-fetch on detail load: iOS still gates reads behind button taps. Foundation
  divergence.
- `total` caps at 50 (matches Web's own contract — not a bug).
- Source-of-truth divergence on task count (2.1): still open on the Web side.
- `risk_items` JSONB: not populated by either Web or iOS sync. Belongs with a later
  risk-item grouping surface.
- **New in 2.6 — Duplicate prevention**: no unique constraint; no pre-check. Mirrors
  Web exactly. Repeated confirmation creates multiple rows.
- **New in 2.6 — RBAC divergence vs `PrimaryRole`**: 2.6 uses a raw-string role
  set rather than `PrimaryRole` because `RBACManager.migrateLegacyRole` drops
  `hr_admin` (false negative) and over-maps `chairperson` / `team_lead` (false
  positives). Isolated to the 2.6 gate; other Projects surfaces still use
  `PrimaryRole`.
- **New in 2.6 — Anchor re-fetch cost**: one extra `project_risk_summaries.id`
  lookup per write. Cheap, self-contained, keeps the method independent of prior
  section state.
- **New in 2.6 — Persistence parity hardcodes Chinese literals**: `title` suffix
  `风险项` and `suggested_action` = `从项目风险分析生成` are persisted verbatim from
  iOS so rows look identical to Web-written rows. UI dialog copy stays English; the
  two concerns are intentionally separated.
- Palette debt: sync capsule uses `Color.Brand.warning`; critical risk / high
  severity / reopened-count debt from 2.3–2.5 unchanged.
- RLS trust on `risk_actions.INSERT`: iOS pre-gates via the raw-string role set;
  RLS remains the server-side ground truth.
- Locale-aware copy on the 2.6 button / hint / dialog / success banner: English-only.
  Belongs with broader iOS i18n (carry-over).
- All prior client-side `filteredProjects`, `AccessOutcome` role normalization,
  batched `.in("id", values: ids)` hydrate, `AsyncImage` cache not persistent,
  date-only `String` fields, `maybeSingle()` absent from Swift SDK, nested
  `NavigationStack` inside `ProjectListView` — unchanged carry-overs from 1.5–2.5.1.

## 8. Recommended Next Round (for Winston to confirm / replace)

Two candidates, either one tractable next:

- **2.7 Resolution write-back minimum viable**: `risk_actions.UPDATE` for `status`
  transitions (open → acknowledged | in_progress | resolved | dismissed) +
  `effectiveness` + `resolution_category` + `reopen` path. Same RBAC gate as 2.6
  (`['super_admin', 'admin', 'hr_admin', 'manager']`). Same confirmation-first
  posture. Same post-write refresh of linked actions + resolution feedback.
  Extends the 2.6 audit-event pattern (`event_type: 'status_changed' | 'reopened' |
  'resolved'`). Keeps `.projects` `.partial`; unlocks full resolution parity with
  Web.
- **Alternative — 2.7 Generate risk analysis from iOS**: blocked until Web exposes
  `/api/ai/project-risk` (or Supabase Edge Function). If that endpoint lands between
  2.6 and 2.7, iOS can drop the "must be generated on Web" hint inside the risk
  analysis section and replace the "Check for risk analysis" refresh flow with a
  real `generate` button.

Neither direction is prejudged by 2.6.
