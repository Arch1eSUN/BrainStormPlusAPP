# Winston-Ready Notes — Sprint 2.4 (Projects Linked Risk Actions Foundation)

## Sprint Scope (as contracted in `devprompt/2.4-projects-linked-risk-actions-foundation.md`)

- Close the linked-risk-actions-on-detail gap flagged by Winston 2.3 audit's "Recommended next round".
- Ship a first-class `linkedRiskActionsSection` on `ProjectDetailView` with a complete 5-phase state machine (idle / loading / noRiskAnalysisSource / empty / loaded) + side-band error surface + `priorPhase` revert on failure.
- **Read-only** against the same tables Web's `getLinkedRiskActions(projectId)` server action hits: `project_risk_summaries` (anchor lookup) + `risk_actions` (filtered by `ai_source_id`). Unlike 2.2 / 2.3, no `askAI()` call, no server-decrypted `api_keys` — the flow is pure Supabase reads, so iOS faithfully replicates it.
- Explicitly defer the "转为风险动作" convert-to-action write path (`syncRiskFromDetection`), resolution feedback, governance intervention, and recent resolutions — all Web-only for now.
- Keep `.projects` on `.partial`.

## Web Source-of-Truth Re-Read (explicit)

### `BrainStorm+-Web/src/lib/actions/summary-actions.ts` (server action)

- `getLinkedRiskActions(projectId: string)` — `'use server'` function at lines 597-626.
- Two-step read:

  ```ts
  // Step 1: anchor lookup — find the project_risk_summaries row id for this project
  const { data: summary, error: summaryError } = await adminDb
    .from('project_risk_summaries')
    .select('id')
    .eq('project_id', projectId)
    .maybeSingle();

  if (summaryError) return { actions: [], error: summaryError.message };
  if (!summary) return { actions: [], error: null };

  // Step 2: filtered select on risk_actions
  const { data: actions, error: actionsError } = await adminDb
    .from('risk_actions')
    .select('id, title, status, severity, ai_source_id')
    .eq('ai_source_id', summary.id)
    .order('created_at', { ascending: false })
    .limit(20);
  ```

- Returns `{ actions: ProjectLinkedRiskAction[], error: string | null }`.
- **No `askAI()` call.** **No `decryptApiKey()` access.** Pure Supabase reads.

### `BrainStorm+-Web/src/app/dashboard/projects/page.tsx`

- Lines 687-697: "转为风险动作" convert-to-action button → `handleSyncToRiskAction()` → `syncRiskFromDetection({ aiSourceId: riskSummaryId })`. **Write path — explicitly Web-only, out of 2.4 scope.**
- Lines 698-702: Count badge `{linkedActions.length} 个已关联动作`.
- Lines 705-724: `linkedActions.slice(0, 3)` preview — each row renders a status-dot + truncated title (2 lines) + severity capsule; a trailing "还有 N 个动作…" hint when `linkedActions.length > 3`.

### `BrainStorm+-Web/src/app/api/`

- Contains `ai/analyze`, `ai/models` HTTP routes. **No `/api/risk-actions` or equivalent.**
- `getLinkedRiskActions` is server-action only — BUT, unlike 2.2 / 2.3, its guts are pure Supabase reads, so iOS CAN faithfully replicate it via direct PostgREST.

### Schema (migration `037_round8_risk_knowledge_ai.sql` + extensions 014-017)

- `risk_actions` columns: `id, org_id, risk_type, source_type, source_id, title, detail, severity ∈ {low, medium, high}, suggested_action, status ∈ {open, acknowledged, in_progress, resolved, dismissed}, assignee_id, resolution_note, ai_source_id FK → project_risk_summaries, resolution_category, follow_up_required, effectiveness, reopen_count, priority_score, resolved_at, created_by, created_at, updated_at`.
- RLS: org-scoped SELECT; INSERT/UPDATE gated to `['super_admin', 'admin', 'hr_admin', 'manager']`.
- Linkage key: `risk_actions.ai_source_id` → `project_risk_summaries.id`.

### Conclusion

- **No source-of-truth discrepancy this round.** Unlike 2.2 (LLM-blocked) and 2.3 (generate-blocked), `getLinkedRiskActions` is a pure read flow with no server-only secrets. iOS 2.4 can faithfully replicate both steps.
- "转为风险动作" sync (write path, role-gated) + resolution feedback + governance intervention + recent resolutions remain Web-only **by scope** (devprompt §3.G), not by source-of-truth divergence.

## iOS 2.4 Deliverables

### `Brainstorm+/Features/Projects/ProjectDetailModels.swift`

