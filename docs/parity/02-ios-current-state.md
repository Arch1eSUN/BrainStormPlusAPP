# 02 iOS Current State

## 已有 Feature
- `Attendance` (Views, ViewModel)
- `Auth` (Session, Role checking via RBACManager)
- `Chat` (Basic chat layout)
- `Copilot` (View & Service)
- `Dashboard` (MainTabView, Dashboard quick actions partially mocked)
- `KnowledgeBase`
- `Leaves`
- `Notifications`
- `OKRs`
- `Payroll`
- `Reporting` (Daily/Weekly templates)
- `Schedule`
- `Settings`
- `Tasks` (List & Cards)

## 已有 Model
- `TaskModel`, `Project`, `Deliverable`
- `Attendance`, `Reporting`, `Schedule`
- `Profile`, `NotificationModel`
- (Supabase Models with Realtime Capabilities partially mapped).

## 仍存在 / 继续 Backlog 中的记录问题
- `TaskListView.swift`:
  - **New Task 遗漏:** Line 116 marks `// TODO: Open New Task Sheet`, essentially breaking the critical create action flow. This is deliberately retained for `1.0` feature sprint.
- `Copilot` API connection:
  - Needs to explicitly integrate with `/api/chat` correctly in the backend format.
- `ActionItemHelper`:
  - A strict entry point `destination(for module: AppModule)` has been fully implemented. However, a legacy `destination(for title: String)` is still preserved as a compatibility layer since `DashboardView`'s quick actions predominantly trigger routes using generic titles instead of proper modules. Final migration of these callers is pending.

## 与 Web 1:1 差距
- Navigation Routing for 15+ missing screens (approvals, admin, analytics, financials, hiring, team).
- Supabase queries are disparate across some iOS features rather than following consistent patterns from web's RPCs or RLS standards.