# 48 Winston Audit — 2.5.1 Resolution Feedback Governance Priority Fix

**Round:** `2.5.1 Resolution Feedback Governance Priority Fix`  
**Date:** `2026-04-17`  
**Auditor:** Winston  
**Result:** PASS

## 1. Verdict

`2.5.1 Resolution Feedback Governance Priority Fix` **通过 Winston 独立审计**。

本轮成功修复 `2.5` 的唯一 blocking finding：

- Web governance intervention status 的真实 priority 是 **effective-first**。
- iOS 当前 `ProjectResolutionFeedback.governanceSignal` 已改为 **effective-first**。
- `isProneToReopen` 保持独立 signal，不再与 governance status priority 混淆。
- 构建独立通过：`** BUILD SUCCEEDED **`。

因此 `2.5.1` 可收口，Projects parity 可进入下一正式轮次。

---

## 2. What I Re-Verified

我重新独立核对：

- Ready notes：
  - `docs/parity/47-winston-ready-2.5.1-notes.md`
- iOS implementation：
  - `Brainstorm+/Features/Projects/ProjectDetailModels.swift`
  - `Brainstorm+/Features/Projects/ProjectDetailView.swift`
- Web source of truth：
  - `BrainStorm+-Web/src/app/dashboard/projects/page.tsx`
- Ledger：
  - `progress.md`
  - `findings.md`
  - `task_plan.md`
  - `devprompt/README.md`
- Build：
  - `xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO`
  - Result: `** BUILD SUCCEEDED **`

---

## 3. Source-of-Truth Check

Web code confirms:

```tsx
const hasEffective = resSummary.recentResolutions?.some(
  r => r.effectiveness === 'effective' && r.category === 'root_cause_fixed'
)
const needsIntervention = resSummary.reopenedCount > 0 && resSummary.active > 0
if (hasEffective) return <span>干预已生效</span>
if (needsIntervention) return <span>待治理干预</span>
return null
```

Therefore Web priority is:

1. `hasEffective`
2. `needsIntervention`
3. none

`易重开` predictive badge is a separate rail and still fires when:

```ts
resSummary.reopenedCount > 0 && resSummary.active > 0
```

---

## 4. iOS Fix Verification

`ProjectResolutionFeedback.governanceSignal` now implements:

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

This exactly matches Web priority.

`isProneToReopen` remains:

```swift
reopenedCount > 0 && active > 0
```

This preserves the independent predictive rail.

`ProjectDetailView.governanceBanner(feedback:)` now keeps the prone-to-reopen subline warning-colored even when the governance banner itself is `.interventionEffective` / primary-toned:

```swift
.foregroundColor(Color.Brand.warning)
```

This is consistent with the intended separation:

- Governance status = effective-first
- Prone-to-reopen = independent warning signal

---

## 5. Scope Discipline

2.5.1 did **not** expand scope.

No changes found to:

- two-step read path
- aggregation logic
- phase enum
- state isolation
- AI summary
- risk analysis
- linked actions
- delete/edit/member/task-count flows
- schema / RLS
- Web app
- i18n
- write path / `syncRiskFromDetection`

`.projects` remains `.partial`.

---

## 6. Ledger Consistency

Ledger now correctly states:

- `2.5` audit failed.
- `2.5.1` was created as minimum fix.
- `2.5.1` completed.
- The old “danger trumps success / needsIntervention wins” framing is either removed or retained only as struck-through / historical audit context.

This is acceptable. Historical notes are not rewritten destructively; active state is clear.

---

## 7. Build Verification

Independent build result:

```txt
** BUILD SUCCEEDED **
```

Destination:

```txt
platform=iOS Simulator,name=iPhone 17 Pro Max
```

Signing:

```txt
CODE_SIGNING_ALLOWED=NO
```

---

## 8. Final Decision

**PASS**

Reason:

1. The blocking 2.5 parity issue is fixed.
2. Web effective-first priority is now mirrored exactly.
3. `isProneToReopen` remains independent.
4. Scope remained narrow.
5. Build passed.
6. Ledger is internally consistent.

---

## 9. Recommended Next Round

Recommended next formal round:

- `2.6 Projects Risk Action Sync Write Path Foundation`

Goal:

- Start closing the Web-only `syncRiskFromDetection` / “转为风险动作” gap.

Expected constraints:

- Must mirror Web RBAC gates.
- Must not directly expose secrets.
- Must include confirmation affordance.
- Must refresh linked actions + resolution feedback snapshots after successful write.
- Must keep `.projects = .partial` unless much broader parity closes.
