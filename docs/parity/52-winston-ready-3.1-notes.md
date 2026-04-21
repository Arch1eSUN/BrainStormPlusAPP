# 52 Winston Ready — 3.1 Team Chat Foundation (Read + Send + Realtime)

**Round:** `3.1 Team Chat Foundation`
**Date:** `2026-04-21`
**Status:** READY — Tasks A–E code-landed against
`devprompt/3.1-team-chat-foundation.md`. Task F (ledger sync) + Task G (this
file) are the closeout.
**Prompt:** `devprompt/3.1-team-chat-foundation.md`

## 1. Sprint Scope

3.1 delivers the minimum conversational surface: channel list filtered by Web's
access rules, paged message read (hard 50, `created_at ASC`), send (insert +
optimistic append + best-effort `last_message` update), and Realtime INSERT
subscription.

Web source of truth: `BrainStorm+-Web/src/lib/actions/chat.ts` (server actions
wrap `createAdminClient()`), `BrainStorm+-Web/src/hooks/use-realtime.ts`,
`BrainStorm+-Web/supabase/schema.sql`, and three chat migrations (023 / 026 /
028). iOS target: `Brainstorm+/Features/Chat/` plus one addition under
`Brainstorm+/Core/Models/`.

Explicitly out of scope (3.1 devprompt §6): create-conversation UI /
find-or-create-DM / message search / attachments / reactions / withdraw UI /
reply-to render / mentions / unread badges / AI Copilot endpoint / Web-side
RLS tightening.

## 2. Web Source-of-Truth Re-Read

### 2.1 `chat.ts` access control — `getAccessibleChannelMap` (L252-282) + `ensureChannelAccess` (L284-305)

`getAccessibleChannelMap(adminDb, userId)` runs three parallel queries on
`chat_channels`: `.eq('type', 'announcement')`, `.eq('created_by', userId)`,
and (conditionally) `.in('id', membershipIds)` where `membershipIds` is
seeded by a `chat_channel_members.eq('user_id', userId)` lookup at
L253-260. Results merge into a `Map<channelId, DbChannel>`, deduped by id.

`ensureChannelAccess(adminDb, userId, channelId)` is the per-channel gate.
L293 short-circuits on `type === 'announcement' || created_by === userId`.
L295-303 falls back to `chat_channel_members.maybeSingle()` on
`(channel_id, user_id)`; empty → throw `'无权访问该会话'`. Used by
`fetchMessages` (L543), `sendMessage` (L585), `updateMessage` (L668),
`deleteMessage` (L714), `searchMessages` (L834).

### 2.2 `chat.ts` message fetching — `fetchMessages` (L539-576)

`requireUser()` + `createAdminClient()` → `ensureChannelAccess` gate (L543)
→ `runMessageSelect` wrapper (swaps `CHAT_MESSAGE_SELECT_FULL` vs `_LEGACY`
depending on DB schema) → `.eq('channel_id', channelId).order('created_at',
{ ascending: true }).limit(limit)` at L549-551. **Ascending** order, hard
`limit = 50` default.

L556-570 does a second-pass `.in('id', replyIds)` query to hydrate
`reply_to` for `normalizeMessage`. **iOS intentionally omits this**: the
model carries `replyTo: UUID?` but the render layer does not consume it
in 3.1 (debt 3.1-debt-03).

### 2.3 `schema.sql` + migrations 023 / 026 / 028 — Chat RLS state

- `schema.sql:169-178` — `chat_channels`: `id / name / description / type /
  created_by / last_message / last_message_at / created_at`.
- `schema.sql:180-192` — `chat_messages`: `id / channel_id / sender_id /
  content / type / reply_to / attachments jsonb / reactions jsonb /
  is_withdrawn / withdrawn_at / created_at`.
- `schema.sql:194-201` — `chat_channel_members`: `id / channel_id / user_id
  / role ∈ {owner,admin,member} / joined_at`.
- `schema.sql:347` — `chat_messages` SELECT `USING (true)`; `348` INSERT
  `WITH CHECK (auth.uid() = sender_id)`.
