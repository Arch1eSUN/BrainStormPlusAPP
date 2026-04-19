# 10 Winston Audit — 1.0 Navigation Typed Routing + Tasks Create Flow

**Audit Time:** 2026-04-16 01:34 GMT+8  
**Auditor:** Winston  
**Result:** FAIL — enter `1.0-0.1`, do not proceed to `1.1`.

## 1. Audit Scope

Audited against:

- `devprompt/1.0-navigation-and-tasks-sprint.md`
- `docs/parity/09-winston-ready-1.0-notes.md`
- `task_plan.md`
- `findings.md`
- `progress.md`
- `Brainstorm+/Features/Dashboard/DashboardView.swift`
- `Brainstorm+/Features/Dashboard/ActionItemHelper.swift`
- `Brainstorm+/Features/Tasks/TaskListView.swift`
- `Brainstorm+/Features/Tasks/TaskListViewModel.swift`
- `Brainstorm+/Core/Models/TaskModel.swift`
- `../BrainStorm+-Web/src/lib/actions/tasks.ts`
- `../BrainStorm+-Web/supabase/schema.sql`
- `../BrainStorm+-Web/supabase/migrations/012_fix_tasks_rls.sql`
- independent scan
- independent xcodebuild

## 2. Positive Findings

### 2.1 Build passes

Independent command:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
```

Result:

```text
** BUILD SUCCEEDED **
```

### 2.2 Dashboard typed routing mostly passes

Confirmed:

- `DashboardView.swift` quick action path calls:

```swift
ActionItemHelper.destination(for: module)
```

- `ActionItemHelper.destination(for module:)` exists.
- `ActionItemHelper.destination(for title:)` is marked deprecated.
- The fuzzy `contains(...)` routing is now isolated inside deprecated legacy compatibility code.

This satisfies the main typed routing requirement for Dashboard's current quick action path.

### 2.3 New Task TODO text was removed

Confirmed:

- `TODO: Open New Task Sheet` no longer appears in `TaskListView.swift`.
- A `CreateTaskView` exists.
- `TaskListViewModel.createTask(...)` exists.

These are necessary but not sufficient.

## 3. Blocking Issues

### B1 — Create Task sheet is not mounted to `TaskListView`

In `TaskListView.swift`, the plus button sets:

```swift
isShowingCreateTask = true
```

But the view body does not attach a corresponding `.sheet(isPresented:)` that presents `CreateTaskView`.

Impact:

- The user can tap the plus button, but the create form is not actually presented.
- This fails the 1.0 functional requirement: “补齐 New Task create flow”.
- The implementation compiles but the primary user flow is broken.

Required fix:

Attach the sheet to the appropriate root view, e.g. the `NavigationStack` / `ZStack` chain:

```swift
.sheet(isPresented: $isShowingCreateTask) {
    CreateTaskView(viewModel: viewModel)
}
```

Then verify the button opens the sheet.

Severity: Critical / functional blocker.

---

### B2 — iOS task insert payload does not align with Web create action / RLS-critical fields

Web source of truth:

`../BrainStorm+-Web/src/lib/actions/tasks.ts` creates tasks with:

```ts
.insert({
  title: form.title,
  description: form.description,
  status: form.status || 'todo',
  priority: form.priority || 'medium',
  owner_id: form.owner_id,
  assignee_id: form.owner_id,
  project_id: form.project_id,
  due_date: form.due_date,
  reporter_id: user.id,
  created_by: user.id,
  progress: 0,
})
```

The migration `012_fix_tasks_rls.sql` explicitly states that previous inserts failed because `reporter_id` was NULL and `created_by` was not checked in policy. Its policy includes:

```sql
auth.uid() = assignee_id
OR auth.uid() = reporter_id
OR auth.uid() = created_by
```

Current iOS insert only sends:

```swift
title
description
priority
status
due_date
```

Impact:

- iOS task creation may compile but fail at runtime due to RLS / visibility / ownership mismatch.
- Even if insert happens under a permissive policy, the created task may not appear under the Web scope model because Web fetch applies scope around `owner_id`.
- `docs/parity/09-winston-ready-1.0-notes.md` claims omitting explicit ownership fields is intentional, but this contradicts the actual Web create action and the RLS fix migration.

Required fix:

Use authenticated Supabase user id from the current session and include the Web-aligned fields where allowed by RLS:

- `reporter_id: user.id`
- `created_by: user.id`
- `progress: 0`
- if no owner picker exists, use current user as owner:
  - `owner_id: user.id`
  - `assignee_id: user.id` for legacy compatibility

This is not “fabricated sysadmin data”; it is the authenticated user's actual id and matches Web behavior's fallback owner logic.

Severity: Critical / data-write and RLS blocker.

---

### B3 — `due_date` format likely mismatches Web/table semantics

Web task type uses:

```ts
due_date?: string
```

Web stats compare it as a date string:

```ts
const today = new Date().toISOString().split('T')[0]
```

SQL schema defines:

```sql
due_date DATE
```

Current iOS code uses:

```swift
ISO8601DateFormatter().string(from: dueDate)
```

which produces a full timestamp, not `YYYY-MM-DD`.

Impact:

- Supabase/Postgres may cast it, but relying on implicit timestamp-to-date casting is not parity-safe.
- It may cause timezone off-by-one behavior.

Required fix:

Encode `due_date` as `yyyy-MM-dd` when present.

Severity: High.

---

### B4 — Status enum mismatch remains unhandled

Web type declares:

```ts
export type TaskStatus = 'todo' | 'in_progress' | 'review' | 'done'
```

Current iOS model has:

```swift
case inReview = "in_review"
case canceled = "canceled"
```

This existed before, but 1.0 touched task create/status flow and should record the mismatch accurately.

Impact:

- Create uses `todo`, so immediate create is not blocked.
- Existing status update flow may still write statuses Web does not use (`canceled`, `in_review` vs `review`).

Required fix for this repair round:

- At minimum document the mismatch in `findings.md` and `09-winston-ready-1.0-notes.md`.
- Do not silently claim exact enum parity.

Severity: Medium for 1.0 create path, High for broader task parity.

## 4. Scan Result

Independent scan command:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
rg -n "if true|PlaceholderDestination|TODO: Open New Task Sheet|destination\(for title|destination\(for module|contains\(" Brainstorm+/Features/Dashboard Brainstorm+/Features/Tasks Brainstorm+/Shared/Navigation || true
```

Result summary:

- no `if true`
- no active `PlaceholderDestination` implementation usage in app source scan scope
- no `TODO: Open New Task Sheet`
- `destination(for module:)` present
- `destination(for title:)` present but deprecated
- `contains(...)` remains only in deprecated legacy compatibility helper

Scan is acceptable except for the functional and data-write issues above.

## 5. Final Verdict

`1.0` does **not** pass.

Reason:

- UI create flow is not actually mounted.
- Insert payload is not aligned with Web create action or RLS-critical fields.
- Date encoding is not parity-safe.
- Docs overstate schema parity.

Proceed to minimal repair round:

- `devprompt/1.0-0.1-task-create-repair.md`
