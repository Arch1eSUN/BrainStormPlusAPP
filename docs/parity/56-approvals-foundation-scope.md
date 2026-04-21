# 56 — Approvals iOS Foundation Scope (Sprint 4.1)

**Date:** 2026-04-21
**Status:** Scoping doc. Sprint 4.1 in progress (read-only foundation).
**Author:** Claude (autonomous session)

## Why this doc exists

The Approvals module is a net-new feature surface on iOS — zero existing
chat-style "3.1 foundation" to build on, and ~2500 lines of TypeScript
across 11 files on the Web side (`BrainStorm+-Web/src/app/dashboard/approval/*`
+ `src/lib/actions/approval-requests.ts` + `src/lib/approvals/types.ts` +
`src/lib/approval/routing.ts`). A single autonomous sprint cannot
responsibly port the whole module. This doc records the scope split so
the user can redirect any of the later sprints if the foundation-
closeout tone turns out to diverge from what they want.

## Web module at a glance

```
src/lib/approvals/types.ts            213 lines — domain types (enums + DTOs)
src/lib/approval/routing.ts           181 lines — capability-based approver eligibility
src/lib/actions/approval-requests.ts  900+ lines — server actions (submit + list + approve + reject + revoke)

src/app/dashboard/approval/
  page.tsx                            216 lines — 7-tab layout (mine + 6 approver queues)
  _tabs/my-submissions.tsx            185 lines — "我提交的" (the only user-centric tab)
  _tabs/leave-list.tsx                146 lines — approver queue, filtered by type
  _tabs/field-work-list.tsx           139 lines
  _tabs/business-trip-list.tsx        148 lines
  _tabs/expense-list.tsx              139 lines
  _tabs/report-list.tsx               137 lines
  _tabs/generic-list.tsx              139 lines
  _tabs/approval-item-card.tsx        123 lines — shared list-row component
  _dialogs/approval-detail-dialog.tsx 615 lines — detail + approve/reject actions
  _dialogs/revoke-comp-time-dialog.tsx 119 lines — self-service revoke flow
```

**Database shape** (migration `020_approval_domain.sql` + `027_permission_alignment.sql`):

- `approval_requests` — base row. RLS SELECT: `auth.uid() = requester_id`
  OR role-is-approver (approver branch depends on request_type).
- `approval_request_leave` / `_reimbursement` / `_procurement` — per-
  type detail tables, 1:1 to base row. RLS SELECT: follows request-row
  access via `EXISTS` join on `approval_requests`.
- `approval_actions` — audit log (approve / reject / comment / escalate).
- `approval_ai_assist` — AI assistance records (sort / classify /
  summarize / risk_scan).

Crucially for iOS: **the "我提交的" read path is fully accessible under
existing SELECT RLS** with a plain user-JWT. No admin-client bypass
needed, no new RPC needed. This mirrors how Projects works today.

## iOS sprint split

Roman-numeral = sprint, letter = subtask.

### Sprint 4.1 — Foundation READ (in progress, this commit)

**Goal:** users can open the iOS Approvals screen and see their own
submissions. No writes, no approver queue, no detail dialog. This is
deliberately the minimum user-observable product — mirrors the way
Projects Sprint 1.3 introduced a read-only list before any detail /
filter / edit work.

**Scope:**
- Domain types for `ApprovalRequest` + `LeaveRequestDetail` + enums
  (`ApprovalRequestType`, `ApprovalStatus`, `RequestPriority`, `LeaveType`).
  Attendance / reimbursement / procurement detail types are NOT added
  in 4.1 because "我提交的" tab only surfaces leave fields in its row
  preview (Web `my-submissions.tsx:145-151`).
- `ApprovalsViewModel.listMySubmissions()` — single PostgREST query
  replicating `src/lib/actions/approval-requests.ts:555-621 listMySubmissions`.
  Uses `approval_requests.select("..., approval_request_leave(...)")` +
  `.eq("requester_id", currentUserId)` + `.order("created_at", DESC)` +
  `.limit(100)`.
- `ApprovalsListView` — NavigationStack with `List` of submission rows.
  Row renders: type label + status chip + created timestamp + leave date
  range + business reason preview + reviewer note (if present). Empty
  state + loading state + `.zyErrorBanner`.
- Entry point — navigation wiring TBD in Task E; likely a Dashboard row
  or tab. Mirror whatever Chat did (ChatListView is surfaced via
  `DashboardView` action item / navigation — to be confirmed).

**Out of scope (explicit carry-forward to 4.2+):**
- Approve / reject / withdraw buttons (all write paths).
- Approver queue (5 sub-tabs: leave / field_work / business_trip /
  expense / report / generic). Requires capability-based filter + badge
  counts + queue-level sort. ~700 lines on Web.
- Submission forms (leave / reimbursement / procurement). Requires
  conditional field schemas + quota lookup + `shouldAutoApprove` check.
  ~400 lines on Web.
- Detail dialog (approval-detail-dialog.tsx 615 lines). Shows full
  request + audit log + AI assist + approver actions.
- Revoke comp-time self-service (revoke-comp-time-dialog.tsx 119
  lines). Depends on detail-dialog rendering.
- Push notifications for status changes. Not implemented on Web either
  (pending notification-provider generalization).

### Sprint 4.2 — Detail + self-service write paths (next)

