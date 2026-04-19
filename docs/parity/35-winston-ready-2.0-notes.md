# Winston-Ready Notes — Sprint 2.0 (Projects Delete Foundation)

**Execution model**: Claude Opus 4.6.
**Build status**: `** BUILD SUCCEEDED **` on `iPhone 17 Pro Max`, `CODE_SIGNING_ALLOWED=NO`.
**Audit target**: `docs/parity/36-winston-audit-2.0.md` (to be written by Winston).

## 1. Round Scope

Close the next narrow Projects parity gap flagged by Winston 1.9 audit:

- **Delete flow** — Web ships a working `deleteProject(id)` action wired into the Projects dashboard row; iOS 1.9 had no delete surface at all.
- **Post-delete state coherence** — even a successful Web-side delete wouldn't reflect in an open iOS detail view or list until a manual refresh; 2.0 closes both.

Explicitly **out of scope** (devprompt §3.D):

- AI summary, risk analysis, linked risk actions, resolution feedback, `task_count`.
- Create-flow redesign, edit-flow redesign, member-management redesign, large UI redesign.
- Schema changes, batch delete, recycle-bin / undo / recover systems.

## 2. Web Source of Truth Re-read

### 2.1 `BrainStorm+-Web/src/lib/actions/projects.ts`

```ts
export async function deleteProject(id: string) {
  await serverGuard()
  const supabase = createAdminClient()
  // project_members cascade-deletes via FK
  const { error } = await supabase.from('projects').delete().eq('id', id)
  if (error) return { error: error.message }
  return { error: null }
}
```

### 2.2 `BrainStorm+-Web/src/app/dashboard/projects/page.tsx`

```ts
const handleDelete = async (id: string) => {
  if (!confirm('确定删除这个项目吗？')) return
  const res = await deleteProject(id)
  if (res.error) {
    alert(res.error)
    return
  }
  await reload()
}
```

### 2.3 Key observations

- Web targets ONLY the `projects` row. `project_members` cascade is a Postgres FK responsibility, not a Web-side responsibility. iOS must mirror this — no client-side `project_members.delete(...)` call.
- Web's intent gate is a simple native `confirm()`. iOS's platform-native equivalent is `.confirmationDialog(...)` with `Button(role: .destructive)`.
- Web's failure surface is a native `alert(error.message)`. iOS's platform-native equivalent is `.alert(title: isPresented: message:)`.
- Web's success cleanup is `await reload()` — re-fetches the full list. iOS can go cheaper: local row removal is correct because delete semantics unambiguously mean "row is gone" (unlike edit, which might have computed columns the server computes on write).

## 3. iOS 2.0 Deliverables

### 3.1 View-model additions

- `ProjectListViewModel.swift`:
  - `@Published public var isDeleting: Bool = false`.
  - `@Published public var deleteErrorMessage: String? = nil` — isolated from `errorMessage` and `ownersErrorMessage`.
  - `public func deleteProject(id: UUID) async -> Bool` → `.from("projects").delete().eq("id", value: id).execute()` + local `projects.removeAll { $0.id == id }` on success; failure leaves `projects` intact.
  - `public func removeProjectLocally(id: UUID)` — pure local helper used by the detail view's `onProjectDeleted` callback.

- `ProjectDetailViewModel.swift`:
  - Same `isDeleting` + `deleteErrorMessage` pair (isolated from `errorMessage` and `enrichmentErrors`).
  - `public func deleteProject() async -> Bool` targeting `self.projectId`; on success clears `self.project = nil` (prevents stale-row flash during pop animation); on failure leaves `project` + enrichment untouched.

### 3.2 View additions

- `ProjectListView.swift`:
  - `@State private var projectPendingDelete: Project? = nil` — identifiable binding so rapid row-switching rebuilds the dialog against the correct project.
  - `Button(role: .destructive) { projectPendingDelete = project }` added to the existing 1.9 `.contextMenu`.
  - `.confirmationDialog("Delete project?", ...titleVisibility: .visible, presenting: projectPendingDelete)` with destructive `Delete "<name>"` button + Cancel.
  - `.alert("Delete failed", ...)` surfaces `viewModel.deleteErrorMessage` and clears it on dismiss.
  - `NavigationLink` to `ProjectDetailView` now passes `onProjectDeleted: { id in viewModel.removeProjectLocally(id: id) }`.

- `ProjectDetailView.swift`:
  - `@Environment(\.dismiss) private var dismiss` + new `onProjectDeleted: ((UUID) -> Void)?` init param + new `@State private var isShowingDeleteConfirm: Bool = false`.
  - Second `.topBarTrailing` toolbar button (`Image(systemName: "trash")`, destructive-colored via `Color.Brand.warning`). Access gate reuses the 1.9 edit-button gate: `accessOutcome != .denied, let _ = viewModel.project`.
  - Existing pencil button gets `.disabled(viewModel.isDeleting)`.
  - Overlay with dimmed ProgressView while `isDeleting`.
  - `.confirmationDialog(...isPresented: $isShowingDeleteConfirm)` with destructive button triggering `confirmDelete()`.
  - `.alert("Delete failed", ...)` surfaces `viewModel.deleteErrorMessage`.
  - `private func confirmDelete() async`: captures `viewModel.projectId` pre-call, awaits `viewModel.deleteProject()`, on success fires `onProjectDeleted?(projectId)` then `dismiss()`.
  - `foundationScopeNote` copy updated: removes "project delete", adds "task_count".

### 3.3 Parity checklist

