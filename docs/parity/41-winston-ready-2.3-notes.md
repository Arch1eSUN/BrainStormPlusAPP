# Winston-Ready Notes — Sprint 2.3 (Projects Risk Analysis Foundation)

## Sprint Scope (as contracted in `devprompt/2.3-projects-risk-analysis-foundation.md`)

- Close the risk-analysis-on-detail gap flagged by Winston 2.2 audit's "Recommended next round".
- Ship a first-class `riskAnalysisSection` on `ProjectDetailView` with complete state machine (idle / loading / success / empty-cache / failure / denied), isolated error surface, and honest labeling.
- **Read-only** against Web's persisted `project_risk_summaries` table: iOS cannot invoke `generateProjectRiskAnalysis` (server action with no HTTP exposure + server-side `decryptApiKey()` on `api_keys`), but it CAN read the cached row directly via PostgREST. That's the parity posture.
- Substitute Web's server-only `askAI({ scenario: 'project_risk_analysis' })` generate-step with a **read-only cached-row surface** — record this as an explicit **second-order source-of-truth discrepancy WITH persistence parity** (the iOS surface reflects real Web-generated analysis, unlike 2.2's local synthesis).
- Preserve risk provenance (`generated_at`, `model`) so a future round that exposes `/api/ai/project-risk` can simply add a "generate" button without changing the display binding.
- Keep `.projects` on `.partial`.

## Web Source-of-Truth Re-Read (explicit)

### `BrainStorm+-Web/src/lib/actions/summary-actions.ts` (server action)

- `generateProjectRiskAnalysis(projectId: string, { forceRegenerate?: boolean })` — `'use server'` function at lines 402-557.
- Cache check FIRST (lines 421-442):

  ```ts
  adminDb.from('project_risk_summaries')
    .select('id, summary, risk_level, generated_at, model_used, scenario')
    .eq('project_id', projectId)
    .maybeSingle()
  ```

- If `forceRegenerate` is false and a cached row exists, returns it as `{ ..., meta: { isCached: true } }`.
- On cache miss or force-regenerate, parallel Supabase reads (all via `adminDb`):
  - `projects.select('name, status, progress, start_date, end_date').eq('id', projectId).single()`
  - `tasks.select('title, status, priority, due_date, assignee_id').eq('project_id', projectId).order('created_at' desc).limit(50)`
  - `daily_logs.select('date, content, blockers').eq('project_id', projectId).order('date' desc).limit(10)`
- LLM call: `askAI({ systemPrompt, userMessage, scenario: 'project_risk_analysis' })` via `src/lib/ai/orchestrator.ts`; scenario config is `maxTokens: 2000, temperature: 0.3, timeoutMs: 45000, maxRetries: 1`; provider credentials decrypted server-side via `decryptApiKey()` from the `api_keys` table.
- Parses risk level from the LLM's first line (LOW / MEDIUM / HIGH / CRITICAL).
- Upserts the result into `project_risk_summaries` (keyed by `project_id`).
- Returns `{ summary, riskLevel, summaryId, meta: { generatedAt, model, scenario, isCached }, error }`.
- **Persistence distinguishes risk from the 2.2 ephemeral summary flow.**

### `BrainStorm+-Web/src/app/dashboard/projects/page.tsx`

- Button entry at lines 609-618 — "AI 风险分析" with `ShieldAlert` icon; calls the server action directly.
- Risk card at lines 643-839 — header, cache badge, risk-level badge, summary, generated-at, model, "转为风险动作" sync button, linked actions preview, resolution feedback badges, governance intervention status, recent resolutions.
- `aiError` inline row at lines 843-853.
- No persistence on the page layer — the table IS the persistence.

### `BrainStorm+-Web/src/app/api/`

- Contains `ai/analyze`, `ai/models` HTTP routes. **No `ai/project-risk` route exists.**
- Server action is the ONLY entry point for `generateProjectRiskAnalysis`. Native iOS cannot reach it over HTTP.

### Companion actions in the same file

- `getProjectRiskMeta(projectId)` at lines 561-593 — read-only metadata. iOS substitutes direct PostgREST read of the same table.
- `getLinkedRiskActions(projectId)` at lines 597-626 — deferred to 2.4+.
- `getProjectRiskResolutionSummary(projectId)` at lines 630-714 — deferred.

### Persistence table

