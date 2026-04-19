# 32 Winston Audit — 1.8 Projects Nested Profile Join + Avatar Rendering Foundation

**Audit Time:** 2026-04-16 17:18 GMT+8  
**Auditor:** Winston  
**Result:** PASS — `1.8 Projects Nested Profile Join + Avatar Rendering Foundation` passes and is certified complete.

## 1. Audit Scope

Audited against:

- `devprompt/1.8-projects-nested-profile-join-avatar-rendering-foundation.md`
- `docs/parity/31-winston-ready-1.8-notes.md`
- `docs/parity/30-winston-audit-1.7.md`
- `docs/parity/28-winston-audit-1.6.md`
- `progress.md`
- `findings.md`
- `task_plan.md`
- `Brainstorm+/Features/Projects/ProjectDetailModels.swift`
- `Brainstorm+/Features/Projects/ProjectDetailViewModel.swift`
- `Brainstorm+/Features/Projects/ProjectDetailView.swift`
- `Brainstorm+/Features/Projects/ProjectCardView.swift`
- `Brainstorm+/Features/Projects/ProjectListViewModel.swift`
- `Brainstorm+/Features/Projects/ProjectListView.swift`
- Web source of truth:
  - `../BrainStorm+-Web/src/lib/actions/projects.ts`
  - `../BrainStorm+-Web/src/app/dashboard/projects/page.tsx`
- independent `rg` scan
- independent `xcodebuild`

## 2. Independent Verification

### 2.1 Prompt Scan

Independently ran:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
rg -n 'profiles:assignee_id|profiles:user_id|assignee_id|user_id|full_name|avatar_url|AsyncImage|ProjectOwner|ProjectTask|ProjectDailyLog|ProjectWeekly|profilesById|taskAssigneesById|dailyLogUsersById|weeklySummaryUsersById|fetchDetail\(|project_members|AccessOutcome|loadEnrichment|applyDeniedState|ProjectDetailView|ProjectCardView|ProjectListViewModel|projects' Brainstorm+ progress.md findings.md task_plan.md
```

Confirmed:

- `ProjectDetailModels.swift` now exposes `userId` on:
  - `ProjectDailyLogSummary`
  - `ProjectWeeklySummary`
- `ProjectDetailViewModel` now defines:
  - `profilesById: [UUID: ProjectOwnerSummary]`
  - `EnrichmentSection.sublistProfiles`
  - `hydrateSublistProfiles()`
  - `displayName(forUserId:)`
- `ProjectDetailView` now defines and uses:
  - `ownerMetaRowLayout(...)`
  - `ownerAvatarView(...)`
  - `taskMetaLine(for:)`
  - `authorLine(forUserId:)`
- `ProjectCardView` now renders owner avatar via `AsyncImage` with fallback placeholder.
- `ProjectListViewModel` continues to batch-hydrate owner profiles via `ownersById`.
- Ledger files state `.projects` remains `.partial`, and deferred gaps are still honestly listed.

### 2.2 Web Source Verification

Independently re-verified Web `fetchProjectDetail(projectId)` in `BrainStorm+-Web/src/lib/actions/projects.ts`.

Confirmed the Web detail query surface still contains:

```ts
adminDb.from('tasks')
  .select('id, title, status, priority, assignee_id, profiles:assignee_id(full_name)')

adminDb.from('daily_logs')
  .select('id, date, content, progress, blockers, profiles:user_id(full_name)')

adminDb.from('weekly_reports')
  .select('id, week_start, summary, highlights, challenges, profiles:user_id(full_name)')
```

Also re-verified Web `projects/page.tsx`:

- list card renders owner avatar + full name
- detail task rows render `t.profiles?.full_name`
- Web still contains CRUD / member picker / AI summary / risk analysis surfaces

This confirms 1.8 targeted the correct next delta after 1.7: nested profile readability on detail sublists and avatar rendering on list/detail.

### 2.3 Build

Independently ran:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
```

Result:

```text
** BUILD SUCCEEDED **
```

## 3. Findings

### 3.1 Goal A — Nested Profile Name Join on Detail Sublists

**Status:** PASS

Verified architectural choice in `ProjectDetailViewModel`:

