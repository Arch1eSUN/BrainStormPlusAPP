# 42 Winston Audit — 2.3 Projects Risk Analysis Foundation

**Round:** `2.3 Projects Risk Analysis Foundation`  
**Date:** `2026-04-16`  
**Auditor:** Winston  
**Result:** PASS

## 1. Verdict

`2.3 Projects Risk Analysis Foundation` **通过 Winston 独立审计**。

本次审计未采信 ready notes、ledger 自述或 control-ui 中的“Build succeeded / 已完成”声明作为结论依据，而是重新独立完成以下核验：

1. 读取并遵循审计相关 skill：
   - `/Users/archiesun/.agents/skills/audit/SKILL.md`
   - `/Users/archiesun/.agents/skills/frontend-design/SKILL.md`
2. 读取本轮 prompt：
   - `devprompt/2.3-projects-risk-analysis-foundation.md`
3. 读取交付说明：
   - `docs/parity/41-winston-ready-2.3-notes.md`
4. 重新核对 iOS 实现：
   - `Brainstorm+/Features/Projects/ProjectDetailModels.swift`
   - `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
   - `Brainstorm+/Features/Projects/ProjectDetailView.swift`
   - `Brainstorm+/Shared/Navigation/AppModule.swift`
5. 重新执行独立构建验证：
   - `xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO`
   - 结果：`** BUILD SUCCEEDED **`
6. 重新核对 ledger：
   - `progress.md`
   - `findings.md`
   - `task_plan.md`
   - `devprompt/README.md`

审计结论：**2.3 已按 contract 交付“只读风险分析 foundation”**，且明确维持 `.projects = .partial`，没有伪装成完整 Web parity。

---

## 2. Audit Scope

本轮审计只判断以下 contract 是否真实完成：

1. iOS Project detail 页是否新增 **Risk Analysis** 一等区块。
2. 该区块是否采用 **read-only cached-row** 路线，而不是伪造 iOS 端 `askAI()` / 伪造 HTTP endpoint。
3. 状态机是否完整且隔离：
   - idle
   - loading
   - success
   - empty-cache
   - failure
   - denied
4. 风险分析失败是否与 detail 主加载、enrichment、delete、2.2 summary 错误面隔离。
5. 是否诚实记录 source-of-truth discrepancy：
   - Web 可生成
   - iOS 只能读缓存
   - 生成新风险分析仍待 Web 暴露 `/api/ai/project-risk` 或等价 server-side bridge
6. 是否维持 `.projects` 为 `.partial`。

本轮**不**要求交付：
- linked risk actions
- resolution feedback
- `summaryId` / `risk_items` 展示
- iOS 侧 force-regenerate
- `/api/ai/project-risk` Web endpoint
- Markdown 富文本风险渲染

---

## 3. What I Re-Verified

### 3.1 数据模型

`ProjectDetailModels.swift` 已新增：

- `ProjectRiskAnalysis`
  - `summary: String`
  - `riskLevel: RiskLevel`
  - `generatedAt: Date?`
  - `model: String?`
  - `scenario: String?`
- `ProjectRiskAnalysis.RiskLevel`
  - `.low`
  - `.medium`
  - `.high`
  - `.critical`
  - `.unknown`

审计判断：
- 结构足以承载 2.3 foundation 所需展示字段。
- `.unknown` 回退存在，避免 Web 端未来新增值导致 decode / UI 语义崩坏。
- 文档注释明确区分 2.2 与 2.3：2.2 是本地 deterministic synthesis，2.3 是**读取 Web 已持久化风险分析缓存**。该表述真实且重要。

### 3.2 ViewModel 状态机

`ProjectDetailViewModel.swift` 已新增四个独立状态：

- `riskAnalysis: ProjectRiskAnalysis?`
- `isLoadingRiskAnalysis: Bool`
- `riskAnalysisNotYetGenerated: Bool`
- `riskAnalysisErrorMessage: String?`

并实现 `refreshRiskAnalysis()`：

- 查询表：`project_risk_summaries`
- 选择列：`summary, risk_level, generated_at, model_used, scenario`
- 过滤：`.eq("project_id", value: projectId)`
- 读取方式：`.limit(1)` + `rows.first`

关键审计点：

1. **实现路径真实**
   - 没有伪造 iOS 端 LLM 调用。
   - 没有伪造 HTTP route。
   - 直接读 Web 已写入的缓存表，符合 prompt contract。

2. **empty-cache 与 idle 被明确区分**
   - `riskAnalysisNotYetGenerated` 的存在是本轮实现的关键价值点。
   - 没查过 ≠ Web 尚未生成，这一点被正确建模。

3. **失败隔离成立**
   - catch 分支只写 `riskAnalysisErrorMessage`
   - 不触碰：
     - `errorMessage`
     - `enrichmentErrors`
     - `deleteErrorMessage`
     - `summaryErrorMessage`
     - `project/tasks/dailyLogs/weeklySummaries/owner`
   - 且保留既有 `riskAnalysis` snapshot，避免一次网络失败清空有效风险上下文。

4. **denied 清理成立**
   - `applyDeniedState()` 会清掉 2.3 风险状态，避免 allowed → denied 切换后泄漏旧快照。

5. **时间与风险等级解析合理**
   - timestamp 双格式 ISO8601 解析，失败静默回退 `nil`
   - risk level 大小写归一化并回退 `.unknown`

审计判断：**ViewModel contract 完成且边界处理真实。**

### 3.3 Detail UI surface

`ProjectDetailView.swift` 已确认：

- `riskAnalysisSection` 被插入到 detail scroll 中
- 顺序在 `aiSummarySection` 之后、footer note 之前
- section header 为 `Risk Analysis`
- 成功态显示：
  - 风险等级 badge
  - summary 文本
  - provenance caption（Generated + model）
- empty-cache 显示诚实提示：
  - `No risk analysis has been generated on the web yet for this project.`
- 按钮状态机存在：
  - `Check for risk analysis`
  - `Checking…`
  - `Refresh`
  - `Try again`
- 按钮在 `isLoadingRiskAnalysis || isDeleting` 时禁用

关键审计点：

1. **UI 文案诚实**
   - `Read-only snapshot · loaded from the web dashboard's most recent analysis. New analyses must be generated on the web.`
   - 这句话准确表达了 2.3 的真实能力边界。

