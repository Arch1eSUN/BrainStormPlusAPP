# Winston-Ready Notes — Sprint 2.2 (Projects AI Summary Foundation)

## Sprint Scope (as contracted in `devprompt/2.2-projects-ai-summary-foundation.md`)
- Close the AI-summary-on-detail gap flagged by Winston 2.1 audit.
- Ship a first-class `aiSummarySection` on `ProjectDetailView` with complete state machine (idle / loading / success / failure), isolated error surface, and honest labeling.
- Mirror Web's input-gathering step (parallel Supabase reads against `tasks(30)` + `daily_logs(10)` + `weekly_reports(3)`) with identical columns / filters / limits / ordering.
- Substitute Web's server-only `askAI({ scenario: 'project_summary' })` LLM call with a deterministic facts-only **local synthesis** — record this as an explicit **second-order source-of-truth discrepancy** (Web flow exists but is unreachable from native iOS because it's a server action, not an HTTP route, and decrypts `api_keys` on the server).
- Preserve raw counts on `ProjectSummaryFoundation.facts` so a future round can swap the synthesis step without changing the UI binding.
- Keep `.projects` on `.partial`.

## Web Source-of-Truth Re-Read (explicit)

### `BrainStorm+-Web/src/lib/actions/summary-actions.ts` (server action)
- `generateProjectSummary(projectId: string)` — `'use server'` file at lines 157-251.
- Parallel Supabase reads (all via `adminDb`):
  - `projects.select('name, status, progress, start_date, end_date').eq('id', projectId).single()`
  - `tasks.select('title, status, priority, due_date').eq('project_id', projectId).order('created_at', { ascending: false }).limit(30)`
  - `daily_logs.select('date, content, progress, blockers').eq('project_id', projectId).order('date', { ascending: false }).limit(10)`
  - `weekly_reports.select('week_start, summary, highlights, challenges').contains('project_ids', [projectId]).order('week_start', { ascending: false }).limit(3)`
- No-data short-circuit: `{ summary: '', error: '项目暂无足够数据生成摘要' }` when `contextParts.length <= 1`.
- LLM call: `askAI({ systemPrompt, userMessage, scenario: 'project_summary' })` via `src/lib/ai/orchestrator.ts`; scenario config is `maxTokens: 2000, temperature: 0.4, timeoutMs: 30000, maxRetries: 1`; provider credentials decrypted server-side via `decryptApiKey()` from the `api_keys` table.
- Returns `{ summary: string, error: string | null }`. Ephemeral — not persisted to any table.

### `BrainStorm+-Web/src/app/dashboard/projects/page.tsx`
- Button entry at lines 600-607 calls the server action directly.
- Rendered result at lines 620-630.
- `aiError` toast row at lines 632-642.
- No persistence, no history list.

### `BrainStorm+-Web/src/app/api/`
- Contains `ai/analyze`, `ai/models` HTTP routes. **No `ai/project-summary` route exists.**
- Server action is the ONLY entry point for `generateProjectSummary`. Native iOS cannot reach it.

### Conclusion
- Web flow exists but is unreachable from iOS over HTTP without either:
  - (a) publishing a thin `/api/ai/project-summary` route that calls the server action (future Web-side work), or
  - (b) embedding decrypted provider credentials on-device — forbidden.
- Devprompt §3.A authorizes a **second-order source-of-truth discrepancy** here: ship Web-shape input gathering (parity) + local deterministic synthesis for the LLM step (divergence, deferred).

## iOS 2.2 Deliverables

### `Brainstorm+/Features/Projects/ProjectDetailModels.swift`
- New public struct `ProjectSummaryFoundation: Equatable` → `summary: String`, `generatedAt: Date`, `facts: Facts`.
- Nested `Facts` → `taskTotal`, `taskDone`, `taskInProgress`, `taskOverdue`, `dailyLogCount`, `weeklyReportCount`.
- Doc comment records the Web server-action posture and the `askAI()` deferral rationale.