- `project_risk_summaries` columns: `id` (PK), `project_id` (FK, unique), `summary TEXT`, `risk_level TEXT`, `generated_at TIMESTAMPTZ`, `model_used TEXT`, `scenario TEXT`, `generated_by UUID`, `risk_items JSONB`.
- Cache key: `project_id` (one row per project). Upsert-on-regenerate.

### Conclusion

- Web flow is unreachable from iOS over HTTP without either:
  - (a) publishing `/api/ai/project-risk` (future Web-side work), or
  - (b) embedding decrypted provider credentials on-device — forbidden.
- Unlike 2.2, risk analysis PERSISTS. iOS CAN read the cached row directly via PostgREST.
- Devprompt §3.A authorizes a **second-order source-of-truth discrepancy** here: ship a faithful read-only surface of the cached row (parity of display) + defer the generate step (divergence, awaits Web endpoint).
- This gives us **stronger parity than 2.2** — the iOS surface reflects actual Web-generated analysis instead of a local synthesis.

## iOS 2.3 Deliverables

### `Brainstorm+/Features/Projects/ProjectDetailModels.swift`

- New public struct `ProjectRiskAnalysis: Equatable` → `summary: String`, `riskLevel: RiskLevel`, `generatedAt: Date?`, `model: String?`, `scenario: String?`.
- Nested public `enum RiskLevel: String, Equatable { case low, medium, high, critical, unknown }`. Unknown server values map to `.unknown` so decode never fails on values outside the Web-defined set.
- Doc comment records the server-action + persistence-parity framing and contrasts 2.3 (reads real Web-generated data) against 2.2 (local synthesis).

### `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`

- Four new `@Published` properties after `summaryErrorMessage`:
  - `riskAnalysis: ProjectRiskAnalysis? = nil`
  - `isLoadingRiskAnalysis: Bool = false`
  - `riskAnalysisNotYetGenerated: Bool = false` — disambiguates "haven't checked yet" from "checked, no cache".
  - `riskAnalysisErrorMessage: String? = nil` — isolated error surface.
- `applyDeniedState()` extended to clear all four risk fields.
- New `public func refreshRiskAnalysis() async` entry point:
  - Flips `isLoadingRiskAnalysis = true`, clears `riskAnalysisErrorMessage`.
  - Reads `project_risk_summaries.select("summary, risk_level, generated_at, model_used, scenario").eq("project_id", value: projectId).limit(1).execute().value` as `[ProjectRiskRow]` (`.limit(1)` + `rows.first` because Swift SDK lacks `.maybeSingle()`, same pattern as 1.6 membership gate).
  - Success + cached row + non-empty summary: builds `ProjectRiskAnalysis(...)`, sets `riskAnalysis`, sets `riskAnalysisNotYetGenerated = false`.
  - Success + empty cache: `riskAnalysis = nil`, `riskAnalysisNotYetGenerated = true`.
  - Failure: preserves prior `riskAnalysis` snapshot, resets `riskAnalysisNotYetGenerated = false`, writes `riskAnalysisErrorMessage`. Does NOT touch `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `summaryErrorMessage`, `access`.
- Private Decodable DTO `ProjectRiskRow` with `CodingKeys` for snake_case → camelCase mapping.
- Private statics: `parseRiskLevel` (case-insensitive LOW/MEDIUM/HIGH/CRITICAL → enum; anything else `.unknown`), `parseTimestamp` (ISO 8601 fractional → plain fallback; parse failure silently returns `nil`), `iso8601FractionalFormatter`, `iso8601PlainFormatter`.

### `Brainstorm+/Features/Projects/ProjectDetailView.swift`

- New `riskAnalysisSection` inserted AFTER `aiSummarySection`, BEFORE `errorMessage` banner + `foundationScopeNote`.
- Section header: "Risk Analysis" + optional inline risk-level badge.
- Subtitle: "Read-only snapshot · loaded from the web dashboard's most recent analysis. New analyses must be generated on the web."
- Body: soft scoped error row when `riskAnalysisErrorMessage` present; `riskAnalysis?.summary` text + provenance caption (`Generated <time>` + `<model>` joined with ` · `) when resolved; "No risk analysis has been generated on the web yet for this project." hint when `riskAnalysisNotYetGenerated == true`.
- Button state machine:
  - idle → `Label("Check for risk analysis", systemImage: "shield.checkered")`
  - loading → `Label("Checking…", systemImage: "shield.checkered")` + ProgressView + disabled
  - success → `Label("Refresh", systemImage: "arrow.clockwise")`
  - error → `Label("Try again", systemImage: "arrow.clockwise")`
- Button disabled while `isLoadingRiskAnalysis || isDeleting || isGeneratingSummary`.
- Risk-level palette `riskLevelStyle(for:)`:
  - `.low`: primary on primaryLight
  - `.medium`: warning on warning×18%
  - `.high`: white on warning
  - `.critical`: white on `Color.red` (debt: no brand critical token yet)
  - `.unknown`: textSecondary on gray×15%
- Visual language reuses existing `enrichmentCard` token.
- `foundationScopeNote` copy updated: "Linked risk actions and resolution feedback are available on the web and will arrive in a later iOS round." (supersedes 2.2's copy).

### Files NOT touched

- `Brainstorm+/Core/Models/Project.swift`, `TaskModel.swift` — unchanged.
- `Brainstorm+/Features/Projects/ProjectCardView.swift`, `ProjectListView.swift`, `ProjectListViewModel.swift` — unchanged.
- `Brainstorm+/Features/Projects/ProjectEditSheet.swift`, `ProjectEditViewModel.swift`, `ProjectMemberCandidate.swift` — unchanged.
- `Brainstorm+/Shared/Navigation/AppModule.swift` — unchanged; `.projects` remains `.partial`.
- Database schema, RLS, indexes, views — untouched.
- No new HTTP endpoint, no new Edge Function, no new `api_keys` touchpoint.

## Parity Checklist vs Web `generateProjectRiskAnalysis`

| Dimension | Web | iOS 2.3 | Verdict |
|---|---|---|---|
| Entry point | "AI 风险分析" button on dashboard | "Check for risk analysis" button inside `riskAnalysisSection` on detail | Parity (different page, same affordance) |
| Loading state | Inline spinner + disabled button | `isLoadingRiskAnalysis` → `ProgressView` + disabled | Parity |
| Cache-first read | `project_risk_summaries.maybeSingle()` | `project_risk_summaries.limit(1).first` | Parity |
| Columns selected | `id, summary, risk_level, generated_at, model_used, scenario` | `summary, risk_level, generated_at, model_used, scenario` (no `id` — not rendered) | Parity (equivalent data) |
| Risk level display | `RISK_LEVEL_COPY` badge | `riskLevelBadge(for:)` with equivalent palette | Parity |
| Summary render | `ReactMarkdown` | `Text(...)` verbatim (no Markdown in foundation scope) | Divergence (documented debt) |
| Provenance caption | `generated_at` + `model_used` + `isCached` badge | `generated_at` + `model` joined with ` · ` | Parity (isCached omitted, see below) |
| `isCached` badge | Rendered | Not surfaced — every visible iOS snapshot is cached by construction | Acceptable divergence |
| Empty cache | Regenerates server-side | Honest "No risk analysis has been generated…" hint | Divergence (recorded source-of-truth discrepancy) |
| Force-regenerate | `{ forceRegenerate: true }` path | Not implemented (can't call `askAI()`) | **Divergence (source-of-truth discrepancy, recorded)** |
| LLM generate | `askAI({ scenario: 'project_risk_analysis' })` server-side | Not reachable from iOS | **Divergence (source-of-truth discrepancy, recorded)** |
| Persistence | Upsert into `project_risk_summaries` | Read-only | Parity on read; generate deferred |
| `summaryId` | Returned + used to link actions | Not surfaced | Deferred (linked actions = 2.4+) |
| `risk_items` JSONB | Parsed on Web | Not parsed | Deferred (linked actions = 2.4+) |
| Linked risk actions | Rendered | Not rendered | Deferred (2.4+) |
| Resolution feedback | Rendered | Not rendered | Deferred (2.5+) |
| "转为风险动作" sync | Rendered | Not rendered | Deferred (2.4+) |
| Failure surface | `aiError` inline row | `riskAnalysisErrorMessage` scoped row | Parity (decorative) |
| Failure isolation | N/A (separate action) | `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `summaryErrorMessage`, `access` untouched | Parity (even stronger) |

## State Machine