- New public struct `ProjectLinkedRiskAction: Identifiable, Codable, Hashable` → `id: UUID`, `title: String`, `status: String`, `severity: String`, `aiSourceId: UUID?`.
- `CodingKeys` map `ai_source_id` → `aiSourceId`. Matches Web's select projection exactly (`id, title, status, severity, ai_source_id`).
- `status` / `severity` decoded as `String` (not typed enums) so future server vocabulary expansion degrades gracefully. UI styling defends via switches with neutral fallback.
- Doc comment cites Web source lines (597-626 for the server action, 687-724 for the renderer) + records 3-row render cap + records "转为风险动作" sync as explicitly Web-only.

### `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`

- New public `enum LinkedRiskActionsPhase: Equatable { case idle, loading, noRiskAnalysisSource, empty, loaded }` + three new `@Published` properties after `riskAnalysisErrorMessage`:
  - `linkedRiskActions: [ProjectLinkedRiskAction] = []`
  - `linkedRiskActionsPhase: LinkedRiskActionsPhase = .idle`
  - `linkedRiskActionsErrorMessage: String? = nil` — side-band error surface.
- `applyDeniedState()` extended to clear all three linked-actions fields.
- New `public func refreshLinkedRiskActions() async` entry point:
  - Captures `priorPhase` before flipping `linkedRiskActionsPhase = .loading` and clearing `linkedRiskActionsErrorMessage`.
  - **Step 1 (anchor lookup)**: `project_risk_summaries.select("id").eq("project_id", value: projectId).limit(1).execute().value` as `[LinkedRiskAnchorRow]`. Zero rows → `linkedRiskActions = []`, phase `.noRiskAnalysisSource`, returns.
  - **Step 2 (filtered select)**: `risk_actions.select("id, title, status, severity, ai_source_id").eq("ai_source_id", value: anchor.id).order("created_at", ascending: false).limit(20).execute().value` as `[ProjectLinkedRiskAction]`. Phase `.empty` when zero, `.loaded` when non-empty.
  - **Failure path**: preserves prior `linkedRiskActions` snapshot (transient flakiness doesn't wipe valid context), writes `linkedRiskActionsErrorMessage`, reverts phase to `priorPhase` (or `.idle` if `priorPhase == .loading`). Does NOT touch `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `summaryErrorMessage`, `riskAnalysisErrorMessage`, `access`.
- Private Decodable DTO `LinkedRiskAnchorRow: Decodable { let id: UUID }` kept inside the VM (risk-anchor-specific, not public surface).

### `Brainstorm+/Features/Projects/ProjectDetailView.swift`

- New `linkedRiskActionsSection` inserted AFTER `riskAnalysisSection`, BEFORE `errorMessage` banner + `foundationScopeNote`.
- Section header: "Linked Risk Actions" + conditional "{N} linked" count badge (only in `.loaded` with non-empty list).
- Subtitle: "Read-only · converting a risk into an action is only available on the web."
- `@ViewBuilder linkedRiskActionsBody` switching on phase:
  - `.idle` / `.loading` → `EmptyView()` (button carries the state).
  - `.noRiskAnalysisSource` → hint: "No risk analysis has been generated on the web yet — risk actions are linked to that analysis."
  - `.empty` → hint: "No risk actions have been linked yet."
  - `.loaded` → `ForEach(linkedRiskActions.prefix(3))` of `linkedRiskActionRow` + "+ N more on the web dashboard" overflow hint when `count > 3`.
- `linkedRiskActionRow(for:)` = 8pt circle status dot + title (2 lines) + severity capsule.
- `linkedActionStatusColor(for:)`: `resolved`→green, `in_progress`→blue, `open`→warning, `acknowledged`→primary, `dismissed`/default→textSecondary.
- `linkedActionSeverityStyle(for:)`: `high`→white on `Color.red`, `medium`→warning on warning×18%, `low`→primary on primaryLight, unknown/default→textSecondary on gray×15%.
- Button state machine:
  - `.idle` → `Label("Check for linked actions", systemImage: "link")`.
  - `.loading` → `Label("Checking…", systemImage: "link")` + ProgressView + disabled.
  - `.loaded` / `.empty` / `.noRiskAnalysisSource` → `Label("Refresh", systemImage: "arrow.clockwise")`.
  - Error (side-band) → `Label("Try again", systemImage: "arrow.clockwise")`.
  - Disabled while `isLoading || isDeleting`.
- Button tap fires `Task { await viewModel.refreshLinkedRiskActions() }`.
- Soft scoped error row reuses existing `summaryErrorRow(_:)` builder.
- `foundationScopeNote` copy updated: "Converting risks into actions and resolution feedback are available on the web and will arrive in later iOS rounds." (supersedes 2.3's copy.)
- Visual language reuses existing `enrichmentCard` token — no new design token, no new corner radius.

### Files NOT touched

- `Brainstorm+/Core/Models/Project.swift`, `TaskModel.swift` — unchanged.
- `Brainstorm+/Features/Projects/ProjectCardView.swift`, `ProjectListView.swift`, `ProjectListViewModel.swift` — unchanged.
- `Brainstorm+/Features/Projects/ProjectEditSheet.swift`, `ProjectEditViewModel.swift`, `ProjectMemberCandidate.swift` — unchanged.
- `Brainstorm+/Shared/Navigation/AppModule.swift` — unchanged; `.projects` remains `.partial`.
- Database schema, RLS, indexes, views — untouched.
- No new HTTP endpoint, no new Edge Function, no new `api_keys` touchpoint.

## Parity Checklist vs Web `getLinkedRiskActions`

| Dimension | Web | iOS 2.4 | Verdict |
|---|---|---|---|
| Entry point | Auto-fetched inside `loadProjectDetail` | Explicit "Check for linked actions" button tap in `linkedRiskActionsSection` | Divergence (intentional; avoids cascading two extra round-trips into initial detail load) |
| Loading state | N/A (auto-fetch) | `.loading` phase → disabled button + ProgressView | Parity (stronger — explicit affordance) |
| Step 1: anchor lookup table | `project_risk_summaries` | `project_risk_summaries` | Parity |
| Step 1: anchor lookup filter | `.eq('project_id', projectId).maybeSingle()` | `.eq("project_id", value: projectId).limit(1)` + `rows.first` | Parity (Swift SDK lacks `.maybeSingle()`) |
| Step 1: anchor columns | `id` | `id` | Parity |
| Step 1: no-anchor branch | Returns `{ actions: [], error: null }` | Phase `.noRiskAnalysisSource` + honest hint | Parity (stronger — honest empty-source disambiguation) |
| Step 2: table | `risk_actions` | `risk_actions` | Parity |
| Step 2: filter | `.eq('ai_source_id', summary.id)` | `.eq("ai_source_id", value: anchor.id)` | Parity |
| Step 2: columns | `id, title, status, severity, ai_source_id` | `id, title, status, severity, ai_source_id` | Parity |
| Step 2: order | `.order('created_at', { ascending: false })` | `.order("created_at", ascending: false)` | Parity |
| Step 2: limit | `.limit(20)` | `.limit(20)` | Parity |
| Render cap | `linkedActions.slice(0, 3)` | `linkedRiskActions.prefix(3)` | Parity |
| Overflow hint | "还有 N 个动作…" | "+ N more on the web dashboard" | Parity (English foundation copy; i18n debt carried forward) |
| Count badge | `{N} 个已关联动作` | `{N} linked` | Parity |
| Row visual | Status dot + truncated title + severity capsule | Status dot + truncated title + severity capsule | Parity |
| Status color mapping | Web palette | Defensive switch (resolved=green, in_progress=blue, open=warning, acknowledged=primary, dismissed/default=textSecondary) | Parity (neutral fallback on unknown values) |
| Severity color mapping | Web palette | Defensive switch (high=red, medium=warning, low=primary, unknown=textSecondary) | Parity (neutral fallback on unknown values) |
| Empty list | N/A (hidden) | Phase `.empty` + "No risk actions have been linked yet." hint | Parity (stronger — honest empty-list disambiguation) |
| Failure surface | Inline `aiError` row | `linkedRiskActionsErrorMessage` scoped row | Parity (decorative) |
| Failure isolation | N/A | `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `summaryErrorMessage`, `riskAnalysisErrorMessage`, `access` untouched; prior list snapshot preserved | Parity (stronger) |
| Phase revert on failure | N/A | `priorPhase` captured + restored so UI doesn't get stuck on "Loading…" | Parity (stronger) |
| "转为风险动作" sync button | Rendered | Not rendered | **Deferred by scope (devprompt §3.G)** |
| Resolution feedback | Rendered | Not rendered | **Deferred by scope (2.5+)** |
| Governance intervention | Rendered | Not rendered | **Deferred by scope (2.5+)** |
| Recent resolutions | Rendered | Not rendered | **Deferred by scope (2.5+)** |
| Assignee hydrate | Not in preview (only detail modal) | Not rendered | Parity at preview scope |

## State Machine

- `.idle`: initial state. `linkedRiskActions == []`, `linkedRiskActionsErrorMessage == nil`. Button: "Check for linked actions".
- `.loading`: `refreshLinkedRiskActions()` in flight. Button: "Checking…" + disabled + ProgressView.
- `.noRiskAnalysisSource`: step 1 returned zero rows — no risk analysis has been generated on the web yet for this project. Honest hint shown. Button: "Refresh" (re-tap to re-check; useful if the web dashboard runs the analysis in the meantime).
- `.empty`: step 1 found an anchor, step 2 returned zero linked actions. Honest hint shown. Button: "Refresh".
- `.loaded`: step 1 + step 2 succeeded with non-empty list. Rows rendered, count badge shown. Button: "Refresh".
- **Failure (side-band)**: `linkedRiskActionsErrorMessage != nil`. Phase reverted to `priorPhase` (or `.idle`). Prior `linkedRiskActions` snapshot preserved. Scoped error row shown. Button: "Try again".
- **Denied**: `applyDeniedState()` clears all three linked-action fields; section hidden via existing access gate (same pattern as other detail sections).

## Verification

- Scan pattern (devprompt §4.1): `'risk analysis|Risk Analysis|linkedRiskActions|linked risk|getLinkedRiskActions|risk_actions|riskSummary|riskLevel|project_risk|generateProjectRiskAnalysis|getProjectRiskMeta|ai_source_id|转为风险动作|resolution feedback|ProjectDetailView|ProjectDetailViewModel|errorMessage|deleteErrorMessage|summaryErrorMessage|riskAnalysisErrorMessage|linkedRiskActionsErrorMessage|projects|tasks|daily|weekly|AppModule|implementationStatus'`.
- Scan scope: `Brainstorm+/Features/Projects`.
- Scan count: 429 occurrences across 9 files.
- Build: `** BUILD SUCCEEDED **` on `iPhone 17 Pro Max` destination with `CODE_SIGNING_ALLOWED=NO`.

## Known Debt Carried Forward

- **"转为风险动作" sync from iOS** (`syncRiskFromDetection`): deferred by scope. Write path, role-gated, belongs with a later write-path round.
- **Resolution feedback** (`getProjectRiskResolutionSummary`, governance intervention, recent resolutions): deferred by scope — natural 2.5+ target.
- **Generate risk analysis from iOS** (2.3 carry-over): deferred (source-of-truth discrepancy) pending Web-side `/api/ai/project-risk` HTTP endpoint or Supabase Edge Function.
- **LLM-generated narrative on AI summary** (2.2 carry-over): deferred behind Web-side `/api/ai/project-summary`.
- **Assignee hydrate on linked actions**: not resolved in 2.4. Belongs with a later "linked action detail modal" round.
- **Auto-fetch on detail load**: iOS gates linked-action fetch behind an explicit tap (Web auto-fetches). Recorded as foundation divergence — intentional to avoid cascading round-trips.
- **`risk_items` JSONB**: not parsed. A later round could group actions by risk item.
- **Status / severity palette debt**: `high` severity uses `Color.red` directly; `in_progress` status uses `Color.blue` directly. Brand tokens would replace these.
- **Re-fetch-on-write coherence**: no auto-refresh when risk analysis / tasks change; user taps "Refresh". Foundation-acceptable.
- **RLS trust**: relies on `risk_actions` + `project_risk_summaries` RLS policies — same posture as every other direct Supabase read in the Projects module.
- **Locale-aware copy**: English-only — belongs with broader iOS i18n.
- **Source-of-truth divergence on task count** (2.1): iOS list card shows task count, Web does not — still open on the Web side.
- Carry-overs from 1.5–2.3: client-side `filteredProjects`, client-side `AccessOutcome` role normalization, batched `.in("id", values: ids)` hydrate in lieu of nested selects, `AsyncImage` non-persistent cache, date-only `String` fields, absence of `.maybeSingle()`, task-count aggregate scaling.
- 13 modules still on `ParityBacklogDestination`.
- Assignee picker still deferred from 1.1.
- Nested `NavigationStack` in `ProjectListView` inherited from 1.3 pattern.

## Recommended Next Round (post Winston 2.4 PASS)

- **Option A (recommended): Resolution feedback foundation on detail** — read-only surface of `getProjectRiskResolutionSummary` (governance intervention status + recent resolutions list). Stays inside native Supabase reads + read-only; closes the remaining read-only gap alongside 2.4's linked-actions surface. Mirrors 2.4's foundation posture exactly.
- **Option B: "转为风险动作" sync write path** (`syncRiskFromDetection`) — promotes linked-actions from read-only to read+write. Requires role gate, confirmation affordance, and a post-write refresh of the linked-actions list. Write-path scope — naturally follows after resolution feedback read-only is done.
- **Option C: Web-side `/api/ai/project-risk` HTTP endpoint** — lets iOS replace 2.3's read-only posture with a generate+read flow. Requires Web engineering, not iOS.
- Decision to be made after Winston 2.4 audit PASS.
