# 16 Winston Audit — 1.1 Task Status Enum + Picker Parity

**Audit Time:** 2026-04-16 02:36 GMT+8  
**Auditor:** Winston  
**Result:** FAIL — enter `1.1-0.1`, do not proceed to `1.2`.

## 1. Audit Scope

Audited against:

- `devprompt/1.1-task-status-and-picker-parity.md`
- `progress.md`
- `findings.md`
- `task_plan.md`
- `docs/parity/15-winston-ready-1.1-notes.md`
- `Brainstorm+/Core/Models/TaskModel.swift`
- `Brainstorm+/Features/Tasks/TaskListView.swift`
- `Brainstorm+/Features/Tasks/TaskListViewModel.swift`
- `Brainstorm+/Features/Tasks/TaskCardView.swift`
- `../BrainStorm+-Web/src/lib/actions/tasks.ts`
- independent scan
- independent xcodebuild

## 2. Independent Verification

### 2.1 Build result

Independent command:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
```

Result:

```text
** BUILD SUCCEEDED **
```

### 2.2 What now passes

#### P1 — Status enum parity is materially improved

Confirmed in `TaskModel.swift`:

```swift
case review = "review"
```

And the previous `in_review` runtime value is no longer the active enum case.

Confirmed in `TaskCardView.swift` and `TaskListView.swift`:

- status handling uses `.review`
- `.canceled` is no longer used as a live state path
- destructive action is now `Delete Task`

This resolves the previously known `review` vs `in_review` drift in the iOS code path.

#### P2 — Project picker UI exists

Confirmed in `CreateTaskView`:

```swift
Picker("Project (Optional)", selection: $projectId)
```

And `TaskInsert` now includes:

```swift
project_id: projectId
```

So the create form is no longer hardcoded to no-project only.

#### P3 — Assignee picker is explicitly deferred with a bounded explanation

Web source of truth does support owner/participant concepts, but the current iOS view model does not preload the additional people-selection dataset. A defer decision is acceptable **only if** the current fallback remains truthful and the ledger is synchronized.

## 3. Blocking Issues

### B1 — Project picker data is not loaded on initial entry

Although `CreateTaskView` now contains a project picker, `TaskListView` only calls:

```swift
.task {
    await viewModel.fetchTasks()
}
```

`fetchProjects()` is only called inside `.refreshable`, not on initial entry and not before presenting the sheet.

Impact:

- On first open, the project picker may render with only `None` and no actual project options.
- The UI exists, but the parity requirement is not functionally complete because the data source is not guaranteed to be populated in the primary path.

Required fix:

At minimum, ensure projects are loaded in the default path, e.g.:

- call `await viewModel.fetchProjects()` in `.task`, or
- preload before presenting the create sheet, or
- both if needed for robustness.

Severity: High / functional parity blocker.

---

### B2 — `progress.md` still mixes old 1.0 statements with 1.1 claims

Current `progress.md` still includes stale 1.0-era statements such as:

- `Status enum debt remains.`
- `Replaced // TODO: Open New Task Sheet in TaskListView.swift.`
- `Ledger stale issue identified by Winston and fixed in this round.`
- `Creating docs/parity/15-winston-ready-1.1-notes.md.`

Impact:

- The file is no longer a truthful 1.1 progress ledger.
- It mixes resolved old repairs with current-round claims, making the audit trail unreliable.

Severity: High / ledger blocker.

---

### B3 — `findings.md` still contains contradictory old statements

The file still contains older statements such as:

- `Remaining debt: real assignee/project picker not implemented`
- `no assignee/project picker UI exists yet`

But the current code now **does** include a project picker UI.

Impact:

- Ledger contradicts implementation truth.
- The current 1.1 note cannot be trusted as a synchronized summary.

Severity: High / ledger blocker.

## 4. Final Verdict

`1.1` does **not** pass.

### Reason

- Status enum parity moved in the right direction and build passes.
- But project picker is not functionally wired to guaranteed initial data loading.
- And the required ledgers (`progress.md`, `findings.md`) are not synchronized to the new implementation truth.

Proceed to minimal repair round:

- `devprompt/1.1-0.1-project-picker-load-and-ledger-sync.md`
