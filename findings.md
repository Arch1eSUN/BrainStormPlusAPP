# Findings: Sprint 3.1 (Team Chat Foundation — Read + Send + Realtime)

## 3.1 Scope

3.1 stands up the first usable Team Chat surface on iOS: channel list (filtered by
Web-parity access rules), message read (50-row ascending window), message send
(optimistic append + best-effort `chat_channels` tail update), and Realtime v2
`INSERT` subscription for live push. Web-only chat features — attachments / reactions
/ withdraw / reply threading / mentions / search / create-conversation / DM
find-or-create / AI Copilot — stay explicitly out of scope per devprompt §6 and carry
forward as debt. Nothing about RBAC, Projects, or other modules moves; this round is
localized to `Features/Chat/` + one `Core/Models/ChatModel.swift` extension.

Ground-truth reference: `BrainStorm+-Web/src/lib/actions/chat.ts` — specifically
`getAccessibleChannelMap` (lines 252-282, three-part union: announcement OR
`created_by` OR `chat_channel_members` membership) and `ensureChannelAccess`
(lines 284-305, same three-part gate per-channel). Web serves these through
`createAdminClient()` (service role, RLS-bypass); iOS holds only a user JWT and
therefore must replicate the access gate client-side because `chat_channels` /
`chat_messages` SELECT RLS is `USING (true)`. This is the 3.1 round's central
architectural decision.

## 3.1 Deltas / What Landed

| File | Change | Key behavior |
|---|---|---|
| `Brainstorm+/Core/Models/ChatModel.swift` | Added `ChatChannelMember` struct + nested `MemberRole` enum (`owner` / `admin` / `member`) | Decodes `chat_channel_members` rows with `channel_id` / `user_id` / `joined_at` snake-case mapping; used by both viewmodels for membership lookups. `ChatMessage` intentionally unchanged — `attachments` / `reactions` / `reply_to` still deferred per scope. |
| `Brainstorm+/Features/Chat/ChatListViewModel.swift` | Rewritten: three-part client-side union mirroring `getAccessibleChannelMap` | Three parallel `async let` PostgREST reads (announcements by `type='announcement'`, owned by `created_by=userId`, memberships via `chat_channel_members` → channel-id resolve) → Set-based dedupe by id → sort `last_message_at DESC nulls last` with `created_at` tiebreaker. Matches Web page.tsx sort exactly. |
| `Brainstorm+/Features/Chat/ChatRoomViewModel.swift` (new) | `@MainActor ObservableObject` with 5 methods: `bootstrap` / `fetchMessages` / `sendMessage` / `subscribeRealtime` / `teardown` | Access gate (announcement OR `createdBy == userId` OR membership row present, else `accessDenied = true`) runs before any fetch/subscribe. Messages fetched `created_at ASC limit 50`. Send flow: insert → optimistic append (dedup against Realtime echo by id) → best-effort `chat_channels.last_message` / `last_message_at` UPDATE via migration 026 policy. Realtime v2 uses `postgresChange(InsertAction.self, filter: .eq("channel_id", channel.id))` with `JSONObject.decode(as:)` inheriting `JSONDecoder.supabase()` fractional-second decoding. `deinit` only cancels the task (MainActor-isolated `teardown()` is not callable from deinit); View layer must call `teardown()` from `.onDisappear`. |
| `Brainstorm+/Features/Chat/ChatRoomView.swift` | Rewritten: bound to `ChatRoomViewModel` via `@StateObject(wrappedValue:)` | `.task { await bootstrap() }` + `.onDisappear { teardown() }`; ScrollViewReader auto-scrolls on `messages.count` change; bubble `isCurrentUser` check keys off `msg.senderId == viewModel.currentUserId`; three-state UI (accessDenied / loading-empty / normal); send button disabled while `isSending || trimmed.isEmpty`; input cleared only after send returns (not optimistically). |
| `Brainstorm+/Features/Chat/ChatDateFormatter.swift` (new) | `enum ChatDateFormatter` + `static func format(_ date: Date?) -> String` | Four branches: nil → `""`, today → `HH:mm`, yesterday → `昨天 HH:mm`, this-year-earlier → `M月d日 HH:mm`, older → `yyyy年M月d日`. `zh_CN` locale, static-cached `DateFormatter` instances. Mirrors Web page.tsx inline formatter with iOS-idiomatic 中文 month/day labels. |
| `Brainstorm+/Features/Chat/ChatListView.swift` | Patched: NavigationLink destination + list-cell date | NavigationLink now constructs `ChatRoomView(viewModel: ChatRoomViewModel(client: supabase, channel: channel))`; `Text(date, style: .time)` replaced with `Text(ChatDateFormatter.format(channel.lastMessageAt))`. No new FAB / search / unread-badge surfaces. |

## 3.1 Web Parity Mapping

| Behavior | Web source | iOS after 3.1 | Parity |
|---|---|---|---|
| Accessible channel set | `getAccessibleChannelMap` (chat.ts:252-282) — admin-client three-query union server-side | Three `async let` user-JWT queries unioned + dedup + sort client-side | Parity (equivalent set; different trust boundary) |
| Per-channel access gate | `ensureChannelAccess` (chat.ts:284-305) — server-action gate before fetch | `ChatRoomViewModel.bootstrap` three-branch check before fetch/subscribe; `accessDenied` rail isolates UI | Parity |
| Message read | `fetchMessages(channelId, limit=50)` (chat.ts:539-576) — `created_at ASC` | `eq("channel_id")` + `order("created_at", ascending: true)` + `limit(50)` | Parity |
| Message send | `sendMessage` (chat.ts:592-660) — insert → UPDATE `chat_channels.last_message` / `last_message_at` | Identical — insert returns row, optimistic append, best-effort UPDATE swallowed on failure | Parity |
| Realtime push | `use-realtime.ts` (79 lines) — `postgres_changes` + `channel_id=eq.${id}` filter | Supabase Swift SDK v2 `postgresChange(InsertAction.self, filter: .eq(...))` + dedup by id against optimistic append | Parity |
| Sort | `last_message_at DESC nulls last`, `created_at` tiebreaker | Identical sort in `ChatListViewModel.fetchChannels` | Parity |
| `last_message` tail update | UPDATE via migration 026 policy `auth.uid() IS NOT NULL` | Same — best-effort `.update(...)` post-insert | Parity |
| Date formatting | Inline formatter (today / 昨天 / M/D HH:MM) | `ChatDateFormatter` (nil / today / 昨天 / 本年 / 跨年) | Parity-plus (nil + cross-year branches iOS-only) |
| Announcement "admin-only send" | `page.tsx` input-bar `canCreate` gate | Not implemented — input always visible | Deferred (debt 3.1-debt-04 via devprompt §5.5) |

## 3.1 Debt Carry-Forward (summary — details in Winston ready-notes)

Five items carry forward into the next chat sprint. Full diagnosis lives in
`docs/parity/52-winston-ready-3.1-notes.md` (authored under Task G); summary here:

- **3.1-debt-01 Attachments / images / files — ✅ CLOSED (image + file subset)
  2026-04-21** via Sprint 3.3 (App commit `93ad38f`):
  - `ChatMessage` extended with `attachments: [ChatAttachment]` field +
    null-tolerant custom decoder (missing / null → `[]`, matches Web's
    `normalizeAttachments` fallback). New `ChatAttachment: Codable, Hashable
    { name, url, type (MIME), size: Int? }` + `isImage` computed property.
  - `ChatRoomViewModel.sendMessage` now accepts `attachments: [ChatAttachment]
    = []`, drops the empty-text guard (attachments-only sends allowed like Web),
    derives message `type` via `attachments.isEmpty ? "text" :
    (allSatisfy({ $0.isImage }) ? "image" : "file")` — 1:1 with
    `chat.ts:595-597`. `last_message` preview mirrors Web: text if present,
    else `"[图片]"` / `"[文件]"`.
  - New `ChatRoomViewModel.uploadAttachment(data:fileName:mimeType:)` writes
    to bucket `chat-files` at path `{user_id}/{channel_id}/{uuid}.{ext}` via
    user-JWT (first segment satisfies existing storage RLS policy from
    migration 028 without needing admin client). Returns `ChatAttachment`
    with `getPublicURL(path:).absoluteString` — public bucket so no
    signed-URL TTL. Chose this over calling Web's `/api/chat/upload` route
    (would add Web-uptime dependency) or SECURITY DEFINER RPC (unnecessary
    for storage-level auth).
  - `ChatRoomView` + button replaced with `Menu` wrapping `PhotosPicker`
    (images, max 9) + `Button → .fileImporter(allowedContentTypes: [.item])`.
    Photos handled via `PhotosPickerItem.loadTransferable(type: Data.self)`
    → `"IMG_<uuid>.jpg"` + `"image/jpeg"` MIME. Files handled via
    `startAccessingSecurityScopedResource()` + `Data(contentsOf:)` +
    `UTType(filenameExtension:)?.preferredMIMEType`. Pending strip above
    input bar shows 64×64 thumbnails (UIImage for images, `doc.fill` + name
    for files) with remove chip. `sendTapped` awaits each upload
    sequentially then calls `sendMessage(text, attachments:)`; upload
    failure surfaces via `errorMessage` banner without consuming state.
  - `messageBubble` grows: `msg.isWithdrawn` → italic gray "此消息已撤回"
    bubble with no attachments rendered (Web parity); else text bubble
    skipped when content empty (no empty bubble over attachments-only
    messages) + `ForEach(attachments)` renders `AsyncImage` 200×200 rounded
    for images or `doc.fill + filename` row for files, both wrapped in
    `Link(destination: URL)` for tap-to-open (Safari / system quick-look).
  - **Note — Web bucket truth**: `page.tsx:288` references bucket
    `'chat_attachments'` but that bucket doesn't exist in any migration;
    the production upload path is `/api/chat/upload` (route.ts:9) which
    uses `'chat-files'`. The `page.tsx:288` client-direct-upload branch is
    dead Web code. iOS aligns with the actual bucket `chat-files`.
  - **Explicitly deferred (3.3-followup)**: (1) image compression before
    upload (Web uploads raw too), (2) signed-URL reads (bucket is public),
    (3) upload progress bar (Web has spinner only), (4) multi-image gallery
    modal on tap (Web opens in new tab — parity), (5) file quick-look
    preview inline (parity: browser / OS delegation), (6) attachment size
    / extension enforcement (no server-side enforcement on Web either),
    (7) Winston 3.3 audit + iOS staging smoke batched to unified testing
    phase per standing directive.
- **3.1-debt-02 Message withdraw**: `is_withdrawn` / `withdrawn_at` fields exist on the
  model but no UI trigger path and no server-side RLS UPDATE test. Web has the flow; iOS
  lags.
- **3.1-debt-03 Reply threading**: `reply_to: UUID?` present on the model but not
  consumed at render. Web's `fetchMessages` does a reply-to second query (chat.ts:160
  `normalizeMessage`); iOS deliberately skips per devprompt §6 scope exclusion. 3.2+
  scope.
- **3.1-debt-04 Mentions / search / create-conversation / find-or-create-DM**:
  - **create-conversation + find-or-create-DM CLOSED (Sprint 3.2, 2026-04-21)**: two
    SECURITY DEFINER RPCs landed on Web
    (`20260421130000_chat_conversation_rpc.sql` — `chat_find_or_create_direct_channel`
    + `chat_create_group_channel`, commit `08bce19`). iOS wires them through new
    `ChatListViewModel.findOrCreateDirectChannel` / `createGroupChannel` plus new
    `UserPickerView` + `NewConversationSheet` + `ChatListView` toolbar `+` entry
    (commit `7143142`). Race-safety preserved via pre-existing partial unique index
    on `chat_channels(participant_pair_key) WHERE type='direct'` — INSERT loser
    catches `unique_violation` and re-SELECTs. Validation mirrors Web (auth required,
    self-DM rejected, empty group name rejected, zero-member/self-only rejected,
    dedup). Verified via 9-assertion native-PG harness (`/tmp/chat_rpc_test.sh`).
  - **Remaining**: `@mentions` (Web parses `content.includes('@<name>')` naive regex
    + writes to `chat_mentions`; iOS sends plain text only) and message search (Web
    `ilike` on `content`) still deferred. Future sprint.
- **3.1-debt-05 Web RLS tightening (system-level security debt)**:
  Sprint 3.2a IN PROGRESS under repeated "你自己决定" delegation. Context: Web
  `chat_channels` / `chat_messages` SELECT RLS was `USING (true)` because Web uses
  `createAdminClient()` server-side to bypass RLS and apply access control in server
  actions. iOS cannot reuse that posture with a user JWT, so 3.1 replicated access
  gating client-side (`getAccessibleChannelMap` / `ensureChannelAccess`). The
  client-side gate only shapes rendering — a forged client (jailbroken iOS, DevTools
  direct to Supabase, custom app shell) would still receive the full tables from the
  DB. Winston audit of 3.1 flagged as real security debt.
  - **Task A ✅** migration authored:
    `BrainStorm+-Web/supabase/migrations/20260421000000_chat_rls_tightening.sql`.
    DROPs `"Anyone can view channels"` / `"Users can view messages"`, CREATEs
    `chat_channels_select_membership` (announcement ∪ owned ∪ member-of) +
    `chat_messages_select_membership` (containing-channel visibility via `EXISTS`).
    Mirrors Web `chat.ts:252-282` so DB predicate is textually equivalent to the
    application-layer one.
  - **Task B ✅** Web read-path regression audit:
    `docs/parity/54-3.2a-task-b-web-regression-audit.md`. 23 admin-client reads in
    `src/lib/actions/chat.ts` unaffected (service_role bypass). 2 user-role Realtime
    reads: chat page subscription is channel-filtered → RLS-compatible; global
    `@mention` listener narrows to member-channels → strict UX improvement (no more
    dead-link notifications for non-member channels). Zero pre-migration code
    changes required.
  - **Task C1 ✅ (native-PG approximation)**: Docker daemon unavailable for
    `supabase start`. Verified via native Postgres 15 + `auth.uid()` stub (session
    GUC `request.jwt.claim.sub`) in `/tmp/chat_rls_test.sh`. Four-user scenario
    matrix (DM member A, DM member B, C-team owner C, stranger D) all green;
    stranger sees only the announcement channel with 0 non-announcement leakage.
    Evidence: `docs/parity/55-3.2a-task-c1-local-verification.md`. Full-stack
    verification (PostgREST + Realtime + GoTrue) deferred to Docker-available run
    or folds into C3 staging shadow.
  - **Remaining**: C2 (iOS staging smoke), C3 (staging shadow ≥24h), Task D (D1
    annotate iOS client gate vs D2 aggressive collapse), Winston 3.2a re-audit.
  - **Related follow-ups**: debt-10 (membership row leak via
    `chat_channel_members` SELECT = `auth.uid() IS NOT NULL`) — precondition for
    the new `EXISTS` subqueries; tightening requires SECURITY DEFINER or redesign;
    tracked separately. Notification provider naive `content.includes('@<name>')`
    mention detection — structured mention handling in a future sprint.
- **3.1-debt-06 Realtime connection failure visibility — ✅ CLOSED** in closeout pass.
  `ChatRoomViewModel` writes `errorMessage` on `subscribeWithError()` throw (commit
  `06b7f99`); `ChatRoomView` now surfaces it via shared
  `.zyErrorBanner($viewModel.errorMessage)` modifier
  (`Shared/DesignSystem/Modifiers/ZYErrorBannerModifier.swift`).