2. **风险等级视觉映射存在**
   - low / medium / high / critical / unknown 均有明确 badge 样式。

3. **复用既有视觉语言**
   - 没有引入新 token 污染设计系统。
   - 以现有 card 语义落地，符合 foundation scope。

4. **区块级错误隔离成立**
   - 风险区块错误不会吞掉整个 detail 页。

审计判断：**UI contract 完成。**

### 3.4 `.projects` 状态

`AppModule.swift` 中：

- `.projects` 仍为 `.partial`

审计判断：**状态声明真实**。

这是本轮必须通过的诚信点之一：
2.3 并没有完成 linked actions / resolution feedback / generate-from-iOS，因此不能升为 `.full`。

### 3.5 Build verification

独立重跑构建，结果：

- `** BUILD SUCCEEDED **`

审计判断：**至少在当前本机构建层面，2.3 实现可编译。**

---

## 4. Web Parity Judgment

### 4.1 已实现的真实 parity

本轮真正实现的是：

- Web 风险分析缓存表的**读取 parity**
- 风险等级与摘要的**展示 parity 基础层**
- generated-at / model 的**provenance parity 基础层**
- risk 失败不污染 detail 主态的**状态隔离 parity**

### 4.2 明确存在且被诚实记录的 divergence

以下 divergence 仍存在，但本轮**没有装作不存在**：

1. Web 可 `generateProjectRiskAnalysis(...)`，iOS 不可生成。
2. Web 有 `isCached` badge，iOS 未展示。
3. Web 有 `summaryId` / linked actions / resolution feedback，iOS 未展示。
4. Web page 层可继续联动风险动作，iOS 只读。

审计判断：
- 这些差异**都已被 findings / progress / ready notes 明确记录**。
- 因此本轮属于**受控差异**，不是伪完成。

---

## 5. Ledger Consistency

我重新核对：

- `progress.md`
- `findings.md`
- `task_plan.md`
- `devprompt/README.md`

结果：

1. 2.3 已被记录为完成。
2. Winston 2.3 audit 被标记为下一步。
3. `.projects` remaining gaps 仍被保留。
4. README 仍只投放一个当前轮次，没有提前一次性放多轮 prompt。

审计判断：**ledger 与代码状态一致。**

---

## 6. Risks / Debt Still Open

以下不是 2.3 fail 点，但必须继续保持真实记录：

1. **生成能力仍缺失**
   - iOS 仍不能主动生成新的风险分析。
   - 真正补齐需 Web 暴露 `/api/ai/project-risk` 或同等 server-side bridge。

2. **linked risk actions 未落地**
   - 这是 2.4 最自然的延续点。

3. **resolution feedback 未落地**
   - 仍明显晚于 Web。

4. **`Color.red` 临时承担 critical token**
   - 不是本轮阻塞，但属于 design token 债。

5. **Markdown 风险摘要仍按 plain text 渲染**
   - Web 使用 ReactMarkdown；iOS 当前仍是 foundation 级 `Text`。

---

## 7. Final Audit Decision

**PASS**

理由：

1. 2.3 的最小 contract 已真实交付。
2. 采用的是正确架构路径：**read-only persisted risk snapshot**，而不是伪造 iOS generate。
3. 状态机完整，且 failure isolation 到位。
4. build 独立通过。
5. ledger 与真实代码对账一致。
6. `.projects` 仍保持 `.partial`，没有虚报完成度。

---

## 8. Recommended Next Round

**推荐下一轮：`2.4 Projects Linked Risk Actions Foundation`**

原因：

1. 它是 2.3 的自然延续。
2. 仍然可以维持 read-only / Supabase-first 路线。
3. 不需要先解决 Web-side generate endpoint，范围比“补 `/api/ai/project-risk`”更窄、更易审计。
4. 可以直接消费 2.3 尚未暴露的 `summaryId` / `ai_source_id` 关联链路，继续收口 Projects detail parity。