- `schema.sql:375` — `chat_channels` SELECT `USING (true)`.
- `023_critical_fixes.sql:55-62` — `chat_channels` INSERT gated on
  `role IN ('super_admin','admin','manager')`.
- `023_critical_fixes.sql:64-72` — `chat_channels` UPDATE admin-role OR
  `auth.uid() = created_by`.
- `026_system_audit_fixes.sql:47-52` — UPDATE widened (for `last_message`
  writeback) to any `auth.uid() IS NOT NULL`.
- `028_chat_message_features.sql:23-33` — `chat_channel_members` SELECT
  `USING (auth.uid() IS NOT NULL)`, INSERT `WITH CHECK (auth.uid() =
  user_id)`; L35-36 indexes on
  `chat_channel_members(user_id, channel_id)` +
  `chat_messages(channel_id, created_at)`.

**Net effect**: a JWT-bearing iOS client can `SELECT` all `chat_channels`
and `chat_messages` rows. Web masks this by routing every chat action
through `createAdminClient()`. iOS has no admin client; access control is
re-implemented client-side and UI must not render rows that fail the
mirror gate. This is the architectural premise of 3.1 (devprompt §2).

### 2.4 Realtime subscription pattern

Web: `src/hooks/use-realtime.ts` L61-67 wires
`supabase.channel(name).on('postgres_changes', {event, schema, table,
filter}, cb).subscribe()`. Channel name is
`realtime-${table}-${filter||'all'}-${Date.now()}` (L51). Cleanup:
`channel.unsubscribe()` (L72). Filter is raw Postgres-changes syntax, e.g.
`user_id=eq.${userId}`.

iOS Supabase Swift SDK `v2.43.1` (`Package.resolved:10`) exposes the
equivalent on `RealtimeChannelV2` via structured (not stringly-typed)
builders:
`client.channel(name).postgresChange(InsertAction.self, schema: "public",
table: "chat_messages", filter: .eq("channel_id", value: id))` returns an
`AsyncStream` consumed via `for await`. iOS writes this exact shape in
`ChatRoomViewModel.subscribeRealtime`; no v1 fallback.

## 3. Deltas Landed

### 3.1 `Brainstorm+/Core/Models/ChatModel.swift`

`ChatChannelMember` struct appended at lines 65-85 with `role: MemberRole`
enum (`.owner / .admin / .member`, matching DB CHECK at `schema.sql:198`).
`CodingKeys` snake-case DB columns. `ChatMessage` (L31-63) is unchanged;
`attachments` / `reactions` stay out of the Codable surface (commented out
at L39-40). commit `0e6e456`.

### 3.2 `Brainstorm+/Features/Chat/ChatListViewModel.swift`

Full rewrite of `fetchChannels()`. Three `async let` queries fire in
parallel (L34-53): announcement, owned, and memberships (decoded to
`[ChatChannelMember]`, then mapped into a fourth conditional
`chat_channels.id IN (...)` query at L58-66). Four result arrays merge via
`Set<UUID>` dedupe (L68-72), sorted by `lastMessageAt DESC nulls last`
falling back to `createdAt DESC` (L74-81). Doc comment at L17-19 cites
`chat.ts:252-282`. commit `f591231`.

### 3.3 `Brainstorm+/Features/Chat/ChatRoomViewModel.swift` (new, 200 lines, `@MainActor`)

Five responsibilities:

- **access gate** (`bootstrap`, L29-69): mirrors `ensureChannelAccess`.
  Short-circuits on `.announcement` or `createdBy == userId`, else
  `chat_channel_members.eq("channel_id").eq("user_id").limit(1)`. Empty
  or throw → `accessDenied = true`, skip fetch/subscribe.
- **fetch** (`fetchMessages`, L74-88): `.eq("channel_id").order(
  "created_at", ascending: true).limit(50)` — exact match for Web.
- **send** (`sendMessage`, L94-147): insert via `InsertPayload` Encodable
  (L109-114), `.select().single()` for the real row, optimistic append if
  absent, then fire-and-forget `UPDATE chat_channels` via `LastMsgPatch`
  (L134-137). `last_message_at` uses
  `ISO8601DateFormatter().string(from: Date())` — PostgREST accepts
  ISO-8601 for `TIMESTAMPTZ`.