- **3.1-debt-07 Chat error surfacing — ✅ CLOSED** in closeout pass. Same shared
  `ZYErrorBannerModifier` attached to both `ChatRoomView` and `ChatListView`; fetch,
  send, and list-load failures now render as a top-aligned red banner with 5s
  auto-dismiss + manual close. Realtime subscribe failures (debt-06) ride the same
  channel so one UI primitive closes both.
- **3.1-debt-08 Nav-destination laziness**: `ChatListView` NavigationLink eagerly
  constructs `ChatRoomViewModel` for every list row. Cheap init so no runtime impact,
  but wasted allocation. Fix is value-based nav (`NavigationLink(value:)` +
  `.navigationDestination(for:)`).
- **3.1-debt-09 Mock-Supabase testability harness**: zero automated coverage on chat
  viewmodels (access-gate union, empty-result handling, decode failure, send failure,
  realtime decode/subscribe failure) — all manual-only. Blocker is `SupabaseClient` /
  `PostgrestQueryBuilder` / `RealtimeChannelV2` have no protocol seam for fakes.
  Originally folded into debt-05 in the ready-notes draft; split out here so
  "add tests" stops coupling to "tighten RLS." Revisit first sprint that either adds
  a non-trivial chat codepath or budgets a dedicated testability pass; introduce a
  minimal `ChatDataSource` protocol in `Core/Services/` with fake implementation.

## 3.1 Verification

- Build: `xcodebuild build` with Debug + iOS Simulator destination +
  `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` → `** BUILD SUCCEEDED **`.
- Commits on `main` (note: Task D subagent committed first; Task A/B/C were filled in
  afterward by the controller — chronological landing order A → B/C → D as recorded
  below):
  - `fdaf782` docs(devprompt): add sprint 3.1 team chat foundation plan
  - `0e6e456` feat(chat): add ChatChannelMember model for membership access checks
    (Task A)
  - `f591231` feat(chat): replicate web access gate and realtime stream in chat
    viewmodels (Tasks B + C)
  - `7b0b135` feat(chat): bind ChatRoomView to ChatRoomViewModel with realtime
    teardown (Tasks D + E)
- Module status: `Features/Chat/` promoted from "3 placeholder files with blind
  SELECT / empty send / no VM" to "read + send + realtime-live foundation with
  client-side access gate". Still `.partial` on `AppModule.chat` until the 5 debt
  items land.

---

# Findings: Sprint 2.6 (Projects Risk Action Sync Write Path Foundation)

## 2.6 Scope

2.6 introduces the **first iOS write path** for the Projects module by mirroring Web's
"转为风险动作" / `syncRiskFromDetection` flow. Minimum surface: one RBAC-gated "Convert
to risk action" button inside `riskAnalysisSection`, a confirmation dialog that previews
the exact payload, a direct Supabase `risk_actions` INSERT (Path A) under client-side
role gating, a best-effort `risk_action_events` audit log (Web parity), and a post-write
fire-and-forget refresh of `linkedRiskActions` + `resolutionFeedback`.

Everything else from 2.0–2.5.1 (list, filter, detail gate, enrichment, AI summary,
risk analysis, linked actions read, resolution feedback read) is unchanged. Still out
of scope: resolution write-back (close / reopen / effectiveness / governance note),
generate-risk-analysis-from-iOS, LLM narrative on AI summary, full risk-action
management module, bulk convert, assignee picker, due-date picker, i18n refactor,
visual redesign, migrations, RLS changes, Web code changes. `.projects` stays `.partial`.

Path A was chosen after an explicit feasibility audit (see §Path Decision below). No
source-of-truth discrepancy on the primary insert: every column in the `risk_actions`
row is UI-supplied or auth-derived, with zero server-only enrichment required.

## 2.6 Path Decision (Path A vs Path B)

Devprompt §2 required an explicit feasibility decision before any code. Audit result:

- `syncRiskFromDetection` is a thin wrapper around `createRiskAction`. Column
  population is deterministic: `org_id` (derivable from `profiles.org_id` via the
  current `auth.uid`), `risk_type: "manual"`, `source_type: "project"`, `source_id`
  (current project id), `ai_source_id` (one extra `project_risk_summaries.id`
  lookup keyed by `project_id`), `title` (template string
  `"[\(project.name)] 风险项"`), `detail` (first 200 chars of the current risk
  analysis summary — Web does the same slice), `severity` (pre-mapped from
  `RiskLevel`), `suggested_action: "从项目风险分析生成"`, `status: "open"`,
  `created_by: user.id`.
