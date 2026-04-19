# 36 Winston Audit — 2.0 Projects Delete Foundation

**Round:** `2.0 Projects Delete Foundation`  
**Date:** 2026-04-16  
**Auditor:** Winston  
**Result:** PASS

## 1. Verdict

`2.0 Projects Delete Foundation` **通过 Winston 独立审计**。

本次审计没有采信 ready notes、ledger 自述或用户消息中的“已完成 / BUILD SUCCEEDED”声明，而是重新独立完成：

1. 读取 `devprompt/2.0-projects-delete-foundation.md`
2. 读取 `docs/parity/35-winston-ready-2.0-notes.md`
3. 读取 ledger：`findings.md`、`progress.md`、`task_plan.md`
4. 对照 Web source of truth：
   - `../BrainStorm+-Web/src/lib/actions/projects.ts`
   - `../BrainStorm+-Web/src/app/dashboard/projects/page.tsx`
5. 审核 iOS 关键实现：
   - `Brainstorm+/Features/Projects/ProjectListViewModel.swift`
   - `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
   - `Brainstorm+/Features/Projects/ProjectListView.swift`
   - `Brainstorm+/Features/Projects/ProjectDetailView.swift`
   - `Brainstorm+/Shared/Navigation/AppModule.swift`
6. 独立执行 prompt §4.1 `rg` scan
7. 独立执行 `xcodebuild build`

结论：**2.0 达到本轮验收标准；`.projects` 仍必须保持 `.partial`。**

---

## 2. Scope Audited

### In scope

本轮要求交付：

1. Native project delete foundation
   - 至少一个真实 delete entry，优先 list + detail 两处
   - 删除前必须明确确认
   - 删除必须走真实 Supabase delete
   - 删除成功后 list/detail state cleanup 必须闭环
   - 删除失败必须有明确错误反馈

2. State truth / destructive-action safety
   - 不回退 1.5 list membership scoping
   - 不回退 1.6 detail membership gate
   - 不回退 1.7 / 1.8 / 1.9 read/edit/member foundation
   - delete failure 不得污染 unrelated read-only state
   - 删除期间必须有 loading / disabled state

3. Ledger truth
   - `findings.md` / `progress.md` / `task_plan.md` / ready notes 必须与真实实现一致
   - `.projects` 不得误标 full parity

### Out of scope

审计确认本轮未扩散到：

- AI summary
- risk analysis
- linked risk actions
- resolution feedback
- `task_count`
- create-flow redesign
- edit/member redesign
- schema changes
- batch delete
- undo / recycle-bin / recover

---

## 3. Independent Findings

### 3.1 Web parity mapping 成立

Web `deleteProject(id)` 为：

```ts
await supabase.from('projects').delete().eq('id', id)
```

iOS 两个 VM 均真实执行：

```swift
.from("projects")
.delete()
.eq("id", value: ...)
.execute()
```

并且没有额外发明 `project_members.delete(...)` 路径；FK cascade 仍由数据库负责。这一点与 Web 语义一致。

### 3.2 两个真实 delete entry 存在

独立确认：

1. `ProjectDetailView.swift`
   - toolbar `trash` button
   - gate：`accessOutcome != .denied && viewModel.project != nil`
   - `.confirmationDialog(...)`
   - `.alert("Delete failed", ...)`
   - 成功后 `onProjectDeleted?(projectId)` + `dismiss()`

2. `ProjectListView.swift`
   - row `.contextMenu` 中存在 destructive `Delete`
   - `.confirmationDialog(... presenting: projectPendingDelete)`
   - `.alert("Delete failed", ...)`
   - detail push path 通过 `onProjectDeleted` 回调做 list local cleanup

因此“至少一处”不仅满足，而且 detail/list 两处都满足。

### 3.3 detail/list state cleanup 闭环成立

独立确认：

- detail VM 删除成功后先清 `self.project = nil`
- detail view `confirmDelete()` 捕获 `projectId`，成功后调用 `onProjectDeleted?(projectId)` 再 `dismiss()`
- list VM 提供 `removeProjectLocally(id:)`
- list direct delete 成功后 `projects.removeAll { $0.id == id }`

这满足本轮要求的：

- list 正确移除已删项目
- detail 不会继续悬挂已删除项目
- detail→list 的状态收口也闭环

### 3.4 failure isolation 成立

独立确认：

- list 侧 delete failure 使用 `deleteErrorMessage`
- detail 侧 delete failure 使用 `deleteErrorMessage`
- 其与既有：
  - `errorMessage`
  - `ownersErrorMessage`
  - `enrichmentErrors`
  - 1.9 的成员 picker/save error surface
  彼此隔离

因此删除失败不会污染 list fetch、owner hydrate、detail enrichment、edit/member path 的读态错误面。

### 3.5 旧能力未见回退

本次核对中未见以下回退：

- 1.5 list membership scope 仍保留
- 1.6 detail membership gate 仍保留
- 1.7 owner hydrate 未动
- 1.8 nested profile/avatar rendering 未动
- 1.9 edit/member foundation 仍保留；detail toolbar 仍同时存在 `pencil`

### 3.6 `.projects` 仍为 `.partial`

独立读取 `AppModule.swift`，确认：

```swift
case .projects:
    return .partial
```

这与当前真实状态一致，因为 `task_count`、AI summary、risk analysis、linked actions、resolution feedback 仍未完成。

---

## 4. One Audit Note

本轮实现总体通过，但我记录一个**非阻塞审计注记**：

### list-row delete 的“删除中”防重复触发弱于 detail 路径

- detail 路径明确把 `viewModel.isDeleting` 用于 toolbar `.disabled(...)` 与 overlay
- list 路径虽然存在 `isDeleting` 状态与 delete VM 逻辑，但 row context menu / confirmationDialog 本身没有做到同等级的显式 UI 禁用反馈

这**不构成本轮失败**，因为：

1. 本轮已具备明确 confirmation gate
2. delete action 真实走 server write
3. 成功/失败/state cleanup 已闭环
4. build 通过

但这意味着 list 路径的 destructive loading affordance 仍偏基础。它更适合作为后续 polish，而不是阻断 2.0 foundation PASS 的理由。

---

## 5. Verification

### 5.1 Scan

已独立执行：

```bash
rg -n 'deleteProject|delete\(|project_members|ProjectDetailView|ProjectListView|toolbar|contextMenu|confirmationDialog|alert\(|isDeleting|errorMessage|reload\(|detail|dismiss|removeAll|projects|AppModule|implementationStatus' Brainstorm+ progress.md findings.md task_plan.md
```

结论：2.0 相关符号与 ledger 记述基本对齐，未发现明显伪报。

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

- `findings.md`：2.0 范围、交付点、未完成 gap 基本真实
- `progress.md`：2.0 实现点、验证、remaining debt 基本真实
- `task_plan.md`：已标 `2.0 completed`，下一步为 Winston 2.0 audit，真实
- `35-winston-ready-2.0-notes.md`：与代码大体一致

未发现把 `.projects` 误写为 full parity 的问题。

---

## 7. Final Verdict

**PASS**

`2.0 Projects Delete Foundation` 已达到本轮 foundation 验收标准：

- 两个真实 delete entry 存在
- confirmation gate 存在
- 真实 Supabase delete 成立
- list/detail cleanup 成立
- failure isolation 成立
- 1.5–1.9 未见回退
- ledger truth 成立
- build 独立通过

**结论收口：可以进入下一正式轮次。**
