# 47 Winston Ready — 2.5.1 Resolution Feedback Governance Priority Fix

**Round:** `2.5.1 Resolution Feedback Governance Priority Fix`
**Date:** `2026-04-17`
**Status:** READY — minimum-fix round against Winston 2.5 FAIL (`docs/parity/46-winston-audit-2.5.md`).
**Prompt:** `devprompt/2.5.1-resolution-feedback-governance-priority-fix.md`

## 1. Sprint Scope

2.5.1 is explicitly a **minimum fix round**. Only the single blocking finding from Winston
2.5 is corrected:

- `ProjectResolutionFeedback.governanceSignal` now uses Web's **effective-first** priority
  (`hasEffective` short-circuits before `needsIntervention`).
- `isProneToReopen` is preserved as an independent rail.
- The prone-to-reopen subline in `ProjectDetailView` no longer inherits the governance
  banner tint, so the warning semantic cannot be flattened by a green "Intervention
  effective" banner.
- All ledger language that claimed the inverted priority (`danger trumps success`,
  `needsIntervention wins priority when both fire`, `single-banner affordance`) has been
  rewritten or struck-through with a "Resolved in 2.5.1" note so the audit trail stays
  legible.

Out-of-scope and explicitly forbidden by the 2.5.1 prompt: schema / RLS changes, Web
changes, linked-actions logic, risk-analysis logic, AI-summary logic, delete / edit /
member / task-count logic, write paths, `syncRiskFromDetection`, auto-fetch, i18n, any
broader UI redesign.

`.projects` stays `.partial` (no change).

## 2. Web Source-of-Truth Re-Read

`BrainStorm+-Web/src/app/dashboard/projects/page.tsx` lines 780-796 (verbatim):

```tsx
const hasEffective = resSummary.recentResolutions?.some(
  r => r.effectiveness === 'effective' && r.category === 'root_cause_fixed'
)
const needsIntervention = resSummary.reopenedCount > 0 && resSummary.active > 0
if (hasEffective) return <span>干预已生效</span>
if (needsIntervention) return <span>待治理干预</span>
return null
```

Web priority is therefore:

1. `hasEffective` first
2. `needsIntervention` second
3. none otherwise

The predictive pulsing-rose `易重开` badge at page.tsx lines 754-758 is a separate badge
on a separate rail; it continues to render whenever `reopenedCount > 0 && active > 0`,
even alongside `干预已生效`.

## 3. iOS 2.5.1 Deliverables

### 3.1 `Brainstorm+/Features/Projects/ProjectDetailModels.swift`

`ProjectResolutionFeedback.governanceSignal` (patched):

```swift
public var governanceSignal: GovernanceSignal {
    let effective = recentResolutions.contains { resolution in
        resolution.effectiveness == "effective" && resolution.category == "root_cause_fixed"
    }
    if effective { return .interventionEffective }
    let needs = reopenedCount > 0 && active > 0
    return needs ? .needsIntervention : .none
}
```

Priority now matches Web exactly. `isProneToReopen` is unchanged and documented as an
independent rail.

The `GovernanceSignal` enum docstring is rewritten to remove "matches Web's implicit
priority — the danger badge wins visual attention" and to call out "effective-first" +
independent prone-to-reopen rail explicitly.

### 3.2 `Brainstorm+/Features/Projects/ProjectDetailView.swift`

`governanceBanner(feedback:)` (patched):

- Comment rewritten to describe effective-first priority and the independent `isProneToReopen`
  rail.
- Subline `foregroundColor` changed from `tint.opacity(0.9)` to `Color.Brand.warning`.
  Rationale: when `.interventionEffective` fires, `tint` resolves to
  `Color.Brand.primary` (green). Letting the subline inherit that tint blurs the two
  semantics because prone-to-reopen is always a warning. Using `Color.Brand.warning`
  invariantly keeps the semantic rail visually distinct without restructuring the
  banner layout (no new pill, no new row, no new card, no new token). Header + banner
  background still follow governance tone.

No other View change.

### 3.3 Ledger

- `findings.md` — scope header retitled to 2.5.1, a top "2.5.1 Fix" section added, the
  2.5 "retained verbatim" body preserved beneath, the parity checklist row for
  "Governance priority when both fire" rewritten from "Minor divergence" to "Parity",
  the debt list line for "Governance priority when both signals fire" struck-through
  with a "Resolved in 2.5.1" note.
- `progress.md` — three occurrences of the erroneous priority framing corrected, a new
  "2.5.1 Resolution Feedback Governance Priority Fix delivered" block appended with
  Goals A-F + Verification, "Active" updated to point at Winston 2.5.1.
- `task_plan.md` — `2.5.1 Resolution Feedback Governance Priority Fix completed.` added,
  next step line updated to Winston 2.5.1 audit. Phase 1.x summary rewritten to
  describe the fix.
- `docs/parity/47-winston-ready-2.5.1-notes.md` — this file.

## 4. Parity Checklist (post-fix)

