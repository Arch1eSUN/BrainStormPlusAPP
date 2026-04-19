# 38 Winston Audit — 2.1 Projects Task Count List Parity

**Round:** `2.1 Projects Task Count List Parity`  
**Date:** 2026-04-16  
**Auditor:** Winston  
**Result:** PASS

## 1. Verdict

`2.1 Projects Task Count List Parity` **通过 Winston 独立审计**。

本次审计没有采信 ready notes、ledger 自述或 control-ui 消息中的“已完成 / BUILD SUCCEEDED”声明，而是重新独立完成：

1. 读取审计相关 skill：
   - `/Users/archiesun/.agents/skills/audit/SKILL.md`
   - `/Users/archiesun/.agents/skills/frontend-design/SKILL.md`
2. 读取本轮 prompt：
   - `devprompt/2.1-projects-task-count-list-parity.md`
3. 读取 ready notes：
   - `docs/parity/37-winston-ready-2.1-notes.md`
4. 读取 ledger：
   - `findings.md`
   - `progress.md`
   - `task_plan.md`
5. 对照 Web source of truth：
   - `../BrainStorm+-Web/src/lib/actions/projects.ts`
   - `../BrainStorm+-Web/src/app/dashboard/projects/page.tsx`
6. 审核 iOS 关键实现：
   - `Brainstorm+/Features/Projects/ProjectListViewModel.swift`
   - `Brainstorm+/Features/Projects/ProjectCardView.swift`
   - `Brainstorm+/Features/Projects/ProjectListView.swift`
   - `Brainstorm+/Shared/Navigation/AppModule.swift`
7. 独立执行 prompt §4.1 `rg` scan
8. 独立执行 `xcodebuild build`

结论：**2.1 达到本轮验收标准；`.projects` 仍必须保持 `.partial`。**

---

## 2. Scope Audited

### In scope

本轮要求交付：

1. Web task count source of truth 重新核清。
2. 如果 Web 真实返回 / 渲染 task count，则 iOS mirror；如果 Web 没有真实返回 / 渲染但 ledger 认定为 gap，则记录 discrepancy 并做最小 iOS foundation。
3. iOS Projects list card 显示 task count。
4. task count 获取必须避免 per-project N+1。
5. count failure 不得污染：
   - main list `errorMessage`
   - `ownersErrorMessage`
   - `deleteErrorMessage`
   - edit/member/detail enrichment error surfaces
6. 不回退 1.5–2.0 已审计能力。
7. ledger 必须如实记录 source-of-truth discrepancy、batched strategy、failure isolation、remaining gaps。
8. `.projects` 不得误标 full parity。

### Out of scope

审计确认本轮未扩散到：

- AI summary
- risk analysis
- linked risk actions
- resolution feedback
- create/edit/delete/member redesign
- task CRUD changes
- schema changes
- analytics dashboard
- large UI redesign
- status-filtered counts
- locale-aware pluralization

---

## 3. Independent Findings

### 3.1 Web source-of-truth discrepancy 真实存在

独立读取 `BrainStorm+-Web/src/lib/actions/projects.ts`：

```ts
export interface Project {
  // ...
  task_count?: number
}
```

但 `fetchProjects()` 查询为：

```ts
let query = adminDb
  .from('projects')
  .select('*, profiles:owner_id(full_name, avatar_url)')
  .order('created_at', { ascending: false })
```

未选择：

- `task_count`
- nested `tasks(count)`
- computed aggregate

独立读取 `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` 的 card markup，确认 list card 渲染 owner / end date / progress / status，不引用 `task_count`。

因此 ledger 的判断成立：**Web 的 `task_count?: number` 是 vestigial typed field；当前 Web list card 实际不显示 task count。**

2.1 prompt §3.A path 3 适用：记录 discrepancy，并做最小 iOS foundation。

### 3.2 iOS 数据层实现满足 batched non-N+1 要求

独立读取 `ProjectListViewModel.swift`，确认新增：

```swift
@Published public var taskCountsByProject: [UUID: Int] = [:]
@Published public var taskCountsErrorMessage: String? = nil
```

并新增：

```swift
private struct TaskProjectIdRow: Decodable {
    let projectId: UUID
    enum CodingKeys: String, CodingKey { case projectId = "project_id" }
}
```

核心 hydrate 为：

```swift
let rows: [TaskProjectIdRow] = try await client
    .from("tasks")
    .select("project_id")
    .in("project_id", values: projectIds)
    .execute()
    .value
```

该实现是**单次 batched PostgREST round-trip**，不是按 project 循环查询，因此满足“不得 N+1”的本轮约束。

实现还先为所有当前 project id 初始化 `0`：

```swift
for id in projectIds { counts[id] = 0 }
```

因此 `0 tasks` 与 fetch failed 的 `nil` 被正确区分。

### 3.3 failure isolation 成立

独立确认 `refreshTaskCountsForCurrentProjects()` failure path：

```swift
self.taskCountsByProject = [:]
self.taskCountsErrorMessage = error.localizedDescription
```

它没有修改：

- `projects`
- `errorMessage`
- `ownersById`
- `ownersErrorMessage`
- `deleteErrorMessage`

UI 通过 `taskCountsByProject[project.id]` 返回 `Int?`，失败时为 `nil`，`ProjectCardView` 隐藏 count label，而不是误显示 `0 tasks`。

这满足本轮要求：**count failure 是装饰性失败，不阻断 Projects list。**

### 3.4 no-membership / empty-state cleanup 成立

独立确认 `ProjectListViewModel.fetchProjects(...)` 的两个 no-membership / missing-user early return 均清理：

```swift
taskCountsByProject = [:]
taskCountsErrorMessage = nil
```

