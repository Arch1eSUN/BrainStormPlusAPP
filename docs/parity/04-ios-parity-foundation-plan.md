# 04 iOS Parity Foundation Plan

## API / Repository Structure
- **RBACManager**: Should pull claims/capabilities precisely matching the web `capabilities.ts`. Roles: employee/admin/superadmin/chairperson.
- **Repository / API Bridge**:
  - Direct read/write via Supabase SDK (RLS). Realtime streams data automatically.
  - Bridge API via `/api/chat` or NextJs edge functions when server-side business logic or third-party service calls (e.g. AI logic, mailing, payment) are executed on the web.
- **RealtimeSyncManager**: Stream presence and entity updates. Keep it modular matching Web channel setup.

## Module Routing Map
- `AppModule.swift` stands as the foundation enum for app routing.
- The `ActionItemHelper` now provides a strict entry point `destination(for module: AppModule)`. The legacy string logic remains as a compatibility layer.
- Developing a central `NavigationManager` passing Destination objects tied completely to `AppModule` is the next priority for migrating callers.

## Prioritization Matrix
1. **P0 (Immediate Migration)**
   - Tasks (CRUD + Lists)
   - Projects (CRUD)
   - Home Dashboard
   - Basic Approvals Framework
2. **P1 (Subsequent Rollout)**
   - Schedules / OKR
   - Attendance & Leaves
   - Knowledge Base & Chat enhancements
3. **P2 (Backlog / Admin / Specialized)**
   - Hiring / Admin Config / Finance AI / Payroll

## Next Step Goal for Next Sprint
**Do not prompt or execute this here.**
The next step will be to firmly refactor the Navigation and ActionItem routing completely across `DashboardView`, ensuring no dead-ends and pure linkage to empty parity placeholders or true functional views.