- **Realtime** (`subscribeRealtime`): `teardown()` first as
  double-subscribe guard; channel name
  `"realtime-chat_messages-<uuid>"`; registers
  `postgresChange(InsertAction.self, schema:, table:, filter: .eq(...))`;
  subscribes via `try await ch.subscribeWithError()` (the non-deprecated
  API; failures are caught and written to `errorMessage` rather than
  swallowed by a `try?`); spins a `Task` consuming `for await change in
  changes`. Each payload decodes via
  `change.record.decode(as: ChatMessage.self)` (Supabase's configured
  decoder, matches `fetchMessages` timestamp parsing).
  `handleRealtimeInsert` dedupes on `msg.id`.
- **teardown**: cancels task, then schedules
  `client.removeChannel(ch)` on a detached `Task` (full cleanup — both
  unsubscribes the socket topic **and** evicts the channel from
  `RealtimeClientV2`'s topic cache, preventing the "re-enter same room
  returns stale cached channel with layered filters" bug). Nils the
  stored reference. `deinit` only cancels the task: `@MainActor` types
  can't synchronously touch non-Sendable channel state from a
  nonisolated `deinit`, so **the View layer MUST call
  `viewModel.teardown()` from `.onDisappear`**. Honored at
  `ChatRoomView.swift`'s `.onDisappear` hook.

commit `f591231`; Realtime / teardown hardening landed in `06b7f99`.

### 3.4 `Brainstorm+/Features/Chat/ChatRoomView.swift`

Full rewrite. `@StateObject` injection of `ChatRoomViewModel` (L5-10).
Three UI states (L32-67): `accessDenied` renders "你没有权限查看此频道";
`isLoading && messages.isEmpty` renders `ProgressView`; otherwise
`ScrollViewReader` wraps a `LazyVStack` of `messageBubble` rows, with
`.onChange(of: viewModel.messages.count)` scrolling to last
(L60-64). `inputBar` hidden when `accessDenied` (L20). Send button
`disabled` when `isSending` or trimmed text empty (`isSendDisabled`,
L107-110). Lifecycle: `.task { await bootstrap() }` (L27) + `.onDisappear
{ teardown() }` (L28). commit `7b0b135`.

### 3.5 `Brainstorm+/Features/Chat/ChatDateFormatter.swift` (new, 54 lines)

`enum` namespace. Four `static let` `DateFormatter` instances
(`Locale(identifier: "zh_CN")`):
- today: `"HH:mm"`
- yesterday: `"'昨天' HH:mm"`
- same-year: `"M月d日 HH:mm"`
- older: `"yyyy年M月d日"`

`format(_ date: Date?) -> String` returns `""` for nil. Branch order:
`isDateInToday` → `isDateInYesterday` → same-year → fallback. Five
branches total including the nil-guard. Strict superset of devprompt's
3-branch shape — the extra `yyyy年…` branch matches Web's implicit
`toLocaleDateString` fallback. commit `7b0b135`.

### 3.6 `Brainstorm+/Features/Chat/ChatListView.swift`

Minimal patch. `NavigationLink` destination changed to
`ChatRoomView(viewModel: ChatRoomViewModel(client: supabase, channel:
channel))` (L21). Row trailing timestamp now uses
`ChatDateFormatter.format(channel.lastMessageAt)` (L39). No other UI
changes. commit `7b0b135`.

## 4. Verification

`xcodebuild build -scheme "Brainstorm+" -destination "generic/platform=iOS
Simulator" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` →
`** BUILD SUCCEEDED **`.

No Swift Testing unit tests land in 3.1. The Chat surface is network- +
Realtime-heavy: `fetchChannels` / `fetchMessages` / `sendMessage` are thin
Supabase-SDK wrappers whose correctness lives in query shape; Realtime
requires a live WebSocket; `ChatRoomViewModel` is `@MainActor` holding
non-Sendable `RealtimeChannelV2` which a mock would have to stand in for.
MVP verification is manual two-simulator smoke (devprompt §4): A sends → B
renders < 2s, own message appears immediately without duplicating on echo,
deep-link into a non-member channel lands on access-denied. A
mock-Supabase harness is **possible** (not "impossible") — adding one is
its own chore, unrelated to the RLS-scoped 3.1-debt-05; tracked
separately as a testability follow-up (see §6 3.1-debt-09).
`ChatDateFormatter.format` was manually verified via three discarded
one-off assertions (today / yesterday / older) per devprompt §4 L529;
worth promoting to Swift Testing next sprint.

## 5. Audit Checklist for Winston

Verify — should all trivially pass:

- [ ] `ChatChannelMember` struct exists at
  `Brainstorm+/Core/Models/ChatModel.swift:65-85` with `role: MemberRole`
  enum containing `.owner / .admin / .member`.
- [ ] `ChatMessage` still declines `attachments` / `reactions` (commented
  at L39-40) — unchanged from pre-3.1.
- [ ] `ChatListViewModel.fetchChannels` fires three `async let` queries.
  Grep `async let` in
  `Brainstorm+/Features/Chat/ChatListViewModel.swift` → expect exactly 3
  matches.
- [ ] `ChatListViewModel` merges via `Set<UUID>` dedupe, sorts by
  `lastMessageAt DESC nulls last` then `createdAt DESC` (L68-81).
- [ ] `ChatRoomViewModel.bootstrap()` sets `accessDenied = true` when the
  user is neither channel creator nor a `chat_channel_members` row
  (L57-65).
- [ ] `ChatRoomViewModel.fetchMessages` uses `.order("created_at",
  ascending: true).limit(50)` — matches `chat.ts:550-551`.
- [ ] `ChatRoomViewModel.sendMessage` performs (a) insert with
  `.select().single()`, (b) optimistic append gated on `!messages.contains
  { $0.id == inserted.id }`, (c) fire-and-forget `UPDATE chat_channels SET
  last_message, last_message_at` via `_ = try?` (L117-143).
- [ ] `subscribeRealtime` uses structured
  `.postgresChange(InsertAction.self, schema:, table:, filter:
  .eq("channel_id", value: ...))` (not the deprecated string filter form).
  Grep `.postgresChange(InsertAction.self` → expect exactly 1 match.
- [ ] `ChatRoomView.onDisappear` calls `viewModel.teardown()`. Grep
  `teardown()` in `Brainstorm+/Features/Chat/ChatRoomView.swift` → expect
  exactly 1 match.
- [ ] `ChatRoomViewModel.deinit` only cancels the Task (does not call
  `teardown()` synchronously) — L197-199; rationale in §3.3.
- [ ] `ChatDateFormatter.format` at
  `Brainstorm+/Features/Chat/ChatDateFormatter.swift` handles
  nil / today / yesterday / same-year / older — 5 branches.
- [ ] `ChatListView` row uses
  `ChatDateFormatter.format(channel.lastMessageAt)` and constructs
  `ChatRoomViewModel(client: supabase, channel: channel)` inside the
  `NavigationLink`.
- [ ] `xcodebuild build -scheme "Brainstorm+" -destination
  "generic/platform=iOS Simulator"` → `** BUILD SUCCEEDED **`.
- [ ] Unimplemented-feature guard under `Brainstorm+/Features/Chat/`:
  grep `attachments` / `reactions` / `@mention` / `createConversation` /
  `findOrCreateDirectMessage` / `searchMessages` → expect 0 matches each.
  `replyTo` appears only in `ChatMessage` model (pre-3.1); grep `replyTo`
  under `Brainstorm+/Features/Chat/` → expect 0 matches.

Scope-creep reverse checks — should find nothing:

- New UI for create-conversation / DM-find-or-create / search → out of
  scope.
- Storage bucket wiring / `chat-files` references → out of scope (3.2).
- Message withdraw / edit / delete UI → out of scope.
- Reaction picker / reaction display → out of scope.
- Mention parser / mention highlight → out of scope.
- AI Copilot `/api/chat` hook → out of scope (user-excluded globally).
- Web schema / RLS / migration edits → out of scope (debt 3.1-debt-05).

## 6. Debt Carry-Forward (open after 3.1)

- **3.1-debt-01 Attachments / images / files**. Web has `chat-files` bucket
  (`028_chat_message_features.sql:38`), `attachments jsonb`
  (`schema.sql:187`), and `message.type IN ('image','file')`
  (`schema.sql:185`). iOS model omits `attachments`; iOS send always uses
  `type: "text"`.
  **Why deferred**: separate upload pipeline + signed-URL render is the
  natural scope of the next sprint.
  **When to revisit**: 3.2 Team Chat Attachments.

- **3.1-debt-02 Message withdraw**. `ChatMessage` carries `isWithdrawn:
  Bool` + `withdrawnAt: Date?`, but 3.1 renders raw `content` without
  inspection, and no UI writes these fields. Web has `withdrawMessage`
  (chat.ts ~L662+).
  **Why deferred**: UI + confirm modal + UPDATE RLS audit pending.
  **When to revisit**: 3.2+, likely alongside edit/delete.

- **3.1-debt-03 Reply threading render**. `ChatMessage.replyTo: UUID?`
  exists in model but is not consumed anywhere. Web `fetchMessages`
  (chat.ts:556-570) does a second `.in('id', replyIds)` query and feeds
  `normalizeMessage` with a `replyLookup`. iOS skips that second pass
  entirely in 3.1.
  **Why deferred**: needs `MessageBubble` redesign to host a quoted
  parent snippet + the second round-trip.
  **When to revisit**: 3.2+, likely folded with 3.1-debt-02.

- **3.1-debt-04 Mentions / search / create-conversation /
  find-or-create-DM**. Web ships `searchMessages` (L830+),
  `createConversation`, `findOrCreateDirectMessage`; `page.tsx` has the
  `canCreate = isPrimaryAdmin(primaryRole)` FAB gate and a search field.
  iOS has none.
  **Why deferred**: each is an independent surface with its own
  capability gate; not MVP for "can chat at all."
  **When to revisit**: 3.3+ after Attachments.

- **3.1-debt-05 Web RLS tightening**（**跨端安全对齐 / 系统级安全债 — 未解决**）.
  Web `chat_channels` / `chat_messages` SELECT are literally `USING (true)`
  (`schema.sql:347, 375`); safety lives in `createAdminClient()` +
  server-side gate functions. **Any JWT-bearing client can SELECT every
  channel and every message directly at the DB layer.** The iOS
  client-side access gate only decides what the app *renders*, not what
  the database *returns* — a forged client bypasses it entirely. This is
  a real unresolved security exposure, not an accepted engineering
  trade-off.
  **Why not fixed in 3.1**: cross-repo change (Web schema migration + Web
  server-action regression pass + iOS simplification) with rollout risk
  on a live channel set; out of 3.1 scope.
  **When to revisit**: spec drafted and queued as
  `devprompt/3.2a-chat-rls-tightening.md` (commit `<filled by closeout>`)
  — awaiting user approval to schedule.

- **3.1-debt-06 Realtime connection failure visibility** ✅ **CLOSED**
  in closeout pass. Fix `06b7f99` swapped deprecated `subscribe()` for
  `subscribeWithError()` and writes
  `errorMessage = "实时连接失败，新消息可能延迟送达"` on throw; the
  shared `.zyErrorBanner($viewModel.errorMessage)` modifier (Task 3.1-K)
  now surfaces it on-screen with an auto-dismiss (default 5s) and a
  manual X.

- **3.1-debt-07 Chat error surfacing** ✅ **CLOSED** in closeout pass.
  `ChatRoomViewModel.fetchMessages` / `.sendMessage` and
  `ChatListViewModel.fetchChannels` all publish to
  `@Published var errorMessage: String?`; both views now attach
  `.zyErrorBanner($viewModel.errorMessage)` (see
  `Shared/DesignSystem/Modifiers/ZYErrorBannerModifier.swift`) so fetch,
  send, and list-load failures surface as a top-aligned red banner with
  5s auto-dismiss + manual close. Realtime subscribe failures
  (debt-06) ride the same channel, so a single UI primitive closes both.

- **3.1-debt-08 Navigation-destination laziness for chat room**.
  `ChatListView.swift:21` eagerly constructs
  `ChatRoomViewModel(client:channel:)` for every row at list-render time;
  only the actually-navigated row's VM survives (`@StateObject`
  semantics). The init is cheap (two stored references, no IO) so
  runtime cost is negligible, but it is still wasted allocation. Fix is
  to migrate to iOS 16 value-based navigation
  (`NavigationLink(value:)` + `.navigationDestination(for:)`) whose
  destination closure is lazy.
  **Why deferred**: correctness is untouched, and a nav refactor is
  out of 3.1 minimal-surface scope.
  **When to revisit**: opportunistically alongside a broader navigation
  pass, or when the list grows large enough to measure.

