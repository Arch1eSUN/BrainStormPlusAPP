# 44 Winston Audit — 2.4 Projects Linked Risk Actions Foundation

**Round:** `2.4 Projects Linked Risk Actions Foundation`  
**Date:** `2026-04-16`  
**Auditor:** Winston  
**Result:** PASS

## 1. Verdict

`2.4 Projects Linked Risk Actions Foundation` **通过 Winston 独立审计**。

本次审计没有采信 ready notes、ledger 自述或 control-ui 中的“交付完成 / BUILD SUCCEEDED”声明，而是重新独立完成：

1. 读取并遵循审计相关 skill：
   - `/Users/archiesun/.agents/skills/audit/SKILL.md`
   - `/Users/archiesun/.agents/skills/frontend-design/SKILL.md`
2. 读取本轮 prompt：
   - `devprompt/2.4-projects-linked-risk-actions-foundation.md`
3. 读取 ready notes：
   - `docs/parity/43-winston-ready-2.4-notes.md`
4. 重新核对 iOS 实现：
   - `Brainstorm+/Features/Projects/ProjectDetailModels.swift`
   - `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
   - `Brainstorm+/Features/Projects/ProjectDetailView.swift`
   - `Brainstorm+/Shared/Navigation/AppModule.swift`
5. 重新核对 ledger：
   - `progress.md`
   - `findings.md`
   - `task_plan.md`
   - `devprompt/README.md`
6. 重新执行独立构建验证：
   - `xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO`
   - 结果：`** BUILD SUCCEEDED **`

审计结论：**2.4 已真实交付 linked risk actions read-only foundation，且这次确实不存在 2.2 / 2.3 那类 source-of-truth 技术阻断。**

---

## 2. Audit Scope

本轮审计只判断以下 contract 是否真实完成：

1. iOS Project detail 页是否新增 **Linked Risk Actions** 一等区块。
2. 是否真实复刻 Web `getLinkedRiskActions(projectId)` 的两步读链路：
   - `project_risk_summaries` anchor lookup
   - `risk_actions` filtered select by `ai_source_id`
3. 是否建立完整状态语义：
   - idle
   - loading
   - noRiskAnalysisSource
   - empty
   - loaded
   - failure（通过 side-band error surface 表达）
   - denied
4. linked actions 失败是否与 detail 主态 / risk analysis / AI summary / enrichment / delete 隔离。
5. 是否诚实声明：
   - 当前只读
   - “转为风险动作”写路径仍未进入 iOS
6. 是否维持 `.projects = .partial`。

本轮**不**要求交付：
- `syncRiskFromDetection` 写入路径
- resolution feedback
- governance intervention
- recent resolutions
- generate-risk-from-iOS
- risk action detail modal
- assignee hydrate on linked actions

---

## 3. What I Re-Verified

### 3.1 Web parity path is real and readable from iOS

从 ready notes、代码注释与实现形态交叉核对，本轮的关键判断成立：

- Web `getLinkedRiskActions(projectId)` 本质是**纯读流程**。
- 它不调用 `askAI()`。
- 它不依赖 server-side `decryptApiKey()`。
- 它只是：
  1. 先找 `project_risk_summaries.id`
  2. 再按 `risk_actions.ai_source_id = summary.id` 取列表

这意味着：

- **iOS 2.4 可以忠实复刻，不需要像 2.2 / 2.3 那样记录技术性 source-of-truth discrepancy。**

审计判断：**这是本轮最关键的真实性点，结论成立。**

### 3.2 数据模型

`ProjectDetailModels.swift` 已新增：

- `ProjectLinkedRiskAction`
  - `id: UUID`
  - `title: String`
  - `status: String`
  - `severity: String`
  - `aiSourceId: UUID?`

关键审计点：

1. 选列与 Web 对齐：
   - `id, title, status, severity, ai_source_id`
2. `CodingKeys` 正确映射：
   - `ai_source_id -> aiSourceId`
3. `status` / `severity` 保持 `String`
   - 这不是偷懒，而是 foundation 阶段对未来服务端词表扩展更稳的选择

审计判断：**数据结构满足 2.4 contract，且没有过度建模。**

### 3.3 ViewModel 两步读取与状态机

`ProjectDetailViewModel.swift` 已确认新增：

- `LinkedRiskActionsPhase`
  - `.idle`
  - `.loading`
  - `.noRiskAnalysisSource`
  - `.empty`
  - `.loaded`
- `linkedRiskActions: [ProjectLinkedRiskAction]`
- `linkedRiskActionsPhase`
- `linkedRiskActionsErrorMessage`

并实现 `refreshLinkedRiskActions()`：

#### Step 1：anchor lookup

```swift
.from("project_risk_summaries")
.select("id")
.eq("project_id", value: projectId)
.limit(1)
```

#### Step 2：filtered select

```swift
.from("risk_actions")
.select("id, title, status, severity, ai_source_id")
.eq("ai_source_id", value: anchor.id)
.order("created_at", ascending: false)
.limit(20)
```

关键审计点：

1. **两步读链路真实存在**
   - 不是 mock。
   - 不是本地拼装。
   - 不是从 2.3 缓存里臆造 linked actions。

2. **`noRiskAnalysisSource` 与 `empty` 被正确区分**
   - 无 anchor ≠ anchor 有了但 actions 为空。
   - 这是本轮状态机设计是否合格的核心判据之一。

3. **失败回滚策略成立**
   - 先保存 `priorPhase`
   - catch 后：
     - 保留旧 `linkedRiskActions` snapshot
     - 写 `linkedRiskActionsErrorMessage`
     - phase 回滚到 `priorPhase`（必要时退回 `.idle`）
   - 不会把 UI 卡死在 `.loading`

4. **错误隔离成立**
   - 不触碰：
     - `errorMessage`
     - `enrichmentErrors`
     - `deleteErrorMessage`
     - `summaryErrorMessage`
     - `riskAnalysisErrorMessage`
     - `accessOutcome`

5. **denied 清理成立**
   - `applyDeniedState()` 已清空 linked actions 相关状态，避免旧快照泄漏。

审计判断：**ViewModel contract 完成，且失败路径处理是真正合格的。**

### 3.4 Detail UI surface

`ProjectDetailView.swift` 已确认：

- `linkedRiskActionsSection` 已插入到：
  - `riskAnalysisSection` 之后
  - footer note 之前
- 标题：`Linked Risk Actions`
- 只读说明：
  - `Read-only · converting a risk into an action is only available on the web.`
- body 按 phase 分支：
  - idle / loading
  - noRiskAnalysisSource
  - empty
  - loaded
- loaded 态：
  - `prefix(3)` 渲染前三条
  - `+ N more on the web dashboard` overflow hint
  - `{N} linked` count badge
- row 结构：
  - status dot
  - truncated title
  - severity capsule
- button 状态机：
  - `Check for linked actions`
  - `Checking…`
  - `Refresh`
  - `Try again`

关键审计点：

1. **UI 诚实**
   - 明确告诉用户只能读，不能在 iOS 端执行“转为风险动作”。

2. **三条预览 + overflow hint 与 Web 语义一致**
   - 不是无限展开，不是另做一套表格。

3. **错误面 scoped**
   - linked actions 出错不会吞掉整个 detail 页面。

4. **视觉语言连续**
   - 没有引入破坏现有 detail card 体系的新 token / 新骨架。

审计判断：**UI contract 完成。**

### 3.5 `.projects` 状态真实

`AppModule.swift` 中：

- `.projects` 仍为 `.partial`

审计判断：**状态声明真实**。

2.4 虽然补了 linked actions foundation，但仍缺：

- `syncRiskFromDetection`
- resolution feedback
- generate-risk-from-iOS
- summary LLM parity

因此不能升 `.full`。

### 3.6 Build verification

独立重跑构建，结果：

- `** BUILD SUCCEEDED **`

审计判断：**2.4 实现可编译。**

---

## 4. Web Parity Judgment

### 4.1 本轮真正完成的 parity

2.4 真正完成的是：

- linked risk actions **anchor lookup parity**
- linked risk actions **filtered select parity**
- top-3 preview **render parity**
- count badge / overflow hint **foundation parity**
- linked-actions failure isolation **parity（且比 Web 更清晰）**

### 4.2 仍未实现但被诚实记录的部分

以下没做，但 ledger / notes 都没有掩盖：

1. **“转为风险动作”写路径**未做。
2. **resolution feedback / governance intervention / recent resolutions** 未做。
3. linked actions 仍是 **button-triggered refresh**，不是 Web 那种 auto-fetch。
4. linked action 的 assignee hydrate / deeper detail 仍未做。

审计判断：
- 这些都是**已记录的 scope defer**，不是伪完成。

---

## 5. Ledger Consistency

我重新核对：

- `progress.md`
- `findings.md`
- `task_plan.md`
- `devprompt/README.md`

结果：

1. 2.4 已记录为完成。
2. Winston 2.4 audit 被标记为下一步。
3. `findings.md` 与 `progress.md` 都明确写出：
   - 本轮无 source-of-truth discrepancy
   - 但写路径与 resolution feedback 仍 defer
4. README 仍只投放一个当前轮次。

审计判断：**ledger 与代码状态一致。**

---

## 6. Risks / Debt Still Open

以下不是 2.4 fail 点，但必须继续真实记录：

1. **写路径仍缺失**
   - iOS 还不能执行 `syncRiskFromDetection`。

2. **resolution feedback 仍缺失**
   - 这是 2.5 最自然的延续点。

3. **auto-fetch 与 Web 仍有行为差异**
   - 当前 iOS 采用显式按钮触发，属于 foundation 级选择。

4. **颜色 token 债仍存在**
   - `Color.red` / `Color.blue` 仍承担部分 severity/status 显示。

5. **English-only copy**
   - 仍未进入 i18n。

---

## 7. Final Audit Decision

**PASS**

理由：

1. 2.4 的最小 contract 已真实交付。
2. 实现路径正确，且这次确实没有 2.2 / 2.3 那类技术性 source-of-truth 阻断。
3. 状态机与失败回滚设计合格。
4. 错误隔离成立。
5. build 独立通过。
6. ledger 与代码对账一致。
7. `.projects` 仍保持 `.partial`，没有虚报完成度。

---

## 8. Recommended Next Round

**推荐下一轮：`2.5 Projects Resolution Feedback Foundation`**

原因：

1. 它是 2.4 的自然延续。
2. 仍可保持 read-only / Supabase-first / 可审计。
3. 比直接做 iOS 写路径更稳、更窄。
4. 能继续关闭 Web risk card 剩余的只读信息差：
   - governance intervention
   - recent resolutions
   - aggregate feedback counts
