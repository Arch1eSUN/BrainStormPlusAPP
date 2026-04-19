# 34 Winston Audit — 1.9 Projects Edit + Member Management Foundation

**Round:** `1.9 Projects Edit + Member Management Foundation`  
**Date:** 2026-04-16  
**Auditor:** Winston  
**Result:** PASS

## 1. Verdict

`1.9 Projects Edit + Member Management Foundation` **通过 Winston 独立审计**。

本次审计没有直接采信 `33-winston-ready-1.9-notes.md`、`progress.md` 或外部消息中的 “rg scan passed / BUILD SUCCEEDED” 声明，而是重新独立完成：

1. 读取 1.9 ready notes 与 dev prompt。
2. 读取 ledger：`findings.md`、`progress.md`、`task_plan.md`。
3. 对照 Web source of truth：
   - `../BrainStorm+-Web/src/lib/actions/projects.ts`
   - `../BrainStorm+-Web/src/app/dashboard/projects/page.tsx`
4. 审核 iOS 关键实现：
   - `Brainstorm+/Features/Projects/ProjectEditViewModel.swift`
   - `Brainstorm+/Features/Projects/ProjectEditSheet.swift`
   - `Brainstorm+/Features/Projects/ProjectMemberCandidate.swift`
   - `Brainstorm+/Features/Projects/ProjectDetailView.swift`
   - `Brainstorm+/Features/Projects/ProjectListView.swift`
   - `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
   - `Brainstorm+/Features/Projects/ProjectListViewModel.swift`
   - `Brainstorm+/Core/Models/Project.swift`
5. 独立执行 prompt §4.1 `rg` scan。
6. 独立执行 prompt §4.2 `xcodebuild build`。

结论：**1.9 达到本轮验收标准；`.projects` 仍应保持 `.partial`。**

---

## 2. Scope Audited

### In scope

本轮应交付：

1. Native project edit foundation：
   - 至少一个真实 edit entry，优先 list + detail 两处。
   - 编辑字段覆盖 `name` / `description` / `start_date` / `end_date` / `status` / `progress`。
   - 保存走真实 Supabase update。
   - 保存成功后 list / detail 刷新。
   - 保存失败有明确错误状态。

2. Member management foundation：
   - 能看到当前项目成员状态。
   - 能增减成员。
   - 对齐 Web `member_ids` delete-then-insert rewrite 语义。
   - 使用 batched `profiles` picker，不允许 N+1。
   - owner 不可被意外移除。

3. State truth / failure isolation：
   - 不回退 1.5 list membership scoping。
   - 不回退 1.6 detail membership gate。
   - 不回退 1.7 owner hydrate。
   - 不回退 1.8 nested profile names / avatar rendering。
   - edit / member update 失败不得污染 unrelated read-only sections。
   - 保存时有 loading / disabled state。
   - 基础校验：name 非空、progress 夹在 `0...100`、日期 payload 不明显错误。

4. Ledger truth：
   - `findings.md`、`progress.md`、`task_plan.md` 与 ready notes 必须真实反映完成和未完成。
   - `.projects` 不得误报 full parity。

### Explicitly out of scope

本轮不要求、且不得借机扩散到：

- project delete
- create-flow redesign
- AI summary
- risk analysis
- linked risk actions
- resolution feedback
- `task_count`
- 大型 UI redesign
- schema changes

审计确认：以上均未被纳入 1.9 交付，且 ledger 明确记录仍 deferred。

---

## 3. Evidence Reviewed

### 3.1 Ready / prompt / ledger

已读：

- `docs/parity/33-winston-ready-1.9-notes.md`
- `devprompt/1.9-projects-edit-member-management-foundation.md`
- `findings.md`
- `progress.md`
- `task_plan.md`

核对结果：

- `33-winston-ready-1.9-notes.md` 对交付范围、实现文件、Web parity mapping、禁止事项、remaining debt 的描述与代码基本一致。
- `findings.md` 已切换到 Sprint 1.9，明确把 edit/member/owner protection 标为 Delivered，并保留 delete / AI / risk / linked actions / resolution feedback / `task_count` 为 gap。
- `progress.md` 已记录 1.9 completed、skills 使用、build passed、remaining debt。
- `task_plan.md` 已标记：
  - `1.9 Projects Edit + Member Management Foundation completed`
  - next step 是 Winston 1.9 audit
  - Projects beyond current foundation 仍包括 delete / AI / risk / linked actions / resolution feedback / `task_count`
- `.projects` 没有被误报为 fully implemented。

### 3.2 Web source of truth

已核对 Web Projects source：

- `fetchProjects(...)`：admin sees all；non-admin 通过 `project_members` scoped ids；search/status server-side；order `created_at DESC`。
- `fetchProjectMembers(projectId)`：从 `project_members` 读取 `user_id`。
- `fetchAllUsersForPicker()`：从 `profiles` 读取 `id, full_name, avatar_url, role, department`，过滤 `status = active`，按 `full_name` 排序。
- `updateProject(id, updates)`：
  - `projects.update({ ...projectUpdates, updated_at: new Date().toISOString() }).eq('id', id).select('*, profiles:owner_id(full_name, avatar_url)').single()`
  - 若 `member_ids !== undefined`：
    - 获取 `owner_id`
    - 删除 non-owner members：`.delete().eq('project_id', id).neq('user_id', ownerId)`
    - 插入 `member_ids` 中非 owner 的 rows，`role: 'member'`
- `page.tsx` edit dialog：
  - `openEditProject(...)` seed `editForm` 与 current members。
  - `handleUpdateProject(...)` 写入 `name`、`description || undefined`、`start_date || undefined`、`end_date || undefined`、`status`、`progress clamped 0...100`、`member_ids`。
  - list card 与 detail panel 均有 edit action。
  - Web 仍有 delete、AI summary、risk analysis、linked risk actions、resolution feedback，iOS 本轮未覆盖，属于真实 remaining gap。

---

## 4. iOS Implementation Findings

### 4.1 Native edit foundation — PASS

#### Evidence

`ProjectEditViewModel.swift` 新增：

- `@MainActor public class ProjectEditViewModel: ObservableObject`
- seeded from `Project`
- form state：
  - `name`
  - `descriptionText`
  - `status`
  - `progress`
  - `includeStartDate` / `startDate`
  - `includeEndDate` / `endDate`
- save state：
  - `isSaving`
  - `errorMessage`
- validation：
  - `trimmedName`
  - `isSaveEnabled = !trimmedName.isEmpty && !isSaving`
- save path：
  - `.from("projects").update(payload).eq("id", value: projectId).select().single().execute().value`
  - returns refreshed `Project`
  - `updatedAt` sent via `ISO8601DateFormatter()`
  - `progress` clamped with `max(0, min(100, progress))`

`ProjectUpdatePayload` contains:

- `name`
- `description`
- `start_date`
- `end_date`
- `status`
- `progress`
- `updated_at`

`ProjectEditSheet.swift` 新增：

- `NavigationStack > Form`
- Project Details section：name + description
- Schedule section：start/end include toggles + `DatePicker`
- Status & Progress section：status picker + progress slider
- Members section
- toolbar Cancel / Save
- `isSaving` overlay + disabled controls
- save failure rendered via `errorMessage`

`ProjectDetailView.swift`：

- 新增 detail toolbar pencil button。
- `accessOutcome != .denied && project != nil` 才显示 edit affordance。
- `.sheet(isPresented:)` presents `ProjectEditSheet`。
- save success 后：
  - `onProjectUpdated?(refreshed)` 通知 parent list
  - `Task { await reload() }` 刷新 detail

`ProjectListView.swift`：

- 新增 `projectBeingEdited: Project?`
- row `.contextMenu` 提供 “Edit” action。
- `.sheet(item:)` presents `ProjectEditSheet`。
- save success 后 `Task { await reload() }`。
- pushed `ProjectDetailView` receives `onProjectUpdated` to refresh list after detail-side edit。

#### Judgment

PASS。

1.9 提供两处真实 edit entry：

1. detail toolbar pencil
2. list row long-press context menu

字段覆盖满足 prompt；保存不是本地假提交，而是真实 Supabase update；保存后 list / detail 会重新加载 server truth；失败有错误面。

---

### 4.2 Member management foundation — PASS

#### Evidence

`ProjectMemberCandidate.swift` 新增 narrow DTO：

- `id`
- `fullName` ← `full_name`
- `avatarUrl` ← `avatar_url`
- `role`
- `department`
- `displayName`

`ProjectEditViewModel.load()`：

- parallel `async let`：
  - `runCandidatesFetch()`
  - `runMembersFetch()`
- candidates fetch：
  - `.from("profiles")`
  - `.select("id, full_name, avatar_url, role, department")`
  - `.eq("status", value: "active")`
  - `.order("full_name", ascending: true)`
- members fetch：
  - `.from("project_members")`
  - `.select("user_id")`
  - `.eq("project_id", value: projectId)`
- `selectedMemberIds` seeded from current project members。
- owner forcibly inserted into `selectedMemberIds`。
- picker/member fetch failures go to `candidatesErrorMessage` rather than save `errorMessage`。

`toggleMember(_:)`：

- owner id short-circuits immediately。
- non-owner ids are added/removed from `selectedMemberIds`。

`filteredCandidates`：

- client-side search over `full_name` / `department` / `role`。
- no extra network calls。

`rewriteMembers()`：

- if `ownerId` exists：
  - `.from("project_members").delete().eq("project_id", value: projectId).neq("user_id", value: ownerId)`
- inserts selected ids excluding owner:
  - `ProjectMemberInsert(project_id: projectId, user_id: uid, role: "member")`

`save()` only rewrites members when：

- `candidatesErrorMessage == nil`
- `selectedMemberIds != originalMemberIds`

#### Judgment

PASS。

实现对齐 Web `member_ids` 的核心语义：**delete non-owner rows → insert selected non-owner rows**。同时 iOS 额外增加了合理保护：picker fetch 失败时不进行 member rewrite，避免用不可信的 partial local state 覆盖服务器成员表。

Owner protection 达到 3 层：

1. VM：`toggleMember` 阻止 owner deselect。
2. UI：owner row disabled + “Owner” badge。
3. Wire：delete 使用 `.neq("user_id", ownerId)`，insert 过滤 owner。

不存在 N+1：sheet open cost 是 candidates + current members 两个 batched fetch。

---

### 4.3 State truth / previous rounds non-regression — PASS

#### 1.5 list membership scoping

`ProjectListViewModel.swift` 未被 1.9 修改核心 fetch path：

- admin：unscoped projects query。
- non-admin：先查 `project_members`，再 `.in("id", values: memberProjectIds)`。
- zero membership：返回空列表，不 fallback 到全量 projects。
- search/status server-side filters preserved。
- order `created_at DESC` preserved。

Judgment：PASS。

#### 1.6 detail membership gate

`ProjectDetailViewModel.swift` gate 仍存在：

- non-admin 必须有 `userId`。
- `checkMembership(userId:)` 查询 `project_members`。
- membership absent → `applyDeniedState()`。
- denied 清理：
  - `project = nil`
  - `owner = nil`
  - `tasks = []`
  - `dailyLogs = []`
  - `weeklySummaries = []`
  - `profilesById = [:]`
  - `enrichmentErrors = [:]`
  - `accessOutcome = .denied`

1.9 detail edit button 又额外 gated by `accessOutcome != .denied && project != nil`。

Judgment：PASS。

#### 1.7 owner hydrate

`ProjectListViewModel.ownersById` batched owner hydrate preserved。  
`ProjectDetailViewModel.fetchOwner(ownerId:)` preserved。  
`ProjectOwnerSummary` reuse preserved。

Judgment：PASS。

#### 1.8 nested profile names + avatar rendering

`ProjectDetailViewModel.profilesById` and `hydrateSublistProfiles()` preserved。  
`ProjectDetailView.displayName(forUserId:)` usage preserved。  
Owner avatar / card avatar rendering from 1.8 remains in existing views。

Judgment：PASS。

---

## 5. Validation Results

### 5.1 Independent rg scan

Command executed:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
rg -n 'updateProject|fetchProjectMembers|fetchAllUsersForPicker|member_ids|owner_id|project_members|ProjectDetailView|ProjectListView|sheet|Dialog|progress|status|start_date|end_date|name|description|save|retry|isSaving|selectedMemberIds|profiles|full_name|avatar_url|AccessOutcome|fetchDetail\(|fetchProjects\(' Brainstorm+ progress.md findings.md task_plan.md
```