- **3.1-debt-09 Mock-Supabase testability harness**. This sprint has
  zero automated coverage on the chat viewmodels — access-gate union,
  empty-result handling, decode failure, send failure, and realtime
  decode-or-subscribe failure are all verified only by manual
  two-simulator smoke. The blocker is that `SupabaseClient` is a
  concrete class with no protocol seam; wrapping `PostgrestQueryBuilder`
  / `RealtimeChannelV2` for fake-driven unit tests is a multi-hour
  infra task unrelated to 3.1's user-visible deliverable.
  **Why deferred**: pure testability infra; independent of RLS
  security work (debt-05), which must be solved at the DB layer not
  the client. Was erroneously folded into debt-05 in the original
  draft; split out here to stop coupling "add tests" to "tighten RLS."
  **When to revisit**: first sprint that either adds a non-trivial
  chat codepath (3.2+ features: reactions, attachments, threading) or
  that budgets a dedicated testability pass. At that point, introduce
  a minimal `ChatDataSource` protocol in `Core/Services/` with a fake
  implementation in tests, and backfill coverage for the five cases
  above.

## 7. Artifacts

- Source (new): `Brainstorm+/Features/Chat/ChatRoomViewModel.swift`,
  `Brainstorm+/Features/Chat/ChatDateFormatter.swift`,
  `Brainstorm+/Shared/DesignSystem/Modifiers/ZYErrorBannerModifier.swift`.