| Dimension | Web behavior | iOS after 2.5.1 | Parity |
|---|---|---|---|
| Two-step read (anchor + filtered select) | Preserved (2.5) | Preserved (2.5) | Parity |
| Client-side aggregation | Preserved (2.5) | Preserved (2.5) | Parity |
| Governance `.interventionEffective` trigger | `effectiveness === 'effective' && category === 'root_cause_fixed'` on any recent resolution | Same | Parity |
| Governance `.needsIntervention` trigger | `reopenedCount > 0 && active > 0` | Same | Parity |
| **Governance priority when both fire** | **effective-first** (`hasEffective` short-circuits) | **`.interventionEffective` wins; `.needsIntervention` only evaluated when effective is false** | **Parity (2.5.1 fix)** |
| Predictive "易重开" / `isProneToReopen` | Pulsing rose badge when `reopenedCount > 0 && active > 0`; **independent** of governance status | Subline rendered whenever `isProneToReopen == true`, including alongside `.interventionEffective`; tinted `Color.Brand.warning` so the semantic is not pulled into the effective banner's primary tone | Parity (different affordance, same trigger, same independence) |
| Banner header tint | Web green / red | iOS primary / warning | Parity |
| Banner background tint | Web green / red | iOS primaryLight×55% / warning×18% | Parity |
| Count badges / dominant category / top-3 recent | Preserved (2.5) | Preserved (2.5) | Parity |
| Resolution write-back | Web only | Still absent on iOS | Deferred by scope |
| "转为风险动作" sync | Web only | Still absent on iOS | Deferred by scope |
| Auto-fetch on detail load | Web auto-fetches | iOS explicit button | Foundation divergence (carried from 2.5) |
| `.projects` parity | — | `.partial` (unchanged) | Parity (no virtual promotion) |

## 5. State Machine

Unchanged from 2.5 — `idle → loading → (noRiskAnalysisSource | empty | loaded)` with
`priorPhase` revert on failure and isolated `resolutionFeedbackErrorMessage`. 2.5.1 only
touches the computed properties on `ProjectResolutionFeedback` and the banner subline
color; no VM edits.

## 6. Verification

- Scan pattern (devprompt §4.1): `'governanceSignal|interventionEffective|needsIntervention|isProneToReopen|danger trumps success|effective-first|hasEffective'`.
- Expected behavior:
  - `governanceSignal`, `interventionEffective`, `needsIntervention`, `isProneToReopen`:
    live hits in code (models + view).
  - `danger trumps success`, `needsIntervention wins priority when both fire`,
    `single-banner affordance`: zero live hits in code and zero live hits in active
    ledger prose. Historical debt lines preserve the phrase inside strike-through /
    "Resolved in 2.5.1" markers for audit trail; the devprompt file itself also retains
    the forbidden phrase inside its "不得再写" directive — both expected.
  - `effective-first`, `hasEffective`: live hits across ledger describing the fix.
- Build command:
  `xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO`
- Build result: **`** BUILD SUCCEEDED **`** (captured 2026-04-17 on `iPhone 17 Pro Max`
  destination with `CODE_SIGNING_ALLOWED=NO`).
- Scan appendix:
  - Code hit count (intended): **24 total across 2 files** — `ProjectDetailModels.swift: 15`,
    `ProjectDetailView.swift: 9`. `ProjectDetailViewModel.swift` is not matched by the
    2.5.1 keyword set (VM did not change this round; governance signal is a computed
    property on the model, and `isProneToReopen` is read by the view helper).
  - `danger trumps success` / `needsIntervention wins priority when both fire` /
    `single-banner affordance` live-text sweep: zero hits in `ProjectDetailModels.swift`
    / `ProjectDetailViewModel.swift` / `ProjectDetailView.swift`. Ledger hits retained
    only inside (a) strike-through "Resolved in 2.5.1" lines, (b) prose explicitly
    describing *which* phrases were removed, (c) the 2.5.1 devprompt's own
    `不得再写` directive, (d) the historical `45-winston-ready-2.5-notes.md` snapshot
    (immutable audit record of the failed round — not allowed to be modified by the
    2.5.1 prompt's "只允许修改" list). All four categories are expected and audit-trail
    legitimate.

## 7. Known Debt (carried from 2.5)

Unchanged from 45-winston-ready-2.5-notes except for:

- The "Governance priority when both signals fire" debt line is **resolved** in this
  round.
- All other debt lines (resolution write-back, governance write, "转为风险动作" sync,
  generate-from-iOS, LLM narrative on summary, auto-fetch divergence, i18n,
  `risk_items` JSONB, palette debt, RLS trust, `total` caps at 50, status vocabulary
  expansion, nested `NavigationStack`) remain as-is and out-of-scope for 2.5.1.

## 8. Recommended Next Round (for Winston to confirm / replace)

Pre-fix recommendation (2.6) is unchanged:

- **"转为风险动作" write path** (`syncRiskFromDetection`): promotes linked-actions from
  read-only to read+write. Requires client-side RBAC mirror
  (`['super_admin', 'admin', 'hr_admin', 'manager']`), confirmation affordance, and a
  post-write refresh of the linked-actions + resolution-feedback snapshots.

Alternative: Web-side `/api/ai/project-risk` HTTP endpoint to unblock generate-risk-from-iOS.

Neither direction is prejudged by 2.5.1.