- `idle`: `riskAnalysis == nil`, `isLoadingRiskAnalysis == false`, `riskAnalysisNotYetGenerated == false`, `riskAnalysisErrorMessage == nil`. Button: "Check for risk analysis".
- `loading`: `isLoadingRiskAnalysis == true`. Button: "Checking…" + disabled + ProgressView.
- `success`: `riskAnalysis != nil`, `riskAnalysisErrorMessage == nil`. Button: "Refresh".
- `empty-cache`: `riskAnalysis == nil`, `riskAnalysisNotYetGenerated == true`, `riskAnalysisErrorMessage == nil`. Honest hint shown. Button: "Check for risk analysis" (re-tap to re-check; useful if the web dashboard runs the analysis in the meantime).
- `failure`: `riskAnalysisErrorMessage != nil`. Prior `riskAnalysis` snapshot preserved. Button: "Try again".
- `denied`: `applyDeniedState()` clears all four risk fields; section hidden via existing access gate (same pattern as other detail sections).

## Verification

- Scan pattern (devprompt §4.1): `'risk analysis|Risk Analysis|riskSummary|riskLevel|project_risk|generateProjectRiskAnalysis|getProjectRiskMeta|linked risk|resolution feedback|ProjectDetailView|ProjectDetailViewModel|errorMessage|deleteErrorMessage|summaryErrorMessage|projects|tasks|daily|weekly|AppModule|implementationStatus'`.
- Scan scope: `Brainstorm+/Features/Projects`.
- Scan count: 350 occurrences across 9 files.
- Build: `** BUILD SUCCEEDED **` on `iPhone 17 Pro Max` destination with `CODE_SIGNING_ALLOWED=NO`.

## Known Debt Carried Forward

- **Generate-from-iOS**: deferred (second-order source-of-truth discrepancy) pending Web-side `/api/ai/project-risk` HTTP endpoint or Supabase Edge Function.
- **Linked risk actions** (`getLinkedRiskActions`, "转为风险动作" sync): absent on iOS — natural 2.4 target (stays inside native Supabase reads).
- **Resolution feedback** (`getProjectRiskResolutionSummary`, governance intervention, recent resolutions): absent on iOS — 2.5+ target.
- **LLM-generated narrative on AI summary** (2.2 carry-over): still deferred behind Web-side `/api/ai/project-summary`.
- **`isCached` badge**: not surfaced — every visible iOS snapshot is cached by construction.
- **`summaryId`**: not surfaced — only needed when linking risk actions.
- **`risk_items` JSONB**: not parsed — belongs with linked actions.
- **Markdown rendering**: risk summary rendered as plain `Text` (Web uses `ReactMarkdown`). A later round could add lightweight Markdown or an `AttributedString(markdown:)` pass.
- **`.critical` palette debt**: uses `Color.red` directly; a `Color.Brand.critical` token would remove the fallback.
- **Timestamp silent fallback**: unparseable `generated_at` silently omits the time. Foundation-acceptable.
- **Re-fetch-on-write coherence**: no auto-refresh when project / tasks change; user taps "Refresh". Foundation-acceptable.
- **RLS trust**: relies on `project_risk_summaries` RLS policies — same posture as every other direct PostgREST read in the Projects module.
- **Locale-aware copy**: English-only — belongs with broader iOS i18n.
- **Source-of-truth divergence on task count** (2.1): iOS list card shows task count, Web does not — still open on the Web side.
- Carry-overs from 1.5–2.2: client-side `filteredProjects`, client-side `AccessOutcome` role normalization, batched `.in("id", values: ids)` hydrate in lieu of nested selects, `AsyncImage` non-persistent cache, date-only `String` fields, absence of `.maybeSingle()`, task-count aggregate scaling.
- 13 modules still on `ParityBacklogDestination`.
- Assignee picker still deferred from 1.1.
- Nested `NavigationStack` in `ProjectListView` inherited from 1.3 pattern.

## Recommended Next Round (post Winston 2.3 PASS)

- **Option A (recommended): Linked risk actions foundation on detail** — read-only list of risk actions linked via `ai_source_id = project_risk_summaries.id`. Stays inside native Supabase reads and follows the 2.3 read-only foundation pattern exactly. Prerequisite for later "转为风险动作" sync parity.
- **Option B: Web-side `/api/ai/project-risk` HTTP endpoint** — lets iOS replace the read-only posture with a generate+read flow. Requires Web engineering, not iOS.
- **Option C: Resolution feedback foundation** — smallest standalone read-only surface (`getProjectRiskResolutionSummary`). Independent of linked actions. Could leapfrog A if governance intervention visibility becomes a higher stakeholder ask.
- Decision to be made after Winston 2.3 audit PASS.
