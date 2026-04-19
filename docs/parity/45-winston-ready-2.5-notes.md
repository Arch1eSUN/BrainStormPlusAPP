# Winston-Ready Notes — Sprint 2.5 (Projects Resolution Feedback Foundation)

## Sprint Scope (as contracted in `devprompt/2.5-projects-resolution-feedback-foundation.md`)

- Close the resolution-feedback-on-detail gap flagged by Winston 2.4 audit's "Recommended next round".
- Ship a first-class `resolutionFeedbackSection` on `ProjectDetailView` with a complete 5-phase state machine (idle / loading / noRiskAnalysisSource / empty / loaded) + side-band error surface + `priorPhase` revert on failure.
- **Read-only** against the same tables Web's `getProjectRiskResolutionSummary(projectId)` server action hits: `project_risk_summaries` (anchor lookup) + `risk_actions` (filtered by `ai_source_id` + ordered `resolved_at DESC NULLS LAST` + `limit 50`). Unlike 2.2 / 2.3, no `askAI()` call, no server-decrypted `api_keys` — the flow is pure Supabase reads plus client-side aggregation, so iOS faithfully replicates it (same parity posture as 2.4).
- Aggregate on-device exactly as Web does client-side: counts (resolved / dismissed / active / followUpRequired / reopenedCount) + `dominantCategory` (most-frequent non-nil `resolution_category`; ties → first-encountered) + top-3 `recentResolutions` filtered to `{resolved, dismissed}`.
- Derive governance signal (`.interventionEffective` / `.needsIntervention` / `.none`) + predictive `isProneToReopen` indicator matching Web's trigger rules exactly.
- Explicitly defer resolution write-back (close / reopen / add effectiveness / add governance note), "转为风险动作" convert-to-action write path, generate-risk-from-iOS, and LLM narrative — all Web-only for now.
- Keep `.projects` on `.partial`.

## Web Source-of-Truth Re-Read (explicit)

### `BrainStorm+-Web/src/lib/actions/summary-actions.ts` (server action)

- `getProjectRiskResolutionSummary(projectId: string)` — `'use server'` function at lines 630-714.
- Two-step read + client-side aggregation:

  ```ts
  // Step 1: anchor lookup — find the project_risk_summaries row id for this project
  const { data: summary, error: summaryError } = await adminDb
    .from('project_risk_summaries')
    .select('id')
    .eq('project_id', projectId)
    .maybeSingle();

  if (summaryError) return { data: null, error: summaryError.message };
  if (!summary) return { data: null, error: null };  // NOT an error

  // Step 2: filtered select on risk_actions
  const { data: rows } = await adminDb
    .from('risk_actions')
    .select('title, status, severity, resolution_category, effectiveness, \
             follow_up_required, reopen_count, resolved_at')
    .eq('ai_source_id', summary.id)
    .order('resolved_at', { ascending: false, nullsFirst: false })
    .limit(50);

  // Step 3: client-side aggregation
  // total             = rows.length
  // resolved          = count where status === 'resolved'
  // dismissed         = count where status === 'dismissed'
  // active            = count where status in {'open', 'acknowledged', 'in_progress'}
  // followUpRequired  = count where follow_up_required === true
  // reopenedCount     = count where (reopen_count ?? 0) > 0
  // dominantCategory  = most-frequent non-nil resolution_category (ties → first-encountered)
  // recentResolutions = rows.filter({resolved|dismissed}).slice(0, 3)
  ```

- Returns `{ data: { total, resolved, dismissed, active, followUpRequired, dominantCategory, reopenedCount, recentResolutions }, error }`.
- **No `askAI()` call.** **No `decryptApiKey()` access.** Pure Supabase read + Swift-level aggregation.
- `total` caps at 50 — matches Web's contract exactly (aggregation over a limit-50 result set).

### `BrainStorm+-Web/src/app/dashboard/projects/page.tsx`

