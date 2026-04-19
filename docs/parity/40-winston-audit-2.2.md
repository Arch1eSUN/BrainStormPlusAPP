# 40 Winston Audit — 2.2 Projects AI Summary Foundation

**Round:** `2.2 Projects AI Summary Foundation`  
**Date:** 2026-04-16  
**Auditor:** Winston  
**Result:** PASS

## 1. Verdict

`2.2 Projects AI Summary Foundation` **通过 Winston 独立审计**。

本次审计没有采信 ready notes、ledger 自述或 control-ui 消息中的“已完成 / BUILD SUCCEEDED”声明，而是重新独立完成：

1. 读取审计相关 skill：
   - `/Users/archiesun/.agents/skills/audit/SKILL.md`
   - `/Users/archiesun/.agents/skills/frontend-design/SKILL.md`
2. 读取本轮 prompt：
   - `devprompt/2.2-projects-ai-summary-foundation.md`
3. 读取 ready notes：
   - `docs/parity/39-winston-ready-2.2-notes.md`
4. 读取 ledger：
   - `findings.md`
   - `progress.md`
   - `task_plan.md`
5. 对照 Web source of truth：
   - `../BrainStorm+-Web/src/lib/actions/summary-actions.ts`
   - `../BrainStorm+-Web/src/app/dashboard/projects/page.tsx`
   - `../BrainStorm+-Web/src/lib/ai/orchestrator.ts`
   - `../BrainStorm+-Web/src/app/api/`