### `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
- Three new `@Published` properties after `deleteErrorMessage`: `summary`, `isGeneratingSummary`, `summaryErrorMessage`.
- `applyDeniedState()` extended to clear `summary` + `summaryErrorMessage`.
- New `public func generateSummary() async` entry point:
  - Guards on `access == .allowed` + `!isGeneratingSummary`.
  - Flips `isGeneratingSummary = true`, clears `summaryErrorMessage`.
  - Three `async let` parallel PostgREST reads with exact Web shape.
  - No-data branch mirrors Web's `contextParts.length <= 1`: sets honest English copy, does NOT write `summary`, flips `isGeneratingSummary = false`, returns.
  - Success path calls `synthesizeFoundationSummary(...)`, writes `summary`, clears `summaryErrorMessage`.
  - Failure path writes `summaryErrorMessage = error.localizedDescription`, clears `summary = nil`; does NOT touch `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `access`.
- Private DTOs (kept inside VM because summary-specific): `ProjectSummaryTaskRow` (carries `due_date`, which 1.7's `ProjectTaskSummary` does NOT), `ProjectSummaryDailyRow`, `ProjectSummaryWeeklyRow`. Snake_case → camelCase via `CodingKeys`.
- Private `synthesizeFoundationSummary(...)` builds Overview + Tasks + Recent activity + Weekly reports sections joined with `\n\n`. Overdue counting uses a UTC-anchored `yyyy-MM-dd` `DateFormatter` (matches Web's implicit `toISOString().split('T')[0]`).
- Private static formatters: `iso8601DateOnlyFormatter` (UTC, `en_US_POSIX`), `displayDateFormatter` (`MMM d, yyyy`). Helper `humanize(_:)` turns `in_progress` → `In Progress`.

### `Brainstorm+/Features/Projects/ProjectDetailView.swift`
- New `aiSummarySection` inserted AFTER `weeklySummariesSection`, BEFORE `errorMessage` banner + `foundationScopeNote`.
- Section header: "Project Summary" (NOT "AI Summary" — honest labeling).
- Subtitle: "Foundation snapshot · synthesized locally from tasks, daily logs, and weekly reports. LLM narrative arrives in a later round."
- Body: soft scoped error row when `summaryErrorMessage` present; `summary?.summary` text block with generated-at caption when resolved.
- Button state machine: Generate summary / Generating… + ProgressView / Regenerate summary / Try again.
- Button disabled while `isGeneratingSummary || isDeleting`.
- Visual language reuses existing `enrichmentCard` token (`Color.Brand.paper`, 20 pt corner radius, 0.04 shadow).
- `foundationScopeNote` copy updated — drops stale "AI summary" + "task count" references; now reads: "Risk analysis, linked actions, and resolution feedback are available on the web and will arrive in a later iOS round."
- New `private static let generatedAtFormatter: DateFormatter` for the caption.

### Files NOT touched
- `Brainstorm+/Core/Models/Project.swift`, `TaskModel.swift` — unchanged.
- `Brainstorm+/Features/Projects/ProjectCardView.swift`, `ProjectListView.swift`, `ProjectListViewModel.swift` — unchanged.
- `Brainstorm+/Features/Projects/ProjectEditSheet.swift`, `ProjectEditViewModel.swift`, `ProjectMemberCandidate.swift` — unchanged.
- `Brainstorm+/Shared/Navigation/AppModule.swift` — unchanged; `.projects` remains `.partial`.
- Database schema, RLS, indexes, views — untouched.
- No new HTTP endpoint, no new Edge Function, no new `api_keys` touchpoint.

## Parity Checklist vs Web `generateProjectSummary`

| Dimension | Web | iOS 2.2 | Verdict |
|---|---|---|---|
| Entry point | Button on dashboard | Button inside `aiSummarySection` on detail | Parity (different page, same UX affordance) |
| Loading state | Inline spinner + disabled button | `isGeneratingSummary` → `ProgressView` + disabled | Parity |
| Input: `tasks(30)` | `eq('project_id').order('created_at' desc).limit(30)` | `eq("project_id").order("created_at", ascending: false).limit(30)` | Parity |
| Input: `daily_logs(10)` | `eq('project_id').order('date' desc).limit(10)` | `eq("project_id").order("date", ascending: false).limit(10)` | Parity |
| Input: `weekly_reports(3)` | `contains('project_ids', [id]).order('week_start' desc).limit(3)` | `contains("project_ids", value: [id.uuidString]).order("week_start", ascending: false).limit(3)` | Parity |
| Project row | Re-fetched inside server action | Already owned by detail VM | Parity (equivalent data) |
| Parallel dispatch | `Promise.all` | `async let` | Parity |
| No-data branch | Chinese: `'项目暂无足够数据生成摘要'` | English: "Not enough data to generate a summary yet…" | Parity (copy localized) |
| LLM narrative | `askAI({ scenario: 'project_summary' })` server-side | Deterministic facts-only local synthesis | **Divergence (source-of-truth discrepancy, recorded)** |
| Persistence | None | None | Parity |
| Failure surface | `{ error }` → toast | `summaryErrorMessage` → scoped row | Parity (decorative, never clobbers primary) |
| Failure isolation | N/A (separate action) | `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `access` untouched | Parity (even stronger) |