Detail screen of a single submission: full field dump including
leave/reimbursement/procurement details, audit log rows
(`approval_actions`), and the **revoke-comp-time** self-service
affordance gated by Web parity conditions (`request_type='leave'` AND
`leave_type='comp_time'` AND `status='approved'` AND `start_date >
today()`). Still no approve/reject (that's 4.3).

### Sprint 4.3 — Approver queues + approve/reject write path

The 6 pending-tab views + approve / reject with comment via
`approveWithAudit` / `rejectWithAudit`. Pulls in the capability system
(`lib/capabilities.ts`) and the RBAC-based tab visibility.

Open question for user review before starting 4.3: the Web approver
eligibility depends on `getEffectiveCapabilities` which combines role
defaults + explicit per-user `capabilities` array + `excluded_capabilities`
array. iOS `RBACManager` has a simpler `PrimaryRole` enum that doesn't
surface excluded-capabilities. Do we:
- (A) mirror the Web capability merger into iOS (more fidelity, more
  code),
- (B) read the user's `capabilities` + `excluded_capabilities` columns
  at runtime via a profiles query (same as Web), or
- (C) add a SECURITY DEFINER RPC `approvals_my_eligible_types(user_id)`
  that returns the list of request types the caller can approve (cleanest
  separation, DB is source of truth)?

Recommendation (not blocking 4.1): **C**. Same pattern as chat RPCs.
But do not decide until 4.3 scope is actually opened.

### Sprint 4.4 — Submission forms

`SubmitLeaveRequest` / `SubmitReimbursementRequest` / `SubmitProcurementRequest`
via the same `insert(approval_requests) → insert(detail)` pattern the
Web server actions use. Includes the `shouldAutoApprove` deadlock
bypass check (`routing.ts:147-154`) so leave requests from users with
no eligible approvers auto-approve at submission time.

## 1:1 parity notes worth recording

- **Status vocabulary**: Web types file lists `draft / pending /
  approved / rejected / withdrawn / needs_revision` (types.ts:15-21),
  but `my-submissions.tsx:24-30` only surfaces 5 chip labels: pending /
  approved / rejected / cancelled / revoked. `draft` and `needs_revision`
  never render on this tab. `cancelled` and `revoked` are surfaced as
  terminal states from the self-service revoke flow (Track B Phase 2 §5).
  iOS 4.1 will mirror the narrower `my-submissions.tsx` vocabulary, not
  the broader types.ts vocabulary, because that's what the view
  actually shows.

- **`approval_request_leave` nested select**: Web uses `approval_request_leave
  ( leave_type, start_date, end_date, days )` and handles the response
  shape being either a single object or an array (PostgREST returns an
  array when there are multiple matching rows, but the schema is 1:1 on
  `request_id` so it should be a single object — Web defensively
  handles both). iOS will decode into `[LeaveRequestDetail]` and take
  `.first`; simpler than a union decoder and matches Web's effective
  behavior.

- **Auto-approve notice**: Web's `reviewer_note` can be
  `'无可用审批人,系统自动通过'` when the request was auto-approved for
  lack of eligible approvers (`routing.ts:165`). iOS 4.1 will surface
  this string verbatim in the reviewer-note row — no special rendering,
  same tint as any other reviewer note. This is honest because (a) it
  IS the note the user sees, (b) special-casing it would require
  parsing reviewer_note which is a brittle contract.

## Architecture decisions for 4.1

- **No admin-client mirroring.** Web uses `createAdminClient()` in
  `listMySubmissions` purely because the server action runs outside a
  request-bound client; there's no security reason. iOS uses user-JWT
  which satisfies `USING (auth.uid() = requester_id)` directly.
- **ViewModel name: `MySubmissionsViewModel`**, not `ApprovalsViewModel`.
  Approvals is the module; "my submissions" is the specific screen this
  sprint delivers. 4.3's approver queue will get its own viewmodel
  (`ApprovalQueueViewModel`). Easier to evolve than one god-object.
- **Model package: `Core/Models/ApprovalModel.swift`** — single file
  containing all 4.1-scope enums + structs, same pattern as
  `ChatModel.swift`. Detail types for reimbursement / procurement added
  later into the same file when their sprints open, not speculatively
  now.
- **Navigation entry**: TBD in task E. Will check `DashboardView.swift`
  and mirror Chat's wiring.

## Unchecked assumptions (call out on read)

1. **`approval_request_leave` is the only detail table surfaced by
   `my-submissions` row-preview.** Web code reads only leave fields in
   the row template (`my-submissions.tsx:145-151`). Reimbursement /
   procurement rows would just show the type label + business_reason
   without preview fields. If product says "actually we want expense
   amount in the row too," this doc is wrong and the Sprint 4.1 view
   needs a second nested select. Low-risk assumption because it's
   explicit in current Web code.
2. **Existing RLS is correct.** Migration `020` SELECT policies were
   added before the current era and have not been re-audited for the
   same three-way-union tightening that chat got. If a follow-up audit
   finds that `approval_requests` SELECT leaks to unauthorized users,
   that's a debt-05-style cross-stack sprint separate from this port.

## Deferred testing

Per standing directive ("先做 1:1 Web→iOS 移植 + iOS 前端，Docker/staging/
Winston 测试批量放到最后；Web 端生产可用兜底"), Sprint 4.1 does
**not** include Winston audit, staging smoke, or automated tests. All
test work for the Approvals module is batched to the final unified
testing phase along with the Chat testing carry-over.

## Commit plan for this sprint

- (this doc, pre-commit for implementation visibility)
- `ApprovalModel.swift` + `MySubmissionsViewModel.swift` + `ApprovalsListView.swift`
  + navigation wiring → single App commit
- ledger update (`progress.md` + `task_plan.md`) → docs commit