6. 审核 iOS 关键实现：
   - `Brainstorm+/Features/Projects/ProjectDetailModels.swift`
   - `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
   - `Brainstorm+/Features/Projects/ProjectDetailView.swift`
   - `Brainstorm+/Shared/Navigation/AppModule.swift`
7. 独立执行 prompt §4.1 `rg` scan
8. 独立执行 `xcodebuild build`

结论：**2.2 达到本轮验收标准；`.projects` 仍必须保持 `.partial`。**

---

## 2. Scope Audited

### In scope

本轮要求交付：

1. 先核清 Web Projects AI summary 的真实 source of truth。
2. 在 iOS `ProjectDetailView` 路径补最小可审计 summary foundation。
3. 提供明确入口、loading、success、isolated failure state。
4. summary failure 不得污染：
   - detail first-load `errorMessage`
   - `enrichmentErrors`
   - `deleteErrorMessage`
   - list / owner / edit / member / task-count surfaces
5. 不阻断既有 owner / tasks / daily / weekly detail 内容。
6. 不扩到 risk analysis / linked risk actions / resolution feedback。
7. ledger 必须记录 Web source truth、iOS 调用方式、state shape、failure isolation、remaining gaps。
8. `.projects` 不得误标 full parity。

### Out of scope

审计确认本轮未扩散到：

- risk analysis
- linked risk actions
- resolution feedback
- schema changes
- long-term persistence / offline cache
- task-count redesign
- create/edit/delete/member redesign
- task CRUD redesign
- streaming chat UI
- prompt engineering backend rewrite
- analytics / telemetry system
- Web-side `/api/ai/project-summary` endpoint
- Supabase Edge Function
- `api_keys` on-device touchpoint

---

## 3. Independent Findings

### 3.1 Web AI summary source of truth 已核清

独立读取 `BrainStorm+-Web/src/lib/actions/summary-actions.ts`，确认 Web 的 project summary 真实入口是：

```ts
generateProjectSummary(projectId: string)
```

它位于 `'use server'` 文件中，是 **Next.js server action**，不是 HTTP API route。

该 action 并行读取：

```ts
projects.select('name, status, progress, start_date, end_date').eq('id', projectId).single()
tasks.select('title, status, priority, due_date').eq('project_id', projectId).order('created_at', { ascending: false }).limit(30)
daily_logs.select('date, content, progress, blockers').eq('project_id', projectId).order('date', { ascending: false }).limit(10)
weekly_reports.select('week_start, summary, highlights, challenges').contains('project_ids', [projectId]).order('week_start', { ascending: false }).limit(3)
```

no-data branch 返回：

```ts
{ summary: '', error: '项目暂无足够数据生成摘要' }
```

随后调用：

```ts
askAI({ systemPrompt, userMessage, scenario: 'project_summary' })
```

独立读取 `BrainStorm+-Web/src/app/dashboard/projects/page.tsx`，确认 Projects 页面确有 summary 入口按钮、loading、结果展示与 error toast。

独立检查 `BrainStorm+-Web/src/app/api/`，确认不存在 `ai/project-summary` HTTP route。

因此 ledger 的关键判断成立：**Web flow 存在，但 native iOS 当前无法通过 HTTP 直接调用该 server action。**

### 3.2 Second-order source-of-truth discrepancy 记录真实且必要

Web 的 `generateProjectSummary` 在服务端执行 `askAI()`，provider credentials 由服务端解密使用。iOS 不能：

1. 直接调用 Next.js server action；
2. 把解密后的 provider credentials 嵌入设备端；
3. 自行伪造 Web 没有公开的 HTTP shape。

因此 2.2 采用：

- Web-shape input gathering：**对齐**
- local deterministic facts-only synthesis：**明确 divergence**
- LLM-generated narrative：**延后到 Web-side HTTP endpoint / Edge Function**

该处理符合 prompt §3.A 的 discrepancy path，也符合安全边界。

### 3.3 iOS 数据模型满足 foundation 要求

独立读取 `ProjectDetailModels.swift`，确认新增：

```swift
public struct ProjectSummaryFoundation: Equatable {
    public let summary: String
    public let generatedAt: Date
    public let facts: Facts
}
```

`Facts` 保存：

- `taskTotal`
- `taskDone`
- `taskInProgress`
- `taskOverdue`
- `dailyLogCount`
- `weeklyReportCount`

该 shape 对本轮是合理的：

- `summary` 用于当前只读展示；
- `generatedAt` 对齐 ephemeral generate 体验；
- `facts` 保留后续替换真实 LLM output 时的稳定 binding。

### 3.4 ViewModel state truth 与 failure isolation 成立

独立读取 `ProjectDetailViewModel.swift`，确认新增独立 state：

```swift
@Published public var summary: ProjectSummaryFoundation? = nil
@Published public var isGeneratingSummary: Bool = false
@Published public var summaryErrorMessage: String? = nil
```

并新增：

```swift
public func generateSummary() async
```

该方法具备：

1. access / double-fire gate；
2. `isGeneratingSummary` loading state；
3. 三路 `async let` 并行查询；
4. no-data branch；
5. deterministic local synthesis；
6. failure path 写入 `summaryErrorMessage`，并清空 `summary`。

failure isolation 审计结果：summary failure **不会修改**：

- `errorMessage`
- `enrichmentErrors`
- `deleteErrorMessage`
- `owner`
- `tasks`
- `dailyLogs`
- `weeklySummaries`
- `profilesById`
- `accessOutcome`

这满足本轮“AI summary 是装饰性失败，不得打断 detail 主路径”的核心约束。

### 3.5 Denied-state cleanup 成立

独立确认 `applyDeniedState()` 已扩展清理：

```swift
self.summary = nil
self.summaryErrorMessage = nil
```

因此不会出现：

- 用户先在 `.allowed` project 生成 summary；
- 后续 fetch 落入 `.denied`；
- 旧 summary 仍残留展示。

该点满足 access leakage 防线。

### 3.6 UI state machine 成立

独立读取 `ProjectDetailView.swift`，确认新增 `aiSummarySection` 插入位置：

- after `weeklySummariesSection`
- before `errorMessage` banner + `foundationScopeNote`

UI 提供：

- idle：`Generate summary`
- loading：`Generating…` + `ProgressView` + disabled
- success：显示 `summary.summary` + generated-at caption + `Regenerate summary`
- failure：显示 scoped soft error row + `Try again`

按钮禁用条件：

```swift
viewModel.isGeneratingSummary || viewModel.isDeleting
```

因此不会与 delete overlay 竞争，也不会重复触发 summary generation。

### 3.7 Honest labeling 成立

UI header 使用：

- `Project Summary`

而不是误导性的 `AI Summary`。

subtitle 明确声明：

- locally synthesized
- LLM narrative later

这点重要：2.2 的结果不是 Web `askAI()` 真输出，因此如果 UI 仍声称“AI Summary”，会构成产品真实性问题。本轮避免了这个问题。

### 3.8 Visual / frontend anti-pattern 审计

按 `frontend-design` 的 anti-pattern 口径，本轮新增 UI 没有引入明显 AI-slop：

- 未新增大面积 gradient / glow；
- 未新增 hero metrics；
- 未把 summary 包装成夸张卡片阵列；
- 复用现有 `enrichmentCard` 视觉语言；
- 新增 section 层级克制，符合 detail 页面既有结构。

非阻断问题：本轮继续沿用现有 `Inter` / rounded card / subtle shadow 体系；这属于既有设计系统，不作为 2.2 regression。

### 3.9 `.projects` 仍为 `.partial`

独立读取 `AppModule.swift`，确认：

```swift
case .projects:
    return .partial