并且 helper 内对 `projectIds.isEmpty` 也清理 count state。

因此不会从 admin mode 或上一次有数据状态泄漏 stale count 到空列表 / 无权限状态。

### 3.5 UI 显示满足 foundation 要求

独立读取 `ProjectCardView.swift`，确认新增：

```swift
public let taskCount: Int?
```

构造器为 additive default：

```swift
public init(project: Project, owner: ProjectOwnerSummary? = nil, taskCount: Int? = nil)
```

显示逻辑为：

```swift
if let taskCount {
    Label(Self.taskCountLabel(taskCount), systemImage: "checklist")
        .font(.custom("Inter-Medium", size: 12))
        .foregroundColor(Color.Brand.textSecondary)
}
```

并提供：

```swift
private static func taskCountLabel(_ count: Int) -> String {
    count == 1 ? "1 task" : "\(count) tasks"
}
```

该 UI：

- 支持 `0 tasks`
- 支持 `1 task`
- 支持 `N tasks`
- 与 end-date metadata 同视觉层级
- 未引入 hero metric、decorative gradient、额外 card redesign
- 未破坏 owner/avatar/status/progress 结构

按 `frontend-design` anti-pattern 审计口径，本轮新增 UI 属于克制的 metadata 增量，未引入明显 AI-slop 视觉。

### 3.6 list wiring 成立

独立读取 `ProjectListView.swift`，确认 row construction 传入：

```swift
taskCount: viewModel.taskCountsByProject[project.id]
```

这与 VM 的 `[UUID: Int]` map 语义一致：

- resolved `0` → `Optional(0)` → card 显示 `0 tasks`
- missing / failed → `nil` → card 隐藏 label

### 3.7 `.projects` 仍为 `.partial`

独立读取 `AppModule.swift`，确认：

```swift
case .projects:
    return .partial
```

这与真实状态一致，因为以下 gaps 仍未完成：

- AI summary
- risk analysis
- linked risk actions
- resolution feedback

2.1 只关闭 task-count-on-list foundation，不能升级 full parity。

### 3.8 旧能力未见回退

本次核对未见以下回退：

- 1.5 list membership scoping 仍保留
- 1.6 ordering / detail membership gate 未被 2.1 改动
- 1.7 owner hydrate 未被破坏
- 1.8 avatar rendering 未被破坏
- 1.9 edit/member management 未被改动
- 2.0 delete foundation 未被改动

2.1 改动面集中在：

- `ProjectListViewModel.swift`
- `ProjectCardView.swift`
- `ProjectListView.swift`
- ledger / ready notes

符合最小变更原则。

---

## 4. Audit Notes

### 4.1 Non-blocking: task count query 不是真正 server-side count aggregate

当前实现选择所有匹配任务的 `project_id` 后在客户端聚合。它满足本轮 prompt 的“batched、非 N+1、最小 foundation”要求，但不是最优 server-side count。

影响：

- 对常规项目列表足够
- 对极大 task volume 会拉取较多 `project_id` rows

不阻断 PASS，因为本轮 prompt 明确允许 batched `tasks` count by project ids，且 ledger 已记录 scaling debt。

后续可选优化：

- Web / iOS 共同改用 nested `tasks(count)`
- 或 Postgres view / RPC 暴露 project task count

### 4.2 Non-blocking: iOS 目前领先 Web

Web list card 当前不显示 task count；iOS 2.1 显示。按严格“镜像当前 Web UI”会构成差异；但本轮 prompt 明确授权在 ledger 认定 gap 时走 §3.A path 3。

因此这是**记录在案的设计性 divergence**，不是误实现。

---

## 5. Verification

### 5.1 Scan

已独立执行：

```bash
rg -n 'task_count|taskCount|taskCounts|tasksCount|count\(|head:|ProjectCardView|ProjectListViewModel|ProjectListView|ownersErrorMessage|deleteErrorMessage|errorMessage|projects|tasks|AppModule|implementationStatus' Brainstorm+ progress.md findings.md task_plan.md
```

结论：2.1 相关符号、实现与 ledger 记述对齐；未发现明显伪报或误标 full parity。

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

- `findings.md`：2.1 scope、Web discrepancy、batched count strategy、remaining gaps 表述基本真实。
- `progress.md`：2.1 实现点、验证、技能使用、debt 记录基本真实。
- `task_plan.md`：2.1 completed / next audit step 与真实流程一致。
- `docs/parity/37-winston-ready-2.1-notes.md`：ready notes 与代码实现大体一致。

需要注意：ready notes 是交接材料，不是审计证据；本结论以实际 source / scan / build 为准。

---

## 7. Final Result

**PASS**。

`2.1 Projects Task Count List Parity` 已满足本轮验收标准：

1. Web task count source-of-truth 已核清。
2. Source-of-truth discrepancy 已明确记录。
3. iOS list card 可显示 task count。
4. count fetch 为 batched non-N+1。
5. `0 tasks` 与 failed/unknown `nil` 语义区分成立。
6. failure isolation 成立。
7. 1.5–2.0 能力未见回退。
8. `.projects` 仍保持 `.partial`。
9. scan 独立完成。
10. build 独立通过。

## 8. Recommended Next Round

建议下一轮不要继续打磨 task count，而是进入 Projects 的下一个核心 Web-only gap：

- **2.2 Projects AI Summary Foundation**

理由：

- task count 已完成 foundation；继续 polish 的边际收益低。
- risk analysis / linked actions / resolution feedback 依赖更大实体与流程判断，范围更重。
- AI summary 可以做成窄口径 foundation：detail 页只读触发 / 请求 / 展示 / failure isolation，不碰 persistence / schema / risk workflow。