- Lines 725-838: resolution feedback render block.
- Lines 754-758: predictive pulsing rose "易重开" badge when `reopenedCount > 0 && active > 0`.
- Lines 780-796: governance-signal badges:
  - "干预已生效" (green tone) when any recent resolution has `effectiveness === 'effective' && category === 'root_cause_fixed'`.
  - "待治理干预" (red tone) when `reopenedCount > 0 && active > 0` (same trigger as "易重开").
  - Both badges can fire simultaneously; Web renders both, iOS collapses to a single `.needsIntervention` banner (danger trumps success — matches Web's implicit priority).
- Count badges: resolved / dismissed / active / followUpRequired / reopenedCount labeled inline.
- `dominantCategory` labeled via a small `category → 中文 label` map.
- `recentResolutions` top-3 rendered as compact rows (title + status + effectiveness + `resolved_at`).

### `BrainStorm+-Web/src/app/api/`

- Contains `ai/analyze`, `ai/models`, `approval/*`, `attendance/*`, `chat/*`, `auth/*`, `knowledge/*`, `mobile/*` routes. **No `/api/risk-resolution*` or equivalent.**
- `getProjectRiskResolutionSummary` is server-action-only — BUT, unlike 2.2 / 2.3, its guts are pure Supabase reads + client-side aggregation, so iOS CAN faithfully replicate it via direct PostgREST + Swift-level counts/filters.

### Schema (migration `037_round8_risk_knowledge_ai.sql` + extensions 015-017)

- `risk_actions` relevant columns for 2.5:
  - `resolution_category TEXT` — `{root_cause_fixed, workaround_applied, escalated, deferred, false_positive}`.
  - `effectiveness TEXT` — `{effective, partial, ineffective, pending}`.
  - `follow_up_required BOOLEAN DEFAULT false`.
  - `reopen_count INTEGER DEFAULT 0`.
  - `resolved_at TIMESTAMPTZ NULLABLE`.
- RLS: org-scoped SELECT; INSERT/UPDATE gated to `['super_admin', 'admin', 'hr_admin', 'manager']`.
- Linkage key: `risk_actions.ai_source_id` → `project_risk_summaries.id` (shared with 2.4).

### Conclusion

- **No source-of-truth discrepancy this round.** Same parity posture as 2.4 — `getProjectRiskResolutionSummary` is a pure read flow with no server-only secrets. iOS 2.5 can faithfully replicate both the read and the client-side aggregation.
- Resolution write-back (close / reopen / effectiveness / governance note) + "转为风险动作" sync + governance intervention write + LLM narrative + generate-risk-from-iOS remain Web-only **by scope** (devprompt §3.G / carry-overs), not by source-of-truth divergence.

## iOS 2.5 Deliverables

### `Brainstorm+/Features/Projects/ProjectDetailModels.swift`

- New public struct `ProjectResolutionFeedback: Equatable`:
  - Eight stored fields: `total: Int`, `resolved: Int`, `dismissed: Int`, `active: Int`, `followUpRequired: Int`, `dominantCategory: String?`, `reopenedCount: Int`, `recentResolutions: [RecentResolution]`.
  - Nested `RecentResolution: Equatable, Hashable` with `title`, `status`, `category: String?`, `effectiveness: String?`, `resolvedAtRaw: String?`.
  - Nested `GovernanceSignal: Equatable { case none, interventionEffective, needsIntervention }`.
  - Two computed properties: `governanceSignal: GovernanceSignal` (mirrors Web's derivation; `.needsIntervention` wins priority when both fire) and `isProneToReopen: Bool` (true when `reopenedCount > 0 && active > 0`).
- `resolvedAtRaw` kept as `String?` so both `timestamptz` formats (with/without fractional seconds) decode; UI parses on render.
- Doc comment cites Web source lines (630-714 for the server action, 725-838 for the renderer) + records client-side aggregation pattern + records `total` capping at 50 matches Web exactly (not a bug) + records governance priority resolution + records no source-of-truth discrepancy posture.

### `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`

- New public `enum ResolutionFeedbackPhase: Equatable { case idle, loading, noRiskAnalysisSource, empty, loaded }` (mirrors 2.4's 5-phase pattern).
- Three new `@Published` properties after the 2.4 linked-actions block:
  - `resolutionFeedback: ProjectResolutionFeedback? = nil`
  - `resolutionFeedbackPhase: ResolutionFeedbackPhase = .idle`
  - `resolutionFeedbackErrorMessage: String? = nil` — side-band error surface.
- `applyDeniedState()` extended to clear all three resolution-feedback fields.
- New `public func refreshResolutionFeedback() async`:
  - Captures `priorPhase` before flipping `resolutionFeedbackPhase = .loading` and clearing `resolutionFeedbackErrorMessage`.
  - **Step 1 (anchor lookup)**: `project_risk_summaries.select("id").eq("project_id", value: projectId).limit(1).execute().value` as `[LinkedRiskAnchorRow]`. Zero rows → `resolutionFeedback = nil`, phase `.noRiskAnalysisSource`, returns.
  - **Step 2 (filtered select)**: `risk_actions.select("title, status, severity, resolution_category, effectiveness, follow_up_required, reopen_count, resolved_at").eq("ai_source_id", value: anchor.id).order("resolved_at", ascending: false, nullsFirst: false).limit(50).execute().value` as `[ResolutionFeedbackRow]`. Zero rows → `.empty` + `resolutionFeedback = nil`. Non-empty → `.loaded` + `resolutionFeedback = Self.aggregateResolutionFeedback(rows:)`.
  - **Failure path**: preserves prior `resolutionFeedback` snapshot, writes `resolutionFeedbackErrorMessage`, reverts phase to `priorPhase` (or `.idle` if `priorPhase == .loading`). Does NOT touch `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `summaryErrorMessage`, `riskAnalysisErrorMessage`, `linkedRiskActionsErrorMessage`, `access`.
- Private Decodable DTO `ResolutionFeedbackRow` with the 8 fields Web's select reads; `CodingKeys` maps snake_case → camelCase. Kept private to the VM.
- Reuses existing private `LinkedRiskAnchorRow` (introduced in 2.4) for the step-1 anchor lookup — both flows share the `project_risk_summaries.id` shape.
- New private static `aggregateResolutionFeedback(rows:) -> ProjectResolutionFeedback`: runs Web's exact counts, builds `dominantCategory` with first-encountered tie-break (stable because rows arrive `resolved_at DESC NULLS LAST`), slices top-3 resolved/dismissed into `recentResolutions`.
- Verified Supabase Swift SDK signature `order(_:ascending:nullsFirst:referencedTable:)` at `PostgrestTransformBuilder.swift:44` — `nullsFirst: false` is real; usage correct.

### `Brainstorm+/Features/Projects/ProjectDetailView.swift`

- New `resolutionFeedbackSection` inserted AFTER `linkedRiskActionsSection`, BEFORE `errorMessage` banner + `foundationScopeNote`.
- Section header: "Resolution Feedback" + conditional "{total} tracked" count badge (only shown in `.loaded`).
- Subtitle: "Read-only · resolution write-back and governance interventions are only available on the web."
- `@ViewBuilder resolutionFeedbackBody` switching on phase:
  - `.idle` / `.loading` → `EmptyView()` (button carries the state).
  - `.noRiskAnalysisSource` → hint: "No risk analysis exists for this project yet. Run one from the web dashboard first, then come back to view its resolution feedback here."
  - `.empty` → hint: "No risk actions tracked yet for this analysis, so there's no resolution feedback to aggregate."
  - `.loaded` → composable stack: `resolutionCountsRow` + conditional `governanceBanner` + conditional `dominantCategoryRow` + `recentResolutionsList` (top-3).
- `resolutionCountsRow`: horizontal-scroll pill strip of 5 badges — Resolved (primary/primaryLight), Dismissed (textSecondary/gray×15%), Active (warning/warning×18%), Follow-up (warning/warning×18%), Reopened (white/red×85%).
- `governanceBanner`: icon + title + optional "Prone to reopen · {N} reopened action(s) still have unresolved work." sub-line. Tones:
  - `.interventionEffective` → `checkmark.shield.fill` + "Intervention effective" + primary tone.
  - `.needsIntervention` → `exclamationmark.shield.fill` + "Needs governance intervention" + warning tone.
- `dominantCategoryRow`: tag icon + "Dominant category" + humanized label (`root_cause_fixed` → `Root Cause Fixed`) via `Self.humanize(_:)`.
- `recentResolutionRow`: 8pt status dot (via `resolutionStatusColor(_:)`) + title (2 lines) + effectiveness capsule + parsed `resolved_at` date. Date parsing via `resolvedAtDisplayDate(_:)` tries both `.withInternetDateTime` and `.withFractionalSeconds` — returns `nil` on parse failure so render drops the date element rather than crashing.
- `effectivenessStyle(for:)`: effective → primary/primaryLight, partial → warning/warning×18%, ineffective → white/red×85%, pending → textSecondary/gray×15%, unknown → humanized label on neutral.
- `resolutionStatusColor(_:)`: narrow palette (recent list only surfaces resolved|dismissed) — resolved → green, dismissed/default → textSecondary.
- `governanceStyle(for:)`: each signal → (title, foreground, background) tokens; `.none` branch is dead-code defensive.
- Button state machine (`resolutionFeedbackActionButton`):
  - `.idle` → `Label("Check for resolution feedback", systemImage: "checkmark.seal")`.
  - `.loading` → "Checking…" + ProgressView + disabled.
  - `.loaded` / `.empty` / `.noRiskAnalysisSource` → "Refresh".
  - Error (side-band) → "Try again".
  - Disabled while `isLoading || isDeleting`.
- Button tap fires `Task { await viewModel.refreshResolutionFeedback() }`.
- Soft scoped error row reuses existing `summaryErrorRow(_:)` builder.
- `foundationScopeNote` copy updated: "Converting risks into actions and generating new risk analyses from iOS are available on the web and will arrive in later iOS rounds." (supersedes 2.4's copy — "resolution feedback" removed from the deferred list since 2.5 closed that gap.)
- Visual language reuses existing `enrichmentCard` token — no new design token, no new corner radius.

### Files NOT touched

- `Brainstorm+/Core/Models/Project.swift`, `TaskModel.swift` — unchanged.
- `Brainstorm+/Features/Projects/ProjectCardView.swift`, `ProjectListView.swift`, `ProjectListViewModel.swift` — unchanged.
- `Brainstorm+/Features/Projects/ProjectEditSheet.swift`, `ProjectEditViewModel.swift`, `ProjectMemberCandidate.swift` — unchanged.
- `Brainstorm+/Shared/Navigation/AppModule.swift` — unchanged; `.projects` remains `.partial`.
- Database schema, RLS, indexes, views — untouched.
- No new HTTP endpoint, no new Edge Function, no new `api_keys` touchpoint.
- No write path into `risk_actions` (no status transitions, no effectiveness writes, no governance notes, no resolution_category writes).

## Parity Checklist vs Web `getProjectRiskResolutionSummary`

| Dimension | Web | iOS 2.5 | Verdict |
|---|---|---|---|
| Entry point | Auto-fetched inside `loadProjectDetail` | Explicit "Check for resolution feedback" button tap | Divergence (intentional; avoids cascading round-trips) |
| Step 1: anchor lookup table | `project_risk_summaries` | `project_risk_summaries` | Parity |
| Step 1: anchor filter | `.eq('project_id').maybeSingle()` | `.eq("project_id", value: projectId).limit(1)` + `rows.first` | Parity (Swift SDK lacks `.maybeSingle()`) |
| Step 1: anchor columns | `id` | `id` | Parity |
| Step 1: no-anchor branch | Returns `{ data: null, error: null }` | Phase `.noRiskAnalysisSource` + honest hint | Parity (stronger — honest empty-source disambiguation) |
| Step 2: table | `risk_actions` | `risk_actions` | Parity |
| Step 2: filter | `.eq('ai_source_id', summary.id)` | `.eq("ai_source_id", value: anchor.id)` | Parity |
| Step 2: columns | `title, status, severity, resolution_category, effectiveness, follow_up_required, reopen_count, resolved_at` | identical | Parity |
| Step 2: order | `.order('resolved_at', { ascending: false, nullsFirst: false })` | `.order("resolved_at", ascending: false, nullsFirst: false)` | Parity |
| Step 2: limit | `.limit(50)` | `.limit(50)` | Parity |
| Total aggregation | Client-side over limit-50 result (caps at 50) | Client-side over limit-50 result (caps at 50) | Parity (matches Web exactly) |
| resolved count | `rows.filter(r => r.status === 'resolved').length` | `rows.filter { $0.status == "resolved" }.count` | Parity |
| dismissed count | `rows.filter(r => r.status === 'dismissed').length` | `rows.filter { $0.status == "dismissed" }.count` | Parity |
| active count | `rows.filter(r => ['open','acknowledged','in_progress'].includes(r.status)).length` | Same (Swift) | Parity |
| followUpRequired count | `rows.filter(r => r.follow_up_required === true).length` | `rows.filter { $0.followUpRequired == true }.count` | Parity |
| reopenedCount | `rows.filter(r => (r.reopen_count ?? 0) > 0).length` | `rows.filter { ($0.reopenCount ?? 0) > 0 }.count` | Parity (nullable guarded) |
| dominantCategory | Most-frequent non-nil `resolution_category`; ties → first-encountered | Same; rows already in `resolved_at DESC` so tie-break stable | Parity |
| recentResolutions | `rows.filter({resolved or dismissed}).slice(0, 3)` | `rows.filter { resolved/dismissed }.prefix(3)` | Parity |
| Governance `.interventionEffective` trigger | Any recent resolution with `effectiveness === 'effective' && category === 'root_cause_fixed'` | Same | Parity |
| Governance `.needsIntervention` trigger | `reopenedCount > 0 && active > 0` | Same | Parity |
| Governance priority when both fire | Implicit — both badges render | `.needsIntervention` wins (danger trumps success, documented) | Divergence (single-banner iOS affordance) |
| Predictive "易重开" signal | Pulsing rose badge when `reopenedCount > 0 && active > 0` | `isProneToReopen` sub-line inside governance banner | Parity (different visual affordance, same trigger) |
| Count badges | Rendered inline | Horizontal-scroll pill strip | Parity |
| Dominant category label | `category → 中文 label` map | `humanize(_:)` underscore-strip + Title Case | Parity (English foundation copy) |
| Recent resolution row format | Title + status + effectiveness + `resolved_at` | Same + parsed display date | Parity |
| Effectiveness color mapping | Web palette | Defensive switch (effective/partial/ineffective/pending + unknown neutral) | Parity |
| Failure surface | Silent on Web (empty render) | Scoped warning row with `.localizedDescription` | Parity (iOS stronger) |
| Failure isolation | N/A | All other VM state untouched; prior snapshot preserved | Parity (stronger) |
| Phase revert on failure | N/A | `priorPhase` captured + restored | Parity (stronger) |
| Resolution write-back | Rendered on Web | Not rendered | **Deferred by scope (devprompt §3.G)** |
| Governance intervention write | Rendered on Web | Not rendered | **Deferred by scope (devprompt §3.G)** |
| "转为风险动作" sync button | Rendered on Web | Not rendered | **Deferred by scope (carry-over from 2.4)** |

## State Machine

- `.idle`: initial state. `resolutionFeedback == nil`, `resolutionFeedbackErrorMessage == nil`. Button: "Check for resolution feedback".
- `.loading`: `refreshResolutionFeedback()` in flight. Button: "Checking…" + disabled + ProgressView.
- `.noRiskAnalysisSource`: step 1 returned zero rows. Honest hint shown. Button: "Refresh".
- `.empty`: step 1 found an anchor, step 2 returned zero rows. Honest hint shown. Button: "Refresh".
- `.loaded`: step 1 + step 2 succeeded with non-empty list. Aggregated snapshot rendered. Button: "Refresh".
- **Failure (side-band)**: `resolutionFeedbackErrorMessage != nil`. Phase reverted to `priorPhase` (or `.idle`). Prior `resolutionFeedback` snapshot preserved. Scoped error row shown. Button: "Try again".
- **Denied**: `applyDeniedState()` clears all three resolution-feedback fields; section hidden via existing access gate.

## Verification

- Scan pattern (devprompt §4.1): `'getProjectRiskResolutionSummary|resolution_category|effectiveness|follow_up_required|reopen_count|resolved_at|resolutionFeedback|governance|ProjectResolutionFeedback|GovernanceSignal|isProneToReopen'`.
- Scan scope: `Brainstorm+/Features/Projects`.
- Scan count: **106 occurrences across 3 files** (`ProjectDetailModels.swift: 16`, `ProjectDetailViewModel.swift: 48`, `ProjectDetailView.swift: 42`).
- Build: `** BUILD SUCCEEDED **` on `iPhone 17 Pro Max` destination with `CODE_SIGNING_ALLOWED=NO`.

## Known Debt Carried Forward

- **Resolution write-back** (close / reopen / add effectiveness / add governance note): deferred by scope. `risk_actions.update` requires role gate `['super_admin', 'admin', 'hr_admin', 'manager']`. Natural next write-path target.
- **"转为风险动作" sync from iOS** (`syncRiskFromDetection`): deferred by scope (carry-over from 2.4). Write path, role-gated.
- **Governance intervention write**: deferred by scope. Web-only.
- **Generate risk analysis from iOS** (2.3 carry-over): deferred pending Web-side `/api/ai/project-risk` HTTP endpoint or Supabase Edge Function.
- **LLM-generated narrative on AI summary** (2.2 carry-over): deferred behind Web-side `/api/ai/project-summary`.
- **Assignee hydrate on recent resolutions**: Web preview doesn't surface it either; iOS matches.
- **Auto-fetch on detail load**: iOS gates resolution-feedback fetch behind an explicit tap. Intentional foundation divergence — a future round could auto-invoke `refreshResolutionFeedback()` after a successful `refreshLinkedRiskActions()` (both share the same anchor lookup).
- **Governance priority when both signals fire**: iOS collapses to a single `.needsIntervention` banner; Web renders both badges. Intentional single-banner iOS affordance.
- **`total` caps at 50**: matches Web's contract exactly (aggregation over limit-50 result). Not a bug.
- **Status / severity / category / effectiveness vocabulary expansion**: iOS decodes as `String` + defensive UI switch with neutral fallback.
- **Palette debt**: reopened-count badge + ineffective effectiveness capsule use `Color.red.opacity(0.85)` directly; brand critical/danger token would replace. Shared debt with 2.3 `.critical` / 2.4 high severity.
- **Re-fetch-on-write coherence**: no auto-refresh when risk analysis / linked actions / tasks change; user taps "Refresh". Foundation-acceptable.
- **RLS trust**: relies on `risk_actions` + `project_risk_summaries` RLS policies — same posture as every other direct Supabase read in the Projects module.
- **Locale-aware copy**: English-only — belongs with broader iOS i18n.
- **Source-of-truth divergence on task count** (2.1): iOS list card shows task count, Web does not — still open on the Web side.
- **`risk_items` JSONB on `project_risk_summaries`**: not parsed — belongs with a later surface grouping resolutions by risk item.
- Carry-overs from 1.5–2.4: client-side `filteredProjects`, client-side `AccessOutcome` role normalization, batched `.in("id", values: ids)` hydrate in lieu of nested selects, `AsyncImage` non-persistent cache, date-only `String` fields, absence of `.maybeSingle()`, task-count aggregate scaling.
- 13 modules still on `ParityBacklogDestination`.
- Assignee picker still deferred from 1.1.
- Nested `NavigationStack` in `ProjectListView` inherited from 1.3 pattern.

## Recommended Next Round (post Winston 2.5 PASS)

- **Option A (recommended): "转为风险动作" sync write path** (`syncRiskFromDetection`) — promotes linked-actions from read-only to read+write, naturally following 2.4 read-only + 2.5 aggregated-read. Requires role gate, confirmation affordance, and post-write refresh of BOTH the linked-actions list (2.4) and the resolution-feedback aggregate (2.5) since both are anchored to the same `ai_source_id`.
- **Option B: Resolution write-back (close / reopen / effectiveness / governance note)** — a more focused write round targeting `risk_actions.update`. Same role gate as Option A. Would also need post-write refresh of both 2.4 + 2.5 surfaces.
- **Option C: Web-side `/api/ai/project-risk` HTTP endpoint** — lets iOS replace 2.3's read-only posture with a generate+read flow. Requires Web engineering, not iOS.
- **Option D: Web-side `/api/ai/project-summary` HTTP endpoint** — lets iOS replace 2.2's deterministic synthesis with an LLM-generated narrative. Requires Web engineering.
- Decision to be made after Winston 2.5 audit PASS.