```

该状态正确，因为以下仍未完成：

- true LLM-generated summary narrative
- risk analysis
- linked risk actions
- resolution feedback

2.2 只关闭 AI summary foundation，不能升级 full parity。

### 3.10 旧能力未见回退

本次核对未见以下回退：

- 1.5 membership scoping
- 1.6 detail gate / ordering
- 1.7 owner hydrate + read-only enrichment
- 1.8 nested profile names + avatar rendering
- 1.9 edit + member management
- 2.0 delete foundation
- 2.1 task-count-on-list foundation

2.2 改动面集中在 detail summary foundation，符合最小变更原则。

---

## 4. Audit Notes

### 4.1 Non-blocking: 2.2 summary 不是 Web 的真实 LLM output

这是本轮最大差异，但不是阻断项。

原因：Web 没有 native-callable route，server action 不能直接从 iOS 调用，且 provider credentials 不能下放到设备端。

后续修正路径：

- Web-side `/api/ai/project-summary` route；或
- Supabase Edge Function；或
- 其他受控 server bridge。

### 4.2 Non-blocking: no-data / error copy 仍为英文

iOS 本轮文案是英文，而 Web 多数 summary/risk 文案为中文。该问题归入 broader iOS i18n，不阻断 foundation PASS。

### 4.3 Non-blocking: generated snapshot 不会自动随底层数据变化刷新

用户需要手动 `Regenerate summary` 才能重新读取 tasks / daily logs / weekly reports。

这符合 foundation 范围；后续如引入 persistence 或 invalidation，再统一处理。

---

## 5. Verification

### 5.1 Scan

已独立执行：

```bash
rg -n 'ai summary|AI summary|summary|generateSummary|refreshSummary|project-summary|ProjectDetailView|ProjectDetailViewModel|errorMessage|deleteErrorMessage|enrichmentErrors|projects|tasks|daily|weekly|AppModule|implementationStatus' Brainstorm+ progress.md findings.md task_plan.md ../BrainStorm+-Web/src
```

结论：2.2 相关符号、实现与 ledger 记述对齐；未发现明显伪报或误标 full parity。

### 5.2 Build

已独立执行：

```bash
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
```

独立结果：

```text
** BUILD SUCCEEDED **
```

---

## 6. Ledger Truth

独立核对后，以下表述成立：

- `findings.md`：2.2 scope、Web server-action discrepancy、iOS local synthesis、remaining gaps 表述真实。
- `progress.md`：2.2 实现点、验证、技能使用、debt 记录基本真实。
- `task_plan.md`：2.2 completed / next audit step 与真实流程一致。
- `docs/parity/39-winston-ready-2.2-notes.md`：ready notes 与代码实现大体一致。

需要注意：ready notes 是交接材料，不是审计证据；本结论以实际 source / scan / build 为准。

---

## 7. Final Result

**PASS**。

`2.2 Projects AI Summary Foundation` 已满足本轮验收标准：

1. Web AI summary source-of-truth 已核清。
2. Web server-action / no HTTP route discrepancy 已明确记录。
3. iOS detail 页面具备 summary foundation。
4. loading / success / failure state 完整。
5. `summaryErrorMessage` failure isolation 成立。
6. `applyDeniedState()` 清理 summary state，避免 stale leakage。
7. 1.5–2.1 能力未见回退。
8. `.projects` 仍保持 `.partial`。
9. scan 独立完成。
10. build 独立通过。

## 8. Recommended Next Round

根据当前 Projects parity 缺口，下一轮不应继续打磨 AI summary foundation，也不应先扩 Web endpoint，除非目标是解除 LLM narrative divergence。

我选择下一轮进入：

- **2.3 Projects Risk Analysis Foundation**

理由：

1. 它延续 1.6 → 2.2 的 Projects detail-surface 深化路径。
2. Web 已存在 project risk analysis surface、cached metadata、risk level、linked risk actions 与 resolution feedback 的完整链路。
3. 2.3 可以只做最小 foundation：risk analysis entry + state machine + cached summary / generated summary read-only display。
4. linked risk actions 与 resolution feedback 可留给 2.4 / 2.5，避免 2.3 过载。
5. `.projects` 仍保持 `.partial`，直到 risk / linked actions / resolution feedback / true LLM summary narrative 均对齐。