- Source (edited): `Brainstorm+/Core/Models/ChatModel.swift`,
  `Brainstorm+/Features/Chat/ChatListViewModel.swift`,
  `Brainstorm+/Features/Chat/ChatRoomView.swift`,
  `Brainstorm+/Features/Chat/ChatListView.swift`.
- Tests: none this sprint (rationale §4); mock-Supabase harness follow-up
  tracked via 3.1-debt-09.
- Devprompt: `devprompt/3.1-team-chat-foundation.md` (commit `fdaf782`).
- Commits:
  - `fdaf782` — devprompt.
  - `0e6e456` — Task A `ChatChannelMember` model.
  - `f591231` — Task B + Task C viewmodels (list union + room
    gate/fetch/send/realtime).
  - `7b0b135` — Task D + Task E view binding, `ChatDateFormatter`, list
    `NavigationLink` update.
  - `a421140` — Task F ledger sync.
  - `3f5679d` — Task G this file.
  - `71e8957` — ledger correction (stale `53-` → `52-` ready-notes path).
  - `06b7f99` — reviewer follow-up: `teardown()` uses
    `client.removeChannel(ch)`; `subscribeWithError()` replaces
    deprecated `subscribe()`; `ChatRoomView.sendTapped` clears input
    optimistically before awaiting send.
  - `a1ab1f7` — ledger: record 3.1-debt-06/07/08 from reviewer
    follow-up.
  - `97d64ad` — closeout: new `ZYErrorBannerModifier` + wire
    `.zyErrorBanner` into `ChatRoomView` + `ChatListView`; closes
    3.1-debt-06 + 3.1-debt-07.
- Ledger sync: `findings.md`, `progress.md`, `task_plan.md`.
- Web references cited: `BrainStorm+-Web/src/lib/actions/chat.ts`
  L252-282 / 284-305 / 539-576; `BrainStorm+-Web/src/hooks/use-realtime.ts`
  L47-75; `BrainStorm+-Web/supabase/schema.sql` L169-201 / 347 / 375;
  `023_critical_fixes.sql:55-72`, `026_system_audit_fixes.sql:47-52`,
  `028_chat_message_features.sql:23-36`.
