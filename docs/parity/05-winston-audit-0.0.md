# 05 Winston Audit — 0.0 Current Foundation Parity

**Audit Time:** 2026-04-15 21:58 GMT+8  
**Auditor:** Winston  
**Result:** FAIL — enter `0.0-0.1` repair round, do not enter `1.0` yet.

## 1. Audit Scope

Audited against:

- `devprompt/0.0-current-foundation-parity.md`
- Required docs under `docs/parity/`
- Required code foundation fixes:
  - `MainTabView.swift`
  - `ActionItemHelper.swift`
  - `AppModule.swift`
- Planning files:
  - `task_plan.md`
  - `findings.md`
  - `progress.md`
- Independent `xcodebuild` verification

## 2. Positive Findings

### 2.1 Required parity docs exist

Confirmed files:

- `docs/parity/00-source-of-truth.md`
- `docs/parity/01-web-module-map.md`
- `docs/parity/02-ios-current-state.md`
- `docs/parity/03-design-token-map.md`
- `docs/parity/04-ios-parity-foundation-plan.md`

### 2.2 Core code files exist / were modified

Confirmed files:

- `Brainstorm+/Features/Dashboard/MainTabView.swift`
- `Brainstorm+/Features/Dashboard/ActionItemHelper.swift`
- `Brainstorm+/Shared/Navigation/AppModule.swift`
- `Brainstorm+/Features/Dashboard/DashboardView.swift`
- `Brainstorm+/Shared/Supabase/SessionManager.swift`

### 2.3 Copilot `if true` hack appears removed from source code

Independent scan did not find `if true` in app source.

`MainTabView.swift` now uses:

- `SessionManager.currentProfile`
- `RBACManager.shared.getEffectiveCapabilities(for:)`
- `.ai_chatbot_access`

This satisfies the basic intent of removing the direct `if true` hack.

### 2.4 `AppModule.swift` exists

`Brainstorm+/Shared/Navigation/AppModule.swift` exists and includes:

- module id
- displayName
- webRoute
- iconName
- group
- implementationStatus

This satisfies the baseline structure requirement.

### 2.5 Build verified independently by Winston

Command run:

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" CODE_SIGNING_ALLOWED=NO
```

Result:

```text
** BUILD SUCCEEDED **
```

## 3. Blocking Issues

### B1 — Planning files are stale and contradict completion state

`task_plan.md` still shows unchecked items:

- Create parity docs
- Fix Copilot hack
- Create `AppModule.swift`
- Update `ActionItemHelper.swift`
- Build iOS App
- Update progress

But the actual files and progress claim those were completed.

Impact:

- Violates `planning-with-files` requirement.
- Breaks auditability.
- Future agents may misread completed work as incomplete.

Severity: High / audit-blocking.

### B2 — `findings.md` is stale and still reports resolved defects as current

`findings.md` still says:

- `MainTabView.swift` has an `if true` hack.
- `DashboardView.swift` and `ActionItemHelper.swift` use `PlaceholderDestination`.

But source code shows:

- `if true` is no longer present in `MainTabView.swift`.
- `ParityBacklogDestination` is now introduced.

Impact:

- Violates factual consistency.
- Makes the evidence ledger unreliable.

Severity: High / audit-blocking.

### B3 — `docs/parity/02-ios-current-state.md` is stale and incorrectly describes current code

The doc still says:

- `MainTabView.swift` line 32 contains `if true`.
- `DashboardView.swift` uses `PlaceholderDestination` everywhere.
- `TaskListView.swift` has `TODO: Open New Task Sheet`.

The first two are stale after code changes. The third remains true.

Impact:

- Required parity doc does not reflect actual audited state.
- Fails the 0.0 requirement to “真实记录当前 App 状态”.

Severity: High / audit-blocking.

### B4 — `ActionItemHelper` routing is still title-string heuristic, not route/module authoritative

Current `ActionItemHelper.destination(for title: String)` maps by fuzzy string checks:

- `contains("task")`
- `contains("project")`
- `contains("request")`
- etc.

This is better than the previous generic placeholder, but still not a robust module/router foundation.

Impact:

- Ambiguous strings can route incorrectly.
- It does not yet fully enforce `AppModule` as the navigation source of truth.
- It only partially satisfies “不再用裸字符串驱动核心导航”.

Severity: Medium / repair-required before 1.0.

### B5 — `AppModule` is missing explicit required capabilities / roles

The 0.0 prompt required each module to include:

- id
- displayName
- webRoute
- iconName
- group
- requiredCapabilities / requiredRoles optional fields
- implementation status

`AppModule.swift` has most fields, but no capability/role metadata.

Impact:

- Route visibility cannot yet be derived from module metadata.
- 1.0 RBAC work would start from an incomplete navigation model.

Severity: Medium / repair-required before 1.0.

### B6 — `TaskListView.swift` TODO remains, but was not in this round’s required fix scope

Scan still finds:

```text
Brainstorm+/Features/Tasks/TaskListView.swift:116: // TODO: Open New Task Sheet
```

Impact:

- Important product gap.
- Not a 0.0 blocker because this round explicitly did not require full Tasks CRUD.
- Must remain documented as a known gap, not treated as fixed.

Severity: Low for 0.0 / high for future Tasks parity.

## 4. Verification Scan Evidence

Scan command:

```bash
rg -n "if true|PlaceholderDestination|TODO: Open New Task Sheet|Coming Soon" Brainstorm+ docs/parity task_plan.md findings.md progress.md
```

Key results:

```text
findings.md:11:- `MainTabView.swift` has an `if true` hack for Copilot.
findings.md:12:- `DashboardView.swift` and `ActionItemHelper.swift` mock most navigation routing with generic partial destinations (like `PlaceholderDestination`). Only Tasks is properly hooked.
task_plan.md:12:- [ ] Fix Copilot hack in `MainTabView.swift` (remove `if true`, use real RBAC).
task_plan.md:14:- [ ] Update `ActionItemHelper.swift` to use `ParityBacklogDestination` instead of `PlaceholderDestination`.
docs/parity/02-ios-current-state.md:27:  - **Copilot Hack:** Line 32 contains `if true` to override permission checks for displaying the copilot tab.
docs/parity/02-ios-current-state.md:29:  - **Mock Routing:** Uses `PlaceholderDestination` everywhere inside quick links for items not firmly mapped.
Brainstorm+/Features/Tasks/TaskListView.swift:116:                    // TODO: Open New Task Sheet
Brainstorm+/Features/Dashboard/MainTabView.swift:46: Text("BrainStorm+ Copilot (Coming Soon)")
```

## 5. Final Verdict

0.0 cannot pass because documentation and planning evidence contradict the actual code state.

This is not a functional build failure. It is an auditability and foundation-quality failure.

## 6. Required Next Step

Create and execute repair prompt:

- `devprompt/0.0-0.1-audit-repair.md`

Repair goals:

1. Update stale planning files.
2. Update stale findings.
3. Update stale parity docs.
4. Strengthen `AppModule` metadata with capability/role hooks where evidence exists.
5. Reduce `ActionItemHelper` fuzzy string dependence by adding module-based destination API.
6. Rebuild and rescan.

Only after `0.0-0.1` passes audit should Winston generate `1.0`.