- `loadEnrichment(for:)` still fans out owner / tasks / daily / weekly in parallel.
- `_ = await (ownerFetch, tasksFetch, dailyFetch, weeklyFetch)` completes first.
- `hydrateSublistProfiles()` then performs exactly one batched profile lookup.

Verified sublist profile hydration logic:

```swift
.from("profiles")
.select("id, full_name, avatar_url")
.in("id", values: Array(ids))
```

Verified id sources:

- `tasks[].assigneeId`
- `dailyLogs[].userId`
- `weeklySummaries[].userId`

Verified owner id is removed before batch hydrate to avoid redundant re-fetch.

Verified display resolution path:

- `displayName(forUserId:)` checks `profilesById`
- falls back to owner when user id equals owner id
- returns `nil` when unresolved

Verified view wiring:

- task meta line now includes assignee name when resolvable
- daily log header now includes `By <name>` when resolvable
- weekly summary header now includes `By <name>` when resolvable

This satisfies the 1.8 human-readable nested profile target without introducing nested DTO sprawl or N+1 queries.

### 3.2 Goal B — Owner Avatar Rendering Foundation

**Status:** PASS

Verified `ProjectCardView`:

- owner byline now renders a 16 pt `AsyncImage`
- nil / empty / invalid URL falls back to placeholder
- `.failure`, `.empty`, `@unknown default` all handled
- avatar failure does not affect card text rendering

Verified `ProjectDetailView`:

- owner metadata row now renders a 22 pt `AsyncImage`
- same fallback chain is present
- metadata layout remains foundation-grade and does not over-redesign the detail card

This closes the exact 1.7 audit gap: iOS was fetching `avatar_url` but not using it.

### 3.3 Goal C — State Truth / Failure Isolation

**Status:** PASS

This was the key correctness checkpoint.

Verified:

- `applyDeniedState()` now clears:
  - `project`
  - `owner`
  - `tasks`
  - `dailyLogs`
  - `weeklySummaries`
  - `profilesById`
  - `enrichmentErrors`
- non-member callers still take the 1.6 `.denied` path before enrichment becomes visible
- sublist profile hydrate failure is isolated to `enrichmentErrors[.sublistProfiles]`
- avatar failure remains view-local and does **not** pollute `errorMessage`
- base section data failure and profile-name failure are separated correctly

No 1.6 regression found. No 1.7 section regression found.

### 3.4 `.projects` Status Honesty

**Status:** PASS

Verified all ledger and code-facing statements remain honest:

- `.projects` remains `.partial`
- still missing:
  - create / update / delete project flows on iOS
  - member picker / member management UI
  - AI summary
  - risk analysis
  - linked risk actions
  - resolution feedback
  - `task_count` on list

1.8 did not overclaim parity.

## 4. Risk Notes

### 4.1 Correct trade-off: batched hydrate instead of nested decode

This is the right call for current Swift SDK ergonomics.

Why:

- Web nested sub-select shape is convenient in TS.
- Swift flat `Codable` decode becomes materially uglier if three sublists each absorb nested `profiles` payloads.
- 1.8 keeps DTOs narrow and pays a bounded one-query follow-up cost.
- That cost is stable and **not N+1**.

I consider this an acceptable parity-preserving implementation difference.

### 4.2 Remaining debt remains real

Still open after 1.8:

- image caching beyond `AsyncImage`
- full CRUD parity
- member management parity
- AI / risk parity
- list `task_count`
- nested `NavigationStack` cleanup if/when that becomes worth touching

These are real gaps, but none block certifying 1.8.

## 5. Audit Verdict

**PASS.**

`1.8 Projects Nested Profile Join + Avatar Rendering Foundation` is certified complete.

It correctly closes the two 1.7 audit gaps:

1. nested profile readability on detail sublists
2. owner avatar rendering on list/detail

It does so without regressing:

- 1.5 list scoping
- 1.6 detail membership gate
- 1.7 read-only detail enrichment foundation

## 6. Next Recommended Round

The highest-value remaining Projects delta is no longer read-only display polish; it is the absence of **native project editing + member management entry**.

Recommended next formal round:

- `1.9 Projects Edit + Member Management Foundation`

Scope should stay narrow:

- native edit entry from list/detail
- update existing project fields
- member picker / current-member state parity foundation
- no delete if the round becomes too wide
- no AI / risk expansion yet unless explicitly split into a later round