- No `askAI()` call. No `decryptApiKey()` call. No `api_keys` access. No `risk_items`
  JSONB parsing required (Web's sync flow does not populate it either).
- RLS on `risk_actions.INSERT` gates the role set `['super_admin', 'admin', 'hr_admin',
  'manager']`; iOS mirrors the same set client-side via raw-string check (see §RBAC
  Divergence).
- No unique constraint for duplicate prevention on Web either — iOS mirrors Web's
  "user sees a success flash; a second tap creates a second row" posture. Not a bug.

**Decision: Path A (direct Supabase write) is safe and feasible.** Path B (blocked
foundation) ruled out.

## 2.6 RBAC Divergence (Important)

Devprompt §3.A banned "relying on RLS post-error as the sole UX". Audit of
`Brainstorm+/Shared/Security/RBACManager.swift` `migrateLegacyRole(_:)`:

- `super_admin → .superadmin` ✓
- `admin | manager | team_lead → .admin` — `team_lead` is a FALSE POSITIVE against
  Web's role set.
- `chairperson → .chairperson` — distinct tier, FALSE POSITIVE against Web's
  `manager`-or-above set (Web allows chairperson via separate higher-tier helpers, not
  via the `manager` check `syncRiskFromDetection` uses).
- `hr_admin` is UNMAPPED and falls through to `.employee` — FALSE NEGATIVE against
  Web's role set (iOS would lock `hr_admin` out of sync even though Web allows it).

Solution: `ProjectDetailViewModel.canSyncRiskAction(role: String?)` checks the raw
profile role string lower-cased against
`syncEnabledRoles: Set<String> = {"super_admin", "admin", "hr_admin", "manager"}` —
Web's exact role set, verbatim. Deliberate iOS divergence from the `PrimaryRole` enum;
kept narrow to this one gate so unrelated iOS helpers don't drift.

## 2.6 Persistence Parity

`title` and `suggested_action` hit the `risk_actions` table as-typed and get surfaced
by Web later. To keep rows written from iOS visually identical to Web-written rows:

- `title`: `"[\(project.name)] 风险项"` — Chinese `风险项` suffix persisted exactly as
  Web writes it (dashboard page.tsx:688).
- `suggested_action`: `"从项目风险分析生成"` — Chinese hard-coded value persisted exactly
  as Web writes it (page.tsx:212).

UI dialog copy (English) is separate from these persisted literals. iOS i18n is
carry-forward debt; the persisted strings are a data-integrity concern, not a UI one.

## 2.6 Parity Checklist

| Dimension | Web behavior | iOS after 2.6 | Parity |
|---|---|---|---|
| Client-side RBAC pre-gate | Absent (RLS post-error only) | Raw-string check against Web's exact role set; button is disabled + hint rendered when gate fails | iOS stronger — parity-plus |
| Confirmation affordance | Absent (one-click) | `.confirmationDialog` with title / severity / detail preview | iOS stronger — parity-plus |
| Primary insert columns | `risk_actions` with 11 columns | Identical 11-column Encodable DTO with snake_case CodingKeys | Parity |
| Hard-coded `risk_type` | `'manual'` | `"manual"` | Parity |
| Hard-coded `source_type` | `'project'` | `"project"` | Parity |
| Hard-coded `status` | `'open'` | `"open"` | Parity |
| Hard-coded `suggested_action` | `'从项目风险分析生成'` | `"从项目风险分析生成"` | Parity |
| `title` template | `` `[${detail.name}] 风险项` `` | `"[\(project.name)] 风险项"` | Parity |
| `detail` slice | `riskSummary.slice(0, 200)` (UTF-16 code units) | `String(analysis.summary.prefix(200))` (grapheme clusters) | Parity (cluster-safe slice — only differs on emoji / combining marks) |
| Severity mapping | critical/high → high; medium → medium; low → low | Same + `.unknown → "medium"` branch | Parity (iOS adds defensive fallback Web never reaches) |
| Title trim-and-reject | `title.trim()` empty reject | `trimmingCharacters(.whitespacesAndNewlines)` empty reject | Parity |
| `org_id` resolution | `profiles.select('org_id').eq('id', user.id).single()` | Identical PostgREST call via `ProfileOrgRow` DTO | Parity |
| Anchor (`ai_source_id`) re-fetch | Caller passes `riskSummaryId` state | iOS re-fetches anchor inside the write method | iOS slightly heavier (+1 round-trip) but self-contained |
| Best-effort audit log | `logRiskEvent` silent-swallow wrapper | Inline `do/catch` silent-swallow on `risk_action_events` insert | Parity |
| Post-write refresh | `await getLinkedRiskActions(detail.id)` | Fire-and-forget `Task { refreshLinkedRiskActions() }` + `Task { refreshResolutionFeedback() }` | Parity-plus (iOS also refreshes resolution feedback; Web only refreshes linked actions) |
| 3-second success auto-clear | `setTimeout(() => setSyncMsg(null), 3000)` | `Task.sleep` + VM `clearRiskActionSyncSuccess()` guarded against stomping a newer in-flight sync | Parity |
| Error isolation | Shared `syncMsg` string | Dedicated `riskActionSyncErrorMessage` separate from every other error rail | iOS stronger — parity-plus |
| Phase modeling | In-flight / done / hidden via `syncMsg` content | Explicit `RiskActionSyncPhase { idle, syncing, succeeded }` + side-band error | Parity-plus |
| `lastSyncedRiskActionId` tracking | Absent (Web doesn't need it) | Published `UUID?` for future rounds to target the new row | iOS extension (parity-neutral) |
| `.projects` parity | — | `.partial` (unchanged) | Parity (no virtual promotion) |

## 2.6 Debt Carry-Forward (updated)

- ~~**Audit doc error to correct in 2.7 (or 2.6.1)**: `49-winston-ready-2.6-notes.md`
  references `BrainStorm+-Web/src/lib/security/rbac.ts` — that file does not exist; real
  path is `src/lib/rbac.ts`. Same doc claims `serverGuard({requiredRole:'manager'})`
  resolves to `{super_admin, admin, hr_admin, manager}` — **false**: `ROLE_LEVEL` has no
  `hr_admin`, and level≥2 resolves to `{manager, team_lead, admin, super_admin,
  superadmin, chairperson}`. iOS's whitelist actually mirrors **DB RLS policies
  (migrations 014 / 037)**, strictly narrower than Web server guard. The code is safe
  (RLS is ground truth for writes), but the narrative must be corrected before 2.7
  reuses it as reference. Full analysis: `docs/parity/50-winston-audit-2.6.md` §8.~~
  **Closed in Sprint 3.0 Task H**: `49-winston-ready-2.6-notes.md` §2.3 / §2.4 rewritten
  against re-read Web sources — path corrected to `src/lib/rbac.ts` and the server-guard
  role set now reads the actual 6-role set (manager / team_lead / admin / super_admin /
  superadmin / chairperson at level ≥ 2). iOS 4-role whitelist is re-contextualized as a
  DB-RLS mirror, intentionally narrower than server guard.
- ~~**RBAC unification debt for 2.7**: fold `canSyncRiskAction` + any new
  `canUpdateRiskAction` into `RBACManager.canManageRiskActions(profile:)` routed through
  `PrimaryRole` + capability lookup — retires the raw-string whitelist shortcut 2.6
  took (which was correct given `migrateLegacyRole` drops `hr_admin`, but is no longer
  necessary once the helper is added).~~ **Closed in Sprint 3.0 Task G**:
  `RBACManager.canManageRiskActions(rawRole:)` + `canManageRiskActions(profile:)` added
  (DB-RLS-mirror raw-string whitelist owned by the shared manager, not Projects-local).
  `ProjectDetailViewModel.canSyncRiskAction` + `syncEnabledRoles` deleted; all call
  sites now route through `RBACManager.shared.canManageRiskActions(...)`. Did not route
  through `PrimaryRole` lookup because `migrateLegacyRole` deliberately drops `hr_admin`
  (which DB RLS accepts) — raw-string remains the right shape for THIS particular gate.
- **Resolution write-back** (close / reopen / effectiveness / governance note): still
  absent on iOS. Write gated to `['super_admin', 'admin', 'hr_admin', 'manager']` via
  the same RLS that 2.6 passes — the gate is ready; the UI / VM are not.
- ~~**"转为风险动作" sync from iOS** (`syncRiskFromDetection`): still deferred (carry-over
  from 2.4).~~ **Delivered in 2.6** with RBAC gate + confirmation + post-write refresh.
- **Governance intervention write**: still absent on iOS.
- **Generate risk analysis from iOS** (2.3 carry-over): still deferred. Requires Web
  to expose `/api/ai/project-risk`.
- **LLM-generated narrative on AI summary** (2.2 carry-over): still deferred behind
  Web-side `/api/ai/project-summary`.
- **Auto-fetch on detail load**: iOS still gates resolution-feedback and linked-actions
  and risk-analysis reads behind explicit button taps; Web auto-fetches. Foundation
  divergence.
- **`total` caps at 50**: matches Web's contract. Not a bug.
- **Source-of-truth divergence on task count** (2.1): iOS list card shows task count;
  Web does not. Still open on the Web side.
- **`risk_items` JSONB**: neither iOS nor Web sync populates it. Belongs with a later
  surface (grouping resolutions by risk item).
- **Duplicate prevention**: no unique constraint; no pre-check. Mirrors Web exactly.
- **Palette debt**: `Color.Brand.warning` chosen for the sync capsule because it
  sits adjacent to risk-level capsules and needs to read as "write"; critical risk /
  high severity / reopened-count debt from 2.3–2.5 unchanged.
- **RLS trust** on `risk_actions.INSERT`: iOS pre-gates via the raw-string role set and
  relies on server-side RLS as a second line. Matches every other write in this module.
- **Locale-aware copy** on "Convert to risk action" / "Converting…" / "Risk action
  created and linked to this analysis." / "Converting a risk into a risk action
  requires admin or manager privileges." / dialog prompt / confirm / cancel: English-
  only. Belongs with broader iOS i18n (carry-over).
- **Swift Anchor re-fetch cost**: 2.6 adds one extra `project_risk_summaries.id` lookup
  per write. Cheap, self-contained, keeps the method independent of prior state.
- Client-side `filteredProjects`, client-side `AccessOutcome` role normalization,
  batched `.in("id", values: ids)` hydrate, `AsyncImage` cache not persistent, date-only
  `String` fields, `maybeSingle()` absent from Swift SDK — all unchanged carry-overs
  from 1.5–2.5.1.

---

# Findings: Sprint 2.5.1 (Resolution Feedback Governance Priority Fix)

## Scope

2.5.1 is a **minimum fix round** against Winston 2.5 FAIL. Only the `governanceSignal`
priority was inverted to match Web's **effective-first** logic, and the prone-to-reopen
subline was unbound from the governance tint so the two rails stay semantically distinct.
Everything else in 2.5 (two-step read, aggregation, counts, state machine, debt list,
state isolation) remains as landed. `.projects` stays `.partial`. All non-priority scope
expansions (write-back, auto-fetch, i18n, risk action management, UI redesign) are
explicitly forbidden by the 2.5.1 prompt.

The 2.5 retrospective below is retained verbatim beneath the **Scope** section so the
historical finding-set stays readable.

## 2.5.1 Fix

- **Source of truth**: `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` lines 780-796.
  Web short-circuits on `hasEffective` first; only when `hasEffective` is false does it
  check `needsIntervention`.
- **iOS 2.5 error**: `ProjectResolutionFeedback.governanceSignal` evaluated `needs` first
  and returned `.needsIntervention` when both conditions fired, inverting Web's priority.
- **Fix**: `ProjectDetailModels.swift` now evaluates `effective` first; only when
  `effective` is false does it consider `needs`.
- **Predictive "易重开" is unchanged**: `isProneToReopen` still = `reopenedCount > 0 && active > 0`,
  rendered as an independent subline inside the banner.
- **Visual semantic separation**: the subline tint switched from `tint.opacity(0.9)` to
  `Color.Brand.warning` so a green `Intervention effective` banner does not drag the
  warning-semantic subline into a calm primary hue.
- **Ledger**: all prior occurrences of "danger trumps success" / "needsIntervention wins
  priority when both fire" were rewritten to say "effective-first (matches Web)" and
  record the prone-to-reopen indicator as an independent rail.
- **No other code paths changed**.
- **Debt carry-forward updated**: the "Governance priority when both signals fire"
  divergence line in the Debt list no longer exists because the divergence itself is
  gone — see Verification for the post-fix scan.

## 2.5 Scope (retained verbatim)

This round closes the next narrow Projects detail-surface gap flagged by Winston 2.4 audit:

1. **No resolution feedback surface on iOS** — 1.3 through 2.4 shipped Projects list + scoping + detail gate + owner join + avatar + edit + member + delete + task-count-on-list + AI-summary-foundation + risk-analysis-foundation + linked-risk-actions-foundation without ever surfacing the resolution aggregation that Web calls out in its risk card (counts, governance signal, predictive "易重开" badge, dominant category, recent resolutions). Web renders this block at `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` lines 725-838 and sources it from `getProjectRiskResolutionSummary(projectId)` at `BrainStorm+-Web/src/lib/actions/summary-actions.ts` lines 630-714.
2. **Web's `getProjectRiskResolutionSummary(projectId)` is a server action, but the underlying aggregation is entirely client-side over a single PostgREST read** — unlike `generateProjectRiskAnalysis` (LLM-bound) and `generateProjectSummary` (LLM-bound), it makes no `askAI()` call and does not decrypt any `api_keys`. Native iOS can faithfully replicate both the anchor lookup and the filtered select, then run the same counting / tie-break / top-3 slice in Swift.

2.5 is still foundation-scope. It does NOT touch the "转为风险动作" sync write path (`syncRiskFromDetection`), generate-risk-from-iOS, AI summary LLM swap, resolution write-back (closing / reopening / adding governance notes), schema, RLS, long-term persistence, streaming, or prompt engineering backend. `.projects` remains `.partial`.

## Winston 2.5 Audit + Next Prompt

- Winston 2.4 audit completed and passed: `docs/parity/44-winston-audit-2.4.md`.
- 2.5 prompt created: `devprompt/2.5-projects-resolution-feedback-foundation.md`.
- Winston 2.5 audit completed: `docs/parity/46-winston-audit-2.5.md` — **FAIL**.
- Blocking finding: Web governance intervention status is `hasEffective`-first, but iOS 2.5 made `.needsIntervention` win when both signals fire. This is a source-of-truth parity error, not a build error.
- Winston 2.5.1 audit completed and passed: `docs/parity/48-winston-audit-2.5.1.md`.
- Next prompt created: `devprompt/2.6-projects-risk-action-sync-write-path-foundation.md`.
- 2.6 now targets the Web-only "转为风险动作" / `syncRiskFromDetection` gap, with explicit requirements for RBAC mirroring, confirmation affordance, isolated write state, and post-write refresh of linked actions + resolution feedback. If direct write is not safely feasible, 2.6 must stop at an honest blocked-foundation result rather than fake the write path.

## Web source-of-truth (explicit)

- `BrainStorm+-Web/src/lib/actions/summary-actions.ts` — `getProjectRiskResolutionSummary(projectId)` is a `'use server'` action (lines 630-714):

  ```ts
  // Step 1 — anchor
  const { data: summary } = await supabase
    .from('project_risk_summaries')
    .select('id')
    .eq('project_id', projectId)
    .maybeSingle()
  if (!summary) return { data: null, error: null }

  // Step 2 — filtered select (limit 50)
  const { data: rows } = await supabase
    .from('risk_actions')
    .select('title, status, severity, resolution_category, effectiveness,
            follow_up_required, reopen_count, resolved_at')
    .eq('ai_source_id', summary.id)
    .order('resolved_at', { ascending: false, nullsFirst: false })
    .limit(50)

  // Step 3 — client-side aggregation
  // total = rows.length
  // resolved   = count where status === 'resolved'
  // dismissed  = count where status === 'dismissed'
  // active     = count where status in {'open','acknowledged','in_progress'}
  // followUp   = count where follow_up_required === true
  // reopened   = count where (reopen_count ?? 0) > 0
  // dominantCategory = most-frequent non-nil resolution_category (ties → first-encountered)
  // recentResolutions = rows.filter({resolved|dismissed}).slice(0, 3)
  ```

  No LLM, no decryption, no server-only secrets — a pure two-step PostgREST read plus client-side aggregation.

- `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` lines 725-838 — renders the block:
  - Line 750 + 754-758: predictive pulsing rose "易重开" badge when `reopenedCount > 0 && active > 0`.
  - Lines 780-796: governance-signal badges — Web uses `hasEffective`-first priority: "干预已生效" (green) when any recent resolution is `effectiveness === 'effective'` AND `category === 'root_cause_fixed'`; only if that is false does it show "待治理干预" (red) when `reopenedCount > 0 && active > 0`. Winston 2.5 audit found iOS 2.5 incorrectly made `.needsIntervention` win; 2.5.1 must fix this.
  - Count badges: resolved / dismissed / active / followUpRequired / reopenedCount.
  - `dominantCategory` labeled via a small `category → 中文 label` map. iOS substitutes a local English `humanize(_:)` fallback since 2.5 foundation copy is English-only (i18n carry-forward debt).
  - `recentResolutions` top-3 rendered as a compact table (title + status + effectiveness + `resolved_at`).
- `BrainStorm+-Web/src/app/api/` — contains `ai/analyze`, `ai/models`, `approval/*`, `attendance/*`, `chat/*`, `auth/*`, `knowledge/*`, `mobile/*` routes but **NO `/api/risk-resolution*` HTTP route exists**. All resolution-feedback logic lives in `summary-actions.ts`.
- **Linkage table**: `risk_actions` (migration `BrainStorm+-Web/supabase/migrations/037_round8_risk_knowledge_ai.sql` + extensions `015`-`017`). Columns relevant to 2.5: `resolution_category ∈ {root_cause_fixed, workaround_applied, escalated, deferred, false_positive}`, `effectiveness ∈ {effective, partial, ineffective, pending}`, `follow_up_required BOOL DEFAULT false`, `reopen_count INT DEFAULT 0`, `resolved_at TIMESTAMPTZ`. Linkage key: `ai_source_id` FK → `project_risk_summaries.id`.
- **Implication**: iOS can replicate `getProjectRiskResolutionSummary` faithfully — **no source-of-truth discrepancy this round** (same parity posture as 2.4). The write-back flows (closing / reopening / governance notes) remain Web-only by scope, not by technical blocker.

## What 2.5 Delivered

### Files Modified

- `Brainstorm+/Features/Projects/ProjectDetailModels.swift`:
  - New public struct `ProjectResolutionFeedback: Equatable` with eight fields (`total`, `resolved`, `dismissed`, `active`, `followUpRequired`, `dominantCategory: String?`, `reopenedCount`, `recentResolutions: [RecentResolution]`) + a nested `RecentResolution: Equatable, Hashable` (`title`, `status`, `category: String?`, `effectiveness: String?`, `resolvedAtRaw: String?`) + a `GovernanceSignal: Equatable { .none, .interventionEffective, .needsIntervention }` enum.
  - Two computed properties on the feedback struct: `governanceSignal: GovernanceSignal` (mirrors Web lines 780-796 logic: `.needsIntervention` wins when `reopenedCount > 0 && active > 0`; `.interventionEffective` wins when any recent resolution has `effectiveness == "effective" && category == "root_cause_fixed"`; otherwise `.none`) and `isProneToReopen: Bool` (true when `reopenedCount > 0 && active > 0`).
  - Doc comment records Web source-of-truth (file path + line ranges 630-714 and 725-838) + client-side aggregation pattern + `total` capping at 50 matching Web exactly (not a bug) + no source-of-truth discrepancy posture + `resolvedAtRaw` kept as `String?` so both `timestamptz` formats decode safely + governance priority resolution.

- `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`:
  - New public enum `ResolutionFeedbackPhase: Equatable` — `.idle`, `.loading`, `.noRiskAnalysisSource`, `.empty`, `.loaded` (mirrors the 2.4 five-phase pattern).
  - Three new `@Published` properties after the 2.4 linked-actions block:
    - `resolutionFeedback: ProjectResolutionFeedback?` — most recent aggregated snapshot. Preserved across transient read failures (prior snapshot stays visible).
    - `resolutionFeedbackPhase: ResolutionFeedbackPhase` — discrete phase (defaults to `.idle`).
    - `resolutionFeedbackErrorMessage: String?` — isolated error surface.
  - `applyDeniedState()` extended to clear all three resolution-feedback fields alongside existing access-denial cleanup.
  - New private Decodable DTO `ResolutionFeedbackRow` with `title`, `status`, `severity?`, `resolutionCategory?`, `effectiveness?`, `followUpRequired?`, `reopenCount?`, `resolvedAt?` — matches Web's exact select projection. `CodingKeys` maps snake_case → camelCase.
  - Reuses the existing private `LinkedRiskAnchorRow` (introduced in 2.4) for the step-1 anchor lookup — both flows share the `project_risk_summaries.id` anchor shape.
  - New `public func refreshResolutionFeedback() async` entry point:
    - Captures the pre-call `priorPhase` so a failure can drop back to whatever state was representative before the call.
    - Flips `resolutionFeedbackPhase = .loading`, clears `resolutionFeedbackErrorMessage = nil`.
    - **Step 1**: `.from("project_risk_summaries").select("id").eq("project_id", value: projectId).limit(1).execute().value` as `[LinkedRiskAnchorRow]`. Zero rows → `resolutionFeedbackPhase = .noRiskAnalysisSource`, clears `resolutionFeedback = nil`, returns.
    - **Step 2**: `.from("risk_actions").select("title, status, severity, resolution_category, effectiveness, follow_up_required, reopen_count, resolved_at").eq("ai_source_id", value: anchor.id).order("resolved_at", ascending: false, nullsFirst: false).limit(50).execute().value` as `[ResolutionFeedbackRow]`. Zero rows → `.empty` + `resolutionFeedback = nil`. Non-empty → `.loaded` + `resolutionFeedback = Self.aggregateResolutionFeedback(rows:)`.
    - Failure path: preserves the prior `resolutionFeedback` snapshot (transient flakiness doesn't wipe valid context), writes `resolutionFeedbackErrorMessage = error.localizedDescription`, reverts phase to `priorPhase` (or `.idle` if `priorPhase` was also `.loading`, guarding against a double-tap race). Does NOT touch `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `summaryErrorMessage`, `riskAnalysisErrorMessage`, `linkedRiskActionsErrorMessage`, or `access`.
  - New private static helper `aggregateResolutionFeedback(rows:) -> ProjectResolutionFeedback`: runs Web's exact counts, builds `dominantCategory` with first-encountered tie-break (rows arrive `resolved_at DESC NULLS LAST`, so the tie-break is stable), slices top-3 resolved/dismissed into `recentResolutions`.
  - Verified Supabase Swift SDK signature `order(_:ascending:nullsFirst:referencedTable:)` at `PostgrestTransformBuilder.swift:44` — `nullsFirst: false` is a real parameter; usage is correct.

- `Brainstorm+/Features/Projects/ProjectDetailView.swift`:
  - New `resolutionFeedbackSection` inserted in `detailScroll` AFTER `linkedRiskActionsSection` and BEFORE the `errorMessage` banner + `foundationScopeNote`. Section anchored directly below linked-actions because its data model is aggregated over the same `risk_actions` filter the 2.4 section lists.
  - Section header: "Resolution Feedback" + conditional "{total} tracked" count badge (only shown in `.loaded` phase).
  - Subtitle: "Read-only · resolution write-back and governance interventions are only available on the web." — honest labeling.
  - State-driven body via `@ViewBuilder resolutionFeedbackBody` switching on `resolutionFeedbackPhase`:
    - `.idle` / `.loading`: empty body (button carries the state).
    - `.noRiskAnalysisSource`: "No risk analysis exists for this project yet. Run one from the web dashboard first, then come back to view its resolution feedback here." — distinct copy from `.empty` so the user knows whether to act on Web or wait.
    - `.empty`: "No risk actions tracked yet for this analysis, so there's no resolution feedback to aggregate."
    - `.loaded`: stacks five composable rows — counts row + governance banner (only when `.governanceSignal != .none || isProneToReopen`) + dominant category row (only when category non-nil/non-empty) + recent resolutions header + top-3 `recentResolutionRow` entries.
  - `resolutionCountsRow` renders a horizontal-scroll `HStack` of five pill-shaped badges: `Resolved` (primary on primaryLight), `Dismissed` (textSecondary on gray×15%), `Active` (warning on warning×18%), `Follow-up` (warning on warning×18%), `Reopened` (white on `.red.opacity(0.85)`). Each badge shows `{count} {label}`.
  - `governanceBanner` renders an icon + title + optional "Prone to reopen · {N} reopened action(s) still have unresolved work." sub-line. Palette:
    - `.interventionEffective` → `checkmark.shield.fill` icon + "Intervention effective" title + `Color.Brand.primary` tone on `Color.Brand.primaryLight.opacity(0.55)` bg.
    - `.needsIntervention` → `exclamationmark.shield.fill` icon + "Needs governance intervention" title + `Color.Brand.warning` tone on `Color.Brand.warning.opacity(0.18)` bg.
    - When only `.isProneToReopen` fires (reopen > 0 + active > 0, but no effective intervention), the banner renders with the `.needsIntervention` tone per the `governanceSignal` priority rule.
  - `dominantCategoryRow` renders a tag icon + "Dominant category" + humanized label via `Self.humanize(_:)` (e.g. `root_cause_fixed` → `Root Cause Fixed`).
  - `recentResolutionRow` renders an 8pt status dot (via `resolutionStatusColor(_:)`) + title (2 lines) + effectiveness capsule (via `effectivenessCapsule(effectiveness:)`) + parsed resolved_at date. Date parsing via `resolvedAtDisplayDate(_:)` which tries both `.withInternetDateTime` and `.withFractionalSeconds` ISO 8601 formatters — returns `nil` on any parse failure so render drops the date element rather than crashing.
  - `effectivenessStyle(for:)` palette: `effective → primary on primaryLight`, `partial → warning on warning×18%`, `ineffective → white on red×85%`, `pending → textSecondary on gray×15%`, unknown → humanized label on neutral.
  - `resolutionStatusColor(_:)` narrow palette (recent resolutions list only surfaces `resolved|dismissed`, so the palette is intentionally tight): `resolved → green`, `dismissed/default → textSecondary`.
  - `governanceStyle(for:)` palette maps each governance signal to `(title, foreground, background)` tokens; the `.none` branch is dead-code defensive (callers already guard on `!= .none`).
  - Button state machine (`resolutionFeedbackActionButton`): `.idle` → "Check for resolution feedback" + `checkmark.seal` icon; `.loading` → "Checking…" + `ProgressView` + disabled; `.loaded` / `.empty` / `.noRiskAnalysisSource` → "Refresh"; any phase with `resolutionFeedbackErrorMessage != nil` → "Try again". Disabled while `isLoading || isDeleting`.
  - Button tap fires `Task { await viewModel.refreshResolutionFeedback() }`.
  - Scoped warning row when `resolutionFeedbackErrorMessage != nil` reuses the existing `summaryErrorRow(_:)` builder.
  - `foundationScopeNote` copy updated to: "Converting risks into actions and generating new risk analyses from iOS are available on the web and will arrive in later iOS rounds." (supersedes 2.4's copy — "resolution feedback" is no longer in the deferred list since 2.5 closed that gap.)
  - Visual language reuses existing `enrichmentCard` token (`Color.Brand.paper`, 20 pt corner radius, 0.04 shadow) — no new design token, no new corner radius.

### Files NOT touched

- `Brainstorm+/Core/Models/Project.swift`, `TaskModel.swift` — unchanged.
- `Brainstorm+/Features/Projects/ProjectCardView.swift`, `ProjectListView.swift`, `ProjectListViewModel.swift` — unchanged.
- `Brainstorm+/Features/Projects/ProjectEditSheet.swift`, `ProjectEditViewModel.swift`, `ProjectMemberCandidate.swift` — unchanged.
- `Brainstorm+/Shared/Navigation/AppModule.swift` — unchanged; `.projects` remains `.partial`.
- Database schema, RLS, indexes, views — untouched.
- No new HTTP endpoint, no new Edge Function, no new `api_keys` touchpoint, no write path into `risk_actions` (status transitions, resolution notes, effectiveness, governance).

### Behavior

- Entry: new "Check for resolution feedback" button inside `resolutionFeedbackSection` on `ProjectDetailView`. Tap fires `Task { await viewModel.refreshResolutionFeedback() }`.
- State truth:
  - Idle: nothing rendered in body; button reads "Check for resolution feedback".
  - Loading: button reads "Checking…" with spinner; body empty.
  - noRiskAnalysisSource: honest hint pointing the user to run a risk analysis on Web first; button reads "Refresh".
  - Empty: honest "no resolution feedback to aggregate" hint; button reads "Refresh".
  - Loaded: counts row + optional governance banner + optional dominant category + top-3 recent resolutions; optional "{total} tracked" count badge; button reads "Refresh".
  - Failure: scoped warning row + prior snapshot (if any) still visible below; button reads "Try again".
  - Denied: section hidden via the existing `accessOutcome == .denied` gate in `ProjectDetailView.body`.
- Isolation: resolution-feedback failure never touches `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `summaryErrorMessage`, `riskAnalysisErrorMessage`, `linkedRiskActionsErrorMessage`.
- Persistence: none on iOS. Every visible snapshot reflects the moment of the most recent successful `refreshResolutionFeedback()` call.

## Web parity mapping

| Dimension | Web | iOS 2.5 | Verdict |
|---|---|---|---|
| Entry point | Automatic fetch on risk card render (`loadProjectDetail`) | Explicit "Check for resolution feedback" button | Minor divergence — foundation uses opt-in tap to avoid cascading round-trips (same posture as 2.2 / 2.3 / 2.4) |
| Step 1: anchor table | `project_risk_summaries` | `project_risk_summaries` | Parity |
| Step 1: anchor filter | `.eq('project_id').maybeSingle()` | `.eq("project_id").limit(1) + rows.first` | Parity (Swift SDK lacks `.maybeSingle()`) |
| Step 1: no-anchor branch | Returns `{ data: null, error: null }` | Phase `.noRiskAnalysisSource` + honest hint | iOS stronger |
| Step 2: table | `risk_actions` | `risk_actions` | Parity |
| Step 2: filter | `.eq('ai_source_id', summary.id)` | `.eq("ai_source_id", value: anchor.id)` | Parity |
| Step 2: columns | `title, status, severity, resolution_category, effectiveness, follow_up_required, reopen_count, resolved_at` | identical | Parity |
| Step 2: order | `resolved_at DESC NULLS LAST` | `.order("resolved_at", ascending: false, nullsFirst: false)` | Parity |
| Step 2: limit | 50 | 50 | Parity |
| Total aggregation | Client-side over limit-50 result (caps at 50) | Client-side over limit-50 result (caps at 50) | Parity (matches Web exactly, not a divergence) |
| resolved/dismissed/active count | Counts by status buckets | Counts by status buckets | Parity |
| followUpRequired count | `follow_up_required === true` | `followUpRequired == true` | Parity |
| reopenedCount | `reopen_count > 0` | `(reopenCount ?? 0) > 0` | Parity (nullable guarded) |
| dominantCategory | Most-frequent non-nil `resolution_category`; ties → first-encountered | Same; rows already in `resolved_at DESC` so tie-break is stable | Parity |
| recentResolutions | `rows.filter({resolved or dismissed}).slice(0, 3)` | `rows.filter { resolved/dismissed }.prefix(3)` | Parity |
| Governance `.interventionEffective` trigger | Any recent resolution with `effectiveness === 'effective' && category === 'root_cause_fixed'` | Same | Parity |
| Governance `.needsIntervention` trigger | `reopenedCount > 0 && active > 0` | Same | Parity |
| Governance priority when both fire | **effective-first** (`hasEffective` short-circuits before `needsIntervention`) | `.interventionEffective` wins; only when false does `.needsIntervention` evaluate (2.5.1 fix) | Parity |
| Predictive "易重开" signal | Pulsing rose badge when `reopenedCount > 0 && active > 0`; **independent** of governance status | `isProneToReopen` subline, rendered regardless of governance signal; tinted `Color.Brand.warning` so it is not drowned by the effective banner's primary tone | Parity (different visual affordance, same trigger; iOS keeps the indicator on its own rail) |
| Count badges (resolved / dismissed / active / follow-up / reopened) | Rendered | Rendered as horizontal pill strip | Parity (brand token substitution) |
| Dominant category label | `category → 中文 label` map | `humanize(_:)` underscore-strip + Title Case | Parity (English foundation copy; i18n debt) |
| Recent resolution row format | Title + status + effectiveness + `resolved_at` | Same + parsed display date | Parity |
| Effectiveness color mapping | Web palette | Defensive switch (effective=primary, partial=warning, ineffective=red×85%, pending=textSecondary) | Parity (neutral fallback on unknown values) |
| Failure surface | Silent on Web (empty render) | Scoped warning row with `.localizedDescription` | iOS stronger |
| Failure isolation | N/A | `errorMessage`, `enrichmentErrors`, `deleteErrorMessage`, `summaryErrorMessage`, `riskAnalysisErrorMessage`, `linkedRiskActionsErrorMessage`, `access` untouched; prior snapshot preserved | iOS stronger |
| Phase revert on failure | N/A | `priorPhase` captured + restored | iOS stronger |
| Resolution write-back (close/reopen/effectiveness) | Rendered on Web | Not rendered | **Deferred by scope (devprompt §3.G)** |
| Governance intervention write | Rendered on Web | Not rendered | **Deferred by scope (devprompt §3.G)** |
| "转为风险动作" sync button | Rendered on Web | Not rendered | **Deferred by scope (carry-over from 2.4)** |

## Delta Tables

Every row below describes behavior measured *after* 2.5 landed.

### Detail deltas

| Capability | 2.4 state | 2.5 state |
|---|---|---|
| Linked risk actions section | Delivered | **Delivered (unchanged)** |
| Resolution feedback entry | Absent | **Delivered (2.5)** |
| Resolution feedback loading state | Absent | **Delivered (2.5)** |
| Two-step read (anchor + filtered select with nullsFirst=false order) | Absent | **Delivered (2.5)** |
| `.noRiskAnalysisSource` distinct phase | Absent | **Delivered (2.5)** |
| `.empty` distinct phase | Absent | **Delivered (2.5)** |
| Client-side aggregation (counts + dominantCategory + recentResolutions) | Absent | **Delivered (2.5)** |
| Count badges (resolved/dismissed/active/followUp/reopened) | Absent | **Delivered (2.5)** |
| Governance banner (`.interventionEffective` / `.needsIntervention`) | Absent | **Delivered (2.5)** |
| Predictive "易重开" / `isProneToReopen` signal | Absent | **Delivered (2.5)** |
| Dominant category row | Absent | **Delivered (2.5)** |
| Top-3 recent resolutions list (matches Web slice) | Absent | **Delivered (2.5)** |
| Effectiveness capsule per recent row | Absent | **Delivered (2.5)** |
| Parsed `resolved_at` display date (both timestamptz formats) | Absent | **Delivered (2.5)** |
| Prior-snapshot preservation on failure | Absent | **Delivered (2.5)** |
| Failure isolation (does not touch errorMessage/summaryErrorMessage/riskAnalysisErrorMessage/linkedRiskActionsErrorMessage/etc.) | Absent | **Delivered (2.5)** |
| Resolution write-back (close / reopen / add effectiveness note) | Absent | **Deferred by scope (explicit — devprompt §3.G)** |
| Governance intervention write | Absent | **Deferred by scope (explicit — devprompt §3.G)** |
| "转为风险动作" write path | Absent | **Deferred by scope (carry-over from 2.4)** |
| Generate risk analysis from iOS | Absent | **Deferred (source-of-truth discrepancy from 2.3, carry-over)** |
| Real LLM-generated summary narrative | Absent | **Deferred (source-of-truth discrepancy from 2.2, carry-over)** |
| Risk item / risk_items JSONB parsing | Absent | **Deferred (belongs with later surface)** |

### List deltas

| Capability | 2.4 state | 2.5 state |
|---|---|---|
| Client-side `filteredProjects` | Carry-over | Unchanged |
| Scope pre-filter (mine/all) | Delivered | Unchanged |
| Task count on list card | Delivered (2.1) | Unchanged |
| Any Web-side resolution-feedback surface on list card | Never rendered on Web | Never rendered on iOS (no divergence) |

## Routing Notes

- No new routes. `ProjectDetailView` remains the sole detail surface. `.projects` stays `.partial` on `AppModule`.
- No new sheet modal, no new navigation destination, no new tab.

## Destination Coverage

- 13 modules remain on `ParityBacklogDestination`: `okr`, `deliverables`, `approval`, `request`, `leaves`, `hiring`, `team`, `announcements`, `activity`, `aiAnalysis`, `finance`, `analytics`, `admin`.
- Projects detail surface now covers: header, metadata, progress, description, tasks enrichment, daily logs enrichment, weekly summaries enrichment, owner hydrate, avatar, edit, member management, delete, AI summary foundation, risk analysis foundation, linked risk actions foundation, **resolution feedback foundation (new)**.
- Projects list surface now covers: list fetch, scope filter, membership gate, pagination, task count.

## Debt carried forward (known)

- **"转为风险动作" write path** (`syncRiskFromDetection`): absent on iOS. Deferred by scope (carry-over from 2.4). `risk_actions` INSERT RLS gates on role in `['super_admin', 'admin', 'hr_admin', 'manager']`.
- **Resolution write-back**: closing / reopening / adding effectiveness / adding governance notes remain Web-only. `risk_actions.update` requires the same role gate as insert; belongs with a write-path sprint.
- **Generate-risk-from-iOS**: deferred (second-order source-of-truth discrepancy) pending Web-side `/api/ai/project-risk` HTTP endpoint or Supabase Edge Function. Carry-over from 2.3.
- **LLM-generated narrative on AI summary** (2.2 carry-over): still deferred behind Web-side `/api/ai/project-summary`.
- **Automatic fetch-on-render**: iOS uses explicit "Check for resolution feedback" button; Web auto-fetches in `loadProjectDetail`. Intentional foundation divergence — explicit opt-in avoids cascading round-trips. A future round could auto-invoke `refreshResolutionFeedback()` after a successful `refreshLinkedRiskActions()` (both share the same anchor lookup).
- **`risk_items` JSONB on `project_risk_summaries`**: not parsed. Belongs with a later surface (grouping resolutions by risk item).
- **Assignee hydrate on recent resolutions**: Web's recent-resolutions block does not surface an assignee byline; iOS matches. A later "resolution detail modal" round could hydrate.
- **`root_cause_fixed` / `workaround_applied` / etc. → Chinese label**: iOS uses English `humanize(_:)` underscore-strip + Title Case. Belongs with broader iOS i18n.
- **Re-fetch-on-write coherence**: if a Web user resolves a risk action while the iOS user is on the detail page, the iOS aggregation snapshot won't update until the user taps "Refresh". Foundation-acceptable.
- ~~**Governance priority when both signals fire**: iOS collapses to a single `.needsIntervention` banner; Web renders both badges. Intentional single-banner affordance on iOS.~~ **Resolved in 2.5.1** — governance priority now matches Web's effective-first logic; prone-to-reopen continues to render as an independent subline.
- **`total` caps at 50**: both iOS and Web cap at the `.limit(50)` result size. Not a bug — matches Web's contract.
- **Status / effectiveness vocabulary expansion**: decoded as `String` + defensive UI switch with neutral fallback.
- **Palette debt**: `Color.red.opacity(0.85)` used for the reopened-count badge + ineffective effectiveness — brand critical/danger token would replace.
- **RLS trust**: relies on `risk_actions` + `project_risk_summaries` RLS policies.
- **Locale-aware copy**: all new copy English-only (button labels, state hints, section header, subtitle, count badge, governance banner titles, "Prone to reopen", "Dominant category", "Recent resolutions").
- **Source-of-truth divergence on task count** (2.1 carry-over): iOS list card shows task count, Web list card does not.
- Carry-overs from 1.5–2.4: client-side `filteredProjects`, client-side `AccessOutcome` role normalization, batched `.in("id", values: ids)` hydrate in lieu of nested selects, `AsyncImage` non-persistent cache, date-only `String` fields, absence of `.maybeSingle()`, task-count aggregate scaling, `Color.red` for critical risk / high severity.
- OKRs, Leaves, Deliverables still have empty `Features/` folders.
- Assignee picker remains deferred from 1.1.
- Nested `NavigationStack` inside `ProjectListView` still present (inherited from 1.3 pattern).

## Verification

### 2.5 (retained)

- Scan pattern (devprompt §4.1 — "本轮关键词"): `'getProjectRiskResolutionSummary|resolution_category|effectiveness|follow_up_required|reopen_count|resolved_at|resolutionFeedback|governance|ProjectResolutionFeedback|GovernanceSignal|isProneToReopen'`.
- Scan scope: `Brainstorm+/Features/Projects`.
- Scan count: **106 occurrences across 3 files** (`ProjectDetailModels.swift: 16`, `ProjectDetailViewModel.swift: 48`, `ProjectDetailView.swift: 42`).
- Build: `** BUILD SUCCEEDED **` on `iPhone 17 Pro Max` destination with `CODE_SIGNING_ALLOWED=NO`.

### 2.5.1

- Scan pattern (devprompt §4.1): `'governanceSignal|interventionEffective|needsIntervention|isProneToReopen|danger trumps success|effective-first|hasEffective'`.
- Expect **zero** hits for `danger trumps success` in code or active ledger lines (the debt list line is struck-through for audit trail; the devprompt itself still contains the forbidden phrase, which is expected).
- Expect `effective-first` / `hasEffective` hits in ledger describing the fix.
- Build: re-run after fix (see 47-winston-ready notes for captured result).