## State Machine
- `idle`: `summary == nil`, `isGeneratingSummary == false`, `summaryErrorMessage == nil`. Button: "Generate summary".
- `loading`: `isGeneratingSummary == true`. Button: "Generating…" + disabled + ProgressView.
- `success`: `summary != nil`, `summaryErrorMessage == nil`. Button: "Regenerate summary".
- `empty (no-data)`: `summary == nil`, `summaryErrorMessage != nil` (honest "Not enough data…" copy). Button: "Try again" (also triggers re-fetch after user adds data).
- `failure`: `summary == nil`, `summaryErrorMessage != nil` (raw `error.localizedDescription`). Button: "Try again".
- `denied`: `applyDeniedState()` clears both `summary` and `summaryErrorMessage`; section hidden via the existing access gate (same pattern as other detail sections).

## Verification
- Scan pattern (devprompt §4.1): `'ai summary|AI summary|summary|generateSummary|refreshSummary|project-summary|ProjectDetailView|ProjectDetailViewModel|errorMessage|deleteErrorMessage|enrichmentErrors|projects|tasks|daily|weekly|AppModule|implementationStatus'`.
- Scan scope: `Brainstorm+/Features/Projects`.
- Scan count: 369 occurrences across 9 files.
- Build: `** BUILD SUCCEEDED **` on `iPhone 17 Pro Max` destination with `CODE_SIGNING_ALLOWED=NO`.

## Known Debt Carried Forward
- LLM-generated narrative deferred (second-order source-of-truth discrepancy) pending Web-side `/api/ai/project-summary` HTTP endpoint.
- Risk analysis / linked risk actions / resolution feedback still absent on iOS.
- Re-fetch-on-write coherence: summary does NOT auto-refresh when underlying tasks/logs/reports change; user taps "Regenerate summary".
- No streaming, no chat UI, no persistence, no history list, no scenario switcher, no prompt editing — matches Web + foundation scope.
- UTC-only overdue comparison; content snippets truncated at 160/160/200 chars; no locale-aware copy; no Markdown parsing on body.
- Source-of-truth divergence on task count (iOS list card shows it, Web does not) still open from 2.1.
- Carry-overs from 1.5 / 1.6 / 1.7 / 1.8 / 1.9 / 2.0 / 2.1: client-side `filteredProjects`, client-side `AccessOutcome` role normalization, batched `.in("id", values: ids)` hydrate in lieu of nested selects, `AsyncImage` non-persistent cache, date-only `String` fields, absence of `maybeSingle()`, task-count query scaling.
- 13 modules still on `ParityBacklogDestination`.
- Assignee picker still deferred from 1.1.
- Nested `NavigationStack` in `ProjectListView` inherited from 1.3 pattern.

## Recommended Next Round (post Winston 2.2 PASS)
- Option A: **Risk analysis foundation on detail** — natural continuation of the detail-surface deepening that 1.6 → 2.2 has followed. Web has a risk analysis surface + linked risk actions + resolution feedback; iOS has none of those. A 2.3 prompt could scope the risk-analysis entry + state machine + list display, leaving linked actions + resolution for 2.4 / 2.5.
- Option B: **Web-side `/api/ai/project-summary` HTTP endpoint** — would let iOS replace the 2.2 local synthesis with the real `askAI()` output. Requires Web engineering, not iOS.
- Decision to be made after Winston 2.2 audit PASS.
