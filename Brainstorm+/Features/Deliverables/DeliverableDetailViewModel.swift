import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 2.1 — Deliverable detail VM.
//
// Web has no dedicated detail page — the list row is editable inline.
// iOS still ships a detail screen so the list stays dense and the
// read-only fields (description, project, link, submitter) have room
// to breathe. This VM mirrors the row payload returned by
// `fetchDeliverables` (deliverables.ts:69-93) and adds a single-row
// refresh for pull-to-reload.
//
// Status updates live on `DeliverableListViewModel` and are shared by
// reference so the list updates optimistically when the detail page
// changes the row (matches how ApprovalDetailView shares its VM with
// the queue).
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class DeliverableDetailViewModel: ObservableObject {
    @Published public private(set) var deliverable: Deliverable
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isMutating: Bool = false
    @Published public var errorMessage: String?
    @Published public var successMessage: String?

    public let client: SupabaseClient
    public weak var listViewModel: DeliverableListViewModel?

    public init(
        deliverable: Deliverable,
        client: SupabaseClient,
        listViewModel: DeliverableListViewModel? = nil
    ) {
        self.deliverable = deliverable
        self.client = client
        self.listViewModel = listViewModel
    }

    /// Hand-off to `DeliverableListViewModel.deleteDeliverable`. Returns
    /// `true` on success so the detail view can dismiss itself. Falls
    /// back to a direct `.delete()` + activity-log write if the detail
    /// view is opened standalone (no list VM attached).
    @discardableResult
    public func deleteCurrent() async -> Bool {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        if let list = listViewModel {
            let ok = await list.deleteDeliverable(id: deliverable.id)
            if !ok { self.errorMessage = list.errorMessage }
            return ok
        }

        // Standalone path.
        let priorTitle = deliverable.title
        do {
            try await client
                .from("deliverables")
                .delete()
                .eq("id", value: deliverable.id.uuidString)
                .execute()
            await ActivityLogWriter.write(
                client: client,
                type: .system,
                action: "delete_deliverable",
                description: "删除了交付物「\(priorTitle)」",
                entityType: "deliverable",
                entityId: deliverable.id
            )
            Haptic.rigid()
            successMessage = "交付物已删除"
            return true
        } catch {
            Haptic.warning()
            errorMessage = ErrorLocalizer.localize(error)
            return false
        }
    }

    /// Adopt a freshly-updated row (e.g. after the edit sheet saves).
    public func apply(_ fresh: Deliverable) {
        self.deliverable = fresh
    }

    public func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fresh: Deliverable = try await client
                .from("deliverables")
                .select(
                    """
                    id, title, description, url, status,
                    project_id, assignee_id, org_id,
                    due_date, submitted_at, file_url,
                    created_at, updated_at,
                    projects:project_id(id, name),
                    profiles:assignee_id(id, full_name, avatar_url)
                    """
                )
                .eq("id", value: deliverable.id.uuidString)
                .single()
                .execute()
                .value
            self.deliverable = fresh
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    /// Transitions the row's status. Delegates to the list VM so the
    /// list + detail stay in sync; falls back to a direct update if
    /// the detail view is opened without a list parent.
    public func updateStatus(_ status: Deliverable.DeliverableStatus) async {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        if let list = listViewModel {
            let ok = await list.updateStatus(id: deliverable.id, to: status)
            if ok, let refreshed = list.items.first(where: { $0.id == deliverable.id }) {
                self.deliverable = refreshed
                self.successMessage = "状态已更新"
            } else if !ok {
                self.errorMessage = list.errorMessage
            }
            return
        }

        // Standalone path (e.g. detail deep-linked from a notification).
        let nowISO = ISO8601DateFormatter().string(from: Date())
        struct Payload: Encodable {
            let status: String
            let submittedAt: String?
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case status
                case submittedAt = "submitted_at"
                case updatedAt = "updated_at"
            }
        }
        let payload = Payload(
            status: status.rawValue,
            submittedAt: status == .submitted ? nowISO : nil,
            updatedAt: nowISO
        )

        do {
            let updated: Deliverable = try await client
                .from("deliverables")
                .update(payload)
                .eq("id", value: deliverable.id.uuidString)
                .select(
                    """
                    id, title, description, url, status,
                    project_id, assignee_id, org_id,
                    due_date, submitted_at, file_url,
                    created_at, updated_at,
                    projects:project_id(id, name),
                    profiles:assignee_id(id, full_name, avatar_url)
                    """
                )
                .single()
                .execute()
                .value
            self.deliverable = updated
            self.successMessage = "状态已更新"
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }
}