Result: required symbols found across implementation and ledger, including：

- `ProjectMemberCandidate.swift`
- `ProjectEditViewModel.swift`
- `ProjectEditSheet.swift`
- `ProjectDetailView.swift`
- `ProjectListView.swift`
- `ProjectDetailViewModel.swift`
- `ProjectListViewModel.swift`
- `findings.md`
- `progress.md`
- `task_plan.md`

Scan confirms the expected implementation surface exists. No missing required symbol found in the audited scope.

### 5.2 Independent build

Command executed:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
```

Result:

```text
** BUILD SUCCEEDED **
```

Build exit code: `0`.

---

## 6. Issues / Caveats

### 6.1 Non-blocking caveat — date clearing semantics

iOS uses include toggles for start/end dates. When untoggled, the payload omits `start_date` / `end_date`, meaning the server column remains unchanged.

This matches Web's current `editForm.start_date || undefined` / `editForm.end_date || undefined` behavior, so it is **not a parity failure**. However, UX-wise it means users cannot explicitly clear a previously saved date from iOS 1.9.

Severity: Low / deferred.

### 6.2 Non-blocking caveat — partial-success member sync UX

If project update succeeds but member rewrite fails, `save()` sets:

```swift
errorMessage = "Project saved, but member update failed: ..."
```

and still returns the refreshed project, so the sheet dismisses via `onSaved(refreshed)`.

This is honest about server state and does not fake success. However, a future UX improvement could keep the sheet open or provide a member-only retry affordance.

Severity: Low / deferred.

### 6.3 Non-blocking caveat — list edit entry discoverability

List edit entry is long-press context menu. It is a real native edit entry and satisfies the prompt, but less discoverable than Web's visible hover pencil.

Detail toolbar pencil provides the primary visible entry, so this is not blocking.

Severity: Low / deferred.

### 6.4 Non-blocking caveat — iOS client guard is not security boundary

As already documented in prior rounds, iOS role/membership gating is a UX/data-shaping layer. Real enforcement must remain Supabase RLS / server-side policy.

1.9 does not worsen this. It also does not claim to be a standalone authorization system.

Severity: Known architecture caveat / unchanged.

---

## 7. Ledger Truth Check

PASS。

- `progress.md` correctly says 1.9 is built and ready for audit.
- `findings.md` correctly marks edit/member/owner protection as delivered.
- `task_plan.md` correctly marks 1.9 completed and keeps remaining Projects parity gaps.
- `.projects` remains `.partial`.

No false claim of full Projects parity found.

---

## 8. Final Audit Result

**PASS — 1.9 Projects Edit + Member Management Foundation is accepted.**

Accepted deliverables:

1. Detail edit entry。
2. List row edit entry。
3. Edit sheet covering `name` / `description` / `start_date` / `end_date` / `status` / `progress`。
4. Real Supabase `projects.update(...).select().single()` save path。
5. Batched member picker via `profiles`。
6. Current member load via `project_members`。
7. Member add/remove via Web-aligned delete-then-insert rewrite。
8. Owner protection at VM / UI / wire layers。
9. Save loading / disabled state。
10. Isolated picker vs save errors。
11. List/detail refresh after successful save。
12. No regression to 1.5 / 1.6 / 1.7 / 1.8。
13. Independent `rg` scan completed。
14. Independent `xcodebuild build` completed with `** BUILD SUCCEEDED **`。

Remaining Projects gaps intentionally deferred:

- project delete
- AI summary
- risk analysis
- linked risk actions
- resolution feedback
- `task_count`
- possible future UX refinement for clearing dates and member-only retry

**Recommendation:** proceed to the next narrow Projects parity round. The highest-value next candidate is likely `2.0 Projects Delete + Task Count Foundation` or a separate AI/risk foundation round, but it should be scoped as one narrow prompt, not a combined catch-all.