| Requirement (devprompt §6) | Delivered | Evidence |
|---|---|---|
| iOS at least one real delete entry | Yes (two) | Detail toolbar trash + list row `.contextMenu` |
| Confirmation before delete | Yes (both surfaces) | `.confirmationDialog(...role: .destructive)` + explicit "cannot be undone" message |
| Real Supabase delete (not local fake) | Yes | `.from("projects").delete().eq("id", value:).execute()` in both VMs |
| List success cleanup | Yes | `projects.removeAll { $0.id == id }` (direct) + `removeProjectLocally(id:)` (from detail) |
| Detail success cleanup | Yes | VM clears `project = nil` then view calls `dismiss()` |
| Delete failure surface | Yes | `deleteErrorMessage` → `.alert("Delete failed", ...)` |
| Loading / disabled state during delete | Yes | `isDeleting` on trash/pencil, ProgressView overlay |
| 1.5/1.6/1.7/1.8/1.9 preserved | Yes | No unrelated file modifications; access gate + membership scope paths untouched |
| Ledger updated | Yes | `findings.md` + `progress.md` + `task_plan.md` + this file |
| `.projects` still `.partial` | Yes | `AppModule.swift` unchanged; AI/risk/linked-actions/resolution/`task_count` still absent |
| Scan complete | Yes | See §4.1 below |
| Build passes | Yes | See §4.2 below |

## 4. Verification

### 4.1 Scan

Ran the devprompt §4.1 pattern across the Projects feature folder:

```bash
rg -n 'deleteProject|delete\(|project_members|ProjectDetailView|ProjectListView|toolbar|contextMenu|confirmationDialog|alert\(|isDeleting|errorMessage|reload\(|detail|dismiss|removeAll|projects|AppModule|implementationStatus' Brainstorm+/Features/Projects
```

Counts per file (foundation scope intact, no stray references):

- `ProjectMemberCandidate.swift`: 1 (unchanged 1.9 file)
- `ProjectDetailModels.swift`: 7 (unchanged)
- `ProjectListView.swift`: 35 (added contextMenu Delete + confirmationDialog + alert + removeProjectLocally wiring)
- `ProjectListViewModel.swift`: 47 (added isDeleting + deleteErrorMessage + deleteProject + removeProjectLocally)
- `ProjectEditSheet.swift`: 11 (unchanged 1.9 file)
- `ProjectDetailViewModel.swift`: 38 (added isDeleting + deleteErrorMessage + deleteProject)
- `ProjectEditViewModel.swift`: 28 (unchanged 1.9 file)
- `ProjectCardView.swift`: 1 (unchanged)
- `ProjectDetailView.swift`: 43 (added dismiss env + onProjectDeleted + isShowingDeleteConfirm + trash toolbar + confirmationDialog + alert + overlay + confirmDelete)

Total: 211 occurrences across 9 files.

### 4.2 Build

```bash
cd /Users/archiesun/Desktop/Work/BrainStorm+/BrainStorm+-App
xcodebuild build -project Brainstorm+.xcodeproj -scheme Brainstorm+ \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  CODE_SIGNING_ALLOWED=NO
```

Result: `** BUILD SUCCEEDED **`.

## 5. What 2.0 Did NOT Do (By Design)

- **AI summary / risk analysis / linked risk actions / resolution feedback** — all still web-only. 2.0 intentionally did not expand into these surfaces.
- **`task_count` on list** — still not fetched; deferred to a later round.
- **Edit-flow refactor** — 1.9's edit path is untouched except for the `.disabled(viewModel.isDeleting)` guard on the pencil button to prevent edit-vs-delete races.
- **List full reload after delete** — 2.0 uses local row removal instead, which is cheaper and correct given delete semantics. This is a deliberate divergence from Web's `await reload()` — documented in `findings.md` and mentioned as future work for the edit path.
- **Schema changes** — none. FK cascade is a pre-existing database responsibility; iOS does not re-implement it.
- **Batch delete / multi-select** — out of scope.
- **Undo / recycle-bin / recover** — out of scope. A deleted project is permanently gone from iOS (matches Web semantics).
- **Nested `NavigationStack` refactor** — the 1.3-era nested stack in `ProjectListView` is still present; the delete confirmation dialog does not compound it (lives at the list root level).

## 6. Known Debt Carried Forward

- Client-side `AccessOutcome` + enrichment rely on client-side role normalization (same caveat as 1.5 / 1.6 / 1.7 / 1.8 / 1.9). Real enforcement is Supabase RLS.
- `maybeSingle()` absent in the Swift SDK — iOS membership gate still uses `.select("id")` + empty-rows check.
- Avatar caching via `AsyncImage` doesn't persist across view lifecycle.
- Date-only decode modeled as `String` because SDK's default decoder rejects `YYYY-MM-DD`.
- Save-state cache coherence on edit still uses full reload; only delete uses local mutation.
- `filteredProjects` retained as defensive smoother.
- Assignee picker still deferred from 1.1.
- Confirmation-dialog race: `.confirmationDialog(...presenting:)` reads `projectPendingDelete` eagerly; if the underlying row gets filtered out between open and confirm, the dialog still fires against the captured project. Acceptable foundation posture.

## 7. Recommended Next Round (Hypothesis, not commitment)

- **`task_count` on list** — the next narrow, high-value Projects gap after delete foundation. Web list cards show a task count; iOS does not. Small, self-contained, honestly fits the "one narrow parity gap per round" rhythm.
- Alternatives Winston may prefer: AI summary foundation (bigger, pulls in an AI-surface shape decision), risk analysis foundation (bigger still). Both are larger than `task_count` and would represent a scope escalation.

## 8. Handoff

- Findings: `findings.md`
- Progress: `progress.md`
- Task plan: `task_plan.md`
- Winston-ready notes: this file
- Expected audit output: `docs/parity/36-winston-audit-2.0.md`

建议进入 Winston 2.0 审计.
