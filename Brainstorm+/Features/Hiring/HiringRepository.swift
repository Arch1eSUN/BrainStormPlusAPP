import Foundation
import Supabase

// Parity target: BrainStorm+-Web/src/lib/actions/hiring/*.
// Web gates every call with `ensureHiringAccess()` (hr_ops). iOS mirrors
// the gate at the view layer (HiringCenterView) and trusts RLS to enforce
// at the DB. Server actions that ran as admin on Web are emulated here
// as direct PostgREST writes under the user JWT — RLS policies on
// job_positions / candidates / contracts / seniority_records already
// grant insert/update/delete to hr_ops / admin+ roles.

@MainActor
public final class HiringRepository {
    public static let shared = HiringRepository()

    private init() {}

    private var client: SupabaseClient { supabase }

    // MARK: - Job positions

    public func fetchJobPositions(search: String?) async throws -> [JobPosition] {
        var builder = client.from("job_positions").select()
        if let s = escapedSearch(search) {
            builder = builder.or("title.ilike.%\(s)%,department.ilike.%\(s)%")
        }
        return try await builder
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    public func createJobPosition(
        title: String,
        department: String?,
        description: String?,
        requirements: String?,
        salaryRange: String?,
        employmentType: JobPosition.EmploymentType
    ) async throws {
        let payload = JobPositionInsertPayload(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            department: nullIfBlank(department),
            description: nullIfBlank(description),
            requirements: nullIfBlank(requirements),
            salaryRange: nullIfBlank(salaryRange),
            employmentType: employmentType.rawValue
        )
        try await client.from("job_positions").insert(payload).execute()
    }

    public func updateJobPosition(
        id: UUID,
        title: String,
        department: String?,
        description: String?,
        requirements: String?,
        salaryRange: String?,
        employmentType: JobPosition.EmploymentType,
        status: JobPosition.PositionStatus
    ) async throws {
        let payload = JobPositionUpdatePayload(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            department: nullIfBlank(department),
            description: nullIfBlank(description),
            requirements: nullIfBlank(requirements),
            salaryRange: nullIfBlank(salaryRange),
            employmentType: employmentType.rawValue,
            status: status.rawValue
        )
        try await client.from("job_positions")
            .update(payload)
            .eq("id", value: id.uuidString)
            .execute()
    }

    public func deleteJobPosition(id: UUID) async throws {
        try await client.from("job_positions")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Candidates

    public func fetchCandidates(search: String?) async throws -> [Candidate] {
        var builder = client.from("candidates")
            .select("*, job_positions(title)")
        if let s = escapedSearch(search) {
            builder = builder.or("full_name.ilike.%\(s)%,email.ilike.%\(s)%")
        }
        return try await builder
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    public func createCandidate(
        fullName: String,
        email: String?,
        phone: String?,
        positionId: UUID?,
        resumeText: String?,
        resumeUrl: String?,
        notes: String?
    ) async throws {
        let payload = CandidateInsertPayload(
            fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            email: nullIfBlank(email),
            phone: nullIfBlank(phone),
            positionId: positionId?.uuidString,
            resumeText: nullIfBlank(resumeText),
            resumeUrl: nullIfBlank(resumeUrl),
            notes: nullIfBlank(notes)
        )
        try await client.from("candidates").insert(payload).execute()
    }

    public func updateCandidate(
        id: UUID,
        fullName: String?,
        email: String?,
        phone: String?,
        positionId: UUID?,
        resumeText: String?,
        resumeUrl: String?,
        notes: String?,
        status: Candidate.CandidateStatus?
    ) async throws {
        let payload = CandidateUpdatePayload(
            fullName: fullName?.trimmingCharacters(in: .whitespacesAndNewlines),
            email: nullIfBlank(email),
            phone: nullIfBlank(phone),
            positionId: positionId?.uuidString,
            resumeText: nullIfBlank(resumeText),
            resumeUrl: nullIfBlank(resumeUrl),
            notes: nullIfBlank(notes),
            status: status?.rawValue
        )
        try await client.from("candidates")
            .update(payload)
            .eq("id", value: id.uuidString)
            .execute()
    }

    public func updateCandidateStatus(id: UUID, status: Candidate.CandidateStatus) async throws {
        struct StatusPayload: Encodable { let status: String }
        try await client.from("candidates")
            .update(StatusPayload(status: status.rawValue))
            .eq("id", value: id.uuidString)
            .execute()
    }

    public func deleteCandidate(id: UUID) async throws {
        try await client.from("candidates")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Helpers

    private func escapedSearch(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw.replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func nullIfBlank(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }
}

// MARK: - Encodable payloads

private struct JobPositionInsertPayload: Encodable {
    let title: String
    let department: String?
    let description: String?
    let requirements: String?
    let salaryRange: String?
    let employmentType: String

    enum CodingKeys: String, CodingKey {
        case title
        case department
        case description
        case requirements
        case salaryRange = "salary_range"
        case employmentType = "employment_type"
    }
}

private struct JobPositionUpdatePayload: Encodable {
    let title: String
    let department: String?
    let description: String?
    let requirements: String?
    let salaryRange: String?
    let employmentType: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case title
        case department
        case description
        case requirements
        case salaryRange = "salary_range"
        case employmentType = "employment_type"
        case status
    }
}

private struct CandidateInsertPayload: Encodable {
    let fullName: String
    let email: String?
    let phone: String?
    let positionId: String?
    let resumeText: String?
    let resumeUrl: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case email
        case phone
        case positionId = "position_id"
        case resumeText = "resume_text"
        case resumeUrl = "resume_url"
        case notes
    }
}

private struct CandidateUpdatePayload: Encodable {
    let fullName: String?
    let email: String?
    let phone: String?
    let positionId: String?
    let resumeText: String?
    let resumeUrl: String?
    let notes: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case email
        case phone
        case positionId = "position_id"
        case resumeText = "resume_text"
        case resumeUrl = "resume_url"
        case notes
        case status
    }
}
