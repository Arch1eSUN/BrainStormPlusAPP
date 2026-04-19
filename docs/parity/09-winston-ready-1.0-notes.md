# 09 Winston Ready 1.0 Notes

## Routing Migration Summary
- **Typed Strategy Enforced**: `DashboardView.swift` quick actions have been completely migrated away from `ActionItemHelper.destination(for title: String)` to `ActionItemHelper.destination(for module: AppModule)`.
- **Legacy Layer Sandboxing**: The old `destination(for title:)` signature remains exclusively as a compatibility layer for any residual widgets, but is explicitly annotated as `@available(*, deprecated)` to prevent future usage.

## Task Create Flow Summary
- **Create Flow Additions**: Replaced the `TODO: Open New Task Sheet` inside `TaskListView.swift`.
- **UX Strategy**: Integrated a SwiftUI `@State` controlled `.sheet` embedding a native `CreateTaskView` form. Includes real-time validation (title required), asynchronous loading spinners, form inputs (Description, Priority `TaskModel.TaskPriority`, and Due Date), and error handling toasts. Refresh runs automatically.
- **ViewModel Integration**: Configured `TaskListViewModel.createTask(...)` with strongly-typed `Encodable` models sending explicit snake_case payloads.

## Schema Assumptions Verified from Web
- Looked directly at `BrainStorm+-Web/src/lib/actions/tasks.ts` and `BrainStorm+-Web/supabase/schema.sql`.
- iOS create payload now explicitly sends authenticated-user-derived `owner_id`, `assignee_id`, `reporter_id`, `created_by`, and `progress: 0` to match Web/RLS-critical behavior.
- No hardcoded UUIDs, no service-role bypass.
- `due_date` is encoded as `yyyy-MM-dd` for Postgres `DATE` semantics.
- Status enum still has known Web/iOS mismatch: Web uses `review`; iOS model includes `in_review` and `canceled`. Create path writes `todo`, so this does not block create, but it remains task parity debt. 

## Remaining Debt
- User Pickers (Assignee / Project Id) inside Tasks are deferred backlogs due to missing complex dependency data sets.
- Residual Views (Reports, Activity, HR components) still hit `ParityBacklogDestination`.

## Exact Build Command/Result
`xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO`
**Result**: `** BUILD SUCCEEDED **`
