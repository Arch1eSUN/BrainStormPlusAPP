# 15 Winston Ready 1.1 Notes

## Task Status Parity
- Discovered iOS `.inReview` disjoint from Web `'review'`. Changed rawValue to match.
- Discovered Web Types entirely omitted `cancelled` despite Postgres CHECK accepting it. Migrated iOS `Cancel Task` button to `Delete Task` integrating `deleteTask()` supabase chain, matching Web's `deleteTask` architecture.

## Picker Assessment
- Added `projectId` native Picker successfully since `projects: [Project]` was already accessible inside `TaskListViewModel` without expanding scope.
- **Deferred**: Assignee Picker. iOS does not fetch profiles in this view, so `assignee` defaults to the authenticated `user.id` (owner=creator fallback). Adding an assignee picker requires cross-module dependencies which is deferred parity debt.

## Build Command/Result
`xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO`
**Result**: `** BUILD SUCCEEDED **`