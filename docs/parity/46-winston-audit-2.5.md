# 46 Winston Audit — 2.5 Projects Resolution Feedback Foundation

**Round:** `2.5 Projects Resolution Feedback Foundation`  
**Date:** `2026-04-17`  
**Auditor:** Winston  
**Result:** FAIL — minimum fix required

## 1. Verdict

`2.5 Projects Resolution Feedback Foundation` **未通过 Winston 独立审计**。

失败原因不是构建失败，也不是整体方向错误；本轮大部分 read-only foundation 已真实完成。但存在一个必须修正的 **Web source-of-truth parity 偏差**：

> Web 在 `hasEffective` 与 `needsIntervention` 同时成立时，governance intervention status 实际优先显示 **“干预已生效”**；iOS 当前 `ProjectResolutionFeedback.governanceSignal` 写成 **`.needsIntervention` 优先**。

这与本轮 prompt / ready notes 中“matching Web trigger rules exactly / mirrors Web derivation”的要求不一致。

---

## 2. What I Re-Verified

本次审计重新读取并核对：

- Skill：
  - `/Users/archiesun/.agents/skills/audit/SKILL.md`
  - `/Users/archiesun/.agents/skills/frontend-design/SKILL.md`
- iOS：
  - `Brainstorm+/Features/Projects/ProjectDetailModels.swift`
  - `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
  - `Brainstorm+/Features/Projects/ProjectDetailView.swift`
  - `Brainstorm+/Shared/Navigation/AppModule.swift`
- Web source of truth：
  - `BrainStorm+-Web/src/lib/actions/summary-actions.ts`
  - `BrainStorm+-Web/src/app/dashboard/projects/page.tsx`
- Ledger：
  - `docs/parity/45-winston-ready-2.5-notes.md`
  - `progress.md`
  - `findings.md`
  - `task_plan.md`
  - `devprompt/README.md`
- Build：
  - `xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO`
  - Result: `** BUILD SUCCEEDED **`

---

## 3. Positive Findings

以下内容已通过审计，修复轮不应扩大范围或重做：

### 3.1 Two-step read path exists and is faithful

`ProjectDetailViewModel.refreshResolutionFeedback()` 已实现：

1. `project_risk_summaries.select("id").eq("project_id", value: projectId).limit(1)`
2. `risk_actions.select("title, status, severity, resolution_category, effectiveness, follow_up_required, reopen_count, resolved_at")`
3. `.eq("ai_source_id", value: anchor.id)`
4. `.order("resolved_at", ascending: false, nullsFirst: false)`
5. `.limit(50)`

这与 Web `getProjectRiskResolutionSummary(projectId)` 的核心读链路一致。

### 3.2 Aggregation mostly matches Web

已确认 iOS 聚合实现包括：

- `total = rows.count`
- `resolved`
- `dismissed`
- `active`
- `followUpRequired`
- `reopenedCount`
- `dominantCategory`
- `recentResolutions` top-3 over resolved/dismissed rows

整体方向正确。

### 3.3 State isolation is acceptable

`resolutionFeedbackErrorMessage` 是独立错误面；失败路径保留 prior snapshot 并回滚 phase。未污染：

- `errorMessage`
- `summaryErrorMessage`
- `riskAnalysisErrorMessage`
- `linkedRiskActionsErrorMessage`
- `deleteErrorMessage`
- `enrichmentErrors`

### 3.4 UI section exists and is scoped

`ProjectDetailView` 已新增 `resolutionFeedbackSection`，且放置位置合理：

- after `linkedRiskActionsSection`
- before `foundationScopeNote`

文案明确 read-only，未伪装写路径已完成。

### 3.5 Build passed

独立构建通过：

- `** BUILD SUCCEEDED **`

### 3.6 `.projects` remains `.partial`

`AppModule.projects` 仍为 `.partial`，没有虚报 full parity。

---

## 4. Blocking Finding

### Finding 1 — Governance badge priority does not match Web

**Severity:** High  
**Category:** Web parity / source-of-truth correctness  
**Location:**

- iOS:
  - `Brainstorm+/Features/Projects/ProjectDetailModels.swift`
  - `ProjectResolutionFeedback.governanceSignal`
- Web:
  - `BrainStorm+-Web/src/app/dashboard/projects/page.tsx`, resolution feedback block

#### Web source of truth

Web code:

```tsx
{(() => {
  const hasEffective = resSummary.recentResolutions?.some(
    r => r.effectiveness === 'effective' && r.category === 'root_cause_fixed'
  )
  const needsIntervention = resSummary.reopenedCount > 0 && resSummary.active > 0
  if (hasEffective) return (
    <span>干预已生效</span>
  )
  if (needsIntervention) return (
    <span>待治理干预</span>
  )
  return null
})()}
```

因此 Web 的 governance intervention status priority 是：

1. `hasEffective` first
2. `needsIntervention` second
3. null otherwise

注意：Web 的 predictive `易重开` badge 是另一个独立 badge，仍会在 `reopenedCount > 0 && active > 0` 时显示；但 governance intervention status 本身并不是 danger-first。

#### iOS current implementation

当前 iOS：

```swift
public var governanceSignal: GovernanceSignal {
    let needs = reopenedCount > 0 && active > 0
    if needs { return .needsIntervention }
    let effective = recentResolutions.contains { resolution in
        resolution.effectiveness == "effective" && resolution.category == "root_cause_fixed"
    }
    return effective ? .interventionEffective : .none
}
```

这把 priority 写成：

1. `needsIntervention` first
2. `interventionEffective` second

与 Web 不一致。

#### Impact

当一个项目同时满足：

- 有 `effectiveness == "effective" && category == "root_cause_fixed"` 的 recent resolution
- 且 `reopenedCount > 0 && active > 0`

Web 会显示 governance status：

- **干预已生效**

同时仍显示独立 predictive badge：

- **易重开**

iOS 当前会显示：

- **Needs governance intervention**

并把 “Prone to reopen” 放进同一个 warning banner。

这改变了 Web 的语义优先级，属于 source-of-truth parity 偏差。

#### Required fix

最小修复应：

1. 修改 `ProjectResolutionFeedback.governanceSignal` priority：
   - 先算 `effective`
   - 若 `effective` 为 true → `.interventionEffective`
   - 否则再判断 `reopenedCount > 0 && active > 0` → `.needsIntervention`
   - 否则 `.none`
2. 保留 `isProneToReopen` 独立计算：
   - `reopenedCount > 0 && active > 0`
3. UI 应允许：
   - governance banner 显示 `Intervention effective`
   - 同时仍显示 prone-to-reopen subline / indicator（如果 `isProneToReopen == true`）
4. 更新注释、ready notes、findings/progress/task_plan。
5. 重跑 build。

---

## 5. Non-blocking Notes

以下不是 fail 点：

1. iOS 采用 explicit button fetch 而非 Web auto-fetch：已记录为 foundation divergence，可接受。
2. English-only copy：已记录为 carry-forward i18n debt。
3. `Color.red` / `Color.green` 少量使用：继承 2.4 风格债，不阻断本轮。
4. no `/api/risk-resolution*` route：不阻断，因为本轮纯读链路可由 iOS PostgREST 复刻。
5. resolution write-back / governance write / syncRiskFromDetection：明确 out-of-scope。

---

## 6. Audit Decision

**FAIL**

2.5 不应直接创建 2.6。应先创建最小修复轮：

- `2.5.1-resolution-feedback-governance-priority-fix.md`

修复目标仅限：

- governanceSignal priority 与 Web source-of-truth 对齐
- 相关注释 / ledger / ready notes 对账
- build 通过

禁止顺手扩展写路径、auto-fetch、risk action management、i18n 或其他 UI 重构。
