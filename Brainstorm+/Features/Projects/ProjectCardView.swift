import SwiftUI

public struct ProjectCardView: View {
    public let project: Project
    /// 1.7: optional owner summary resolved by `ProjectListViewModel.ownersById`.
    /// `nil` means owner wasn't resolved yet, owner is missing on the row, or the owner
    /// batch fetch failed — we fall back to the raw UUID (or hide the byline if the
    /// project itself has no owner) so the card never goes completely ownerless.
    public let owner: ProjectOwnerSummary?

    /// 2.1: optional task count from the list VM's batched `tasks` aggregate. `nil` means
    /// "count not yet fetched" or "count fetch failed" — in either case the card hides the
    /// count line rather than showing a stale or zeroed value. A resolved `0` is rendered
    /// as "0 tasks" so users can see a project genuinely has no tasks.
    public let taskCount: Int?

    public init(project: Project, owner: ProjectOwnerSummary? = nil, taskCount: Int? = nil) {
        self.project = project
        self.owner = owner
        self.taskCount = taskCount
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(.custom("Outfit-SemiBold", size: 18))
                        .foregroundColor(Color.Brand.text)
                        .lineLimit(2)

                    if let description = project.description, !description.isEmpty {
                        Text(description)
                            .font(.custom("Inter-Regular", size: 13))
                            .foregroundColor(Color.Brand.textSecondary)
                            .lineLimit(2)
                    }

                    if let byline = ownerByline {
                        HStack(spacing: 6) {
                            // 1.8: render the owner avatar when `avatar_url` is present; falls
                            // through to an SF-symbol placeholder for nil / invalid / load-failure.
                            avatarView(urlString: owner?.avatarUrl, diameter: 16)
                            Text(byline)
                                .font(.custom("Inter-Medium", size: 11))
                                .foregroundColor(Color.Brand.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Spacer()

                statusBadge
            }

            HStack(spacing: 12) {
                if let endDate = project.endDate {
                    Label(Self.dateFormatter.string(from: endDate), systemImage: "calendar")
                        .font(.custom("Inter-Medium", size: 12))
                        .foregroundColor(Color.Brand.textSecondary)
                }

                // 2.1: task count read from the list VM's batched `tasks` aggregate. Hidden
                // when `taskCount == nil` so a failed / pending hydrate doesn't render a
                // misleading "0 tasks". A resolved `0` IS rendered so users can see a
                // project genuinely has no tasks.
                if let taskCount {
                    Label(Self.taskCountLabel(taskCount), systemImage: "checklist")
                        .font(.custom("Inter-Medium", size: 12))
                        .foregroundColor(Color.Brand.textSecondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("\(project.progress)%")
                        .font(.custom("Inter-SemiBold", size: 12))
                        .foregroundColor(Color.Brand.primary)

                    ProgressView(value: Double(min(max(project.progress, 0), 100)) / 100.0)
                        .progressViewStyle(.linear)
                        .tint(Color.Brand.primary)
                        .frame(width: 80)
                }
            }
        }
        .padding(16)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    /// Owner byline shown under the title. Priority:
    ///  1. `owner.fullName` (joined profile from Web parity query)
    ///  2. raw UUID (so the card still surfaces ownership when join fails / hasn't loaded)
    ///  3. nil — project truly has no owner_id, hide the byline
    private var ownerByline: String? {
        if let name = owner?.fullName, !name.isEmpty { return name }
        if let ownerId = project.ownerId { return ownerId.uuidString }
        return nil
    }

    private var statusBadge: some View {
        let (label, fg, bg) = Self.statusStyle(for: project.status)
        return Text(label)
            .font(.custom("Inter-SemiBold", size: 11))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bg)
            .foregroundColor(fg)
            .clipShape(Capsule())
    }

    private static func statusStyle(for status: Project.ProjectStatus) -> (String, Color, Color) {
        switch status {
        case .planning:
            return ("Planning", Color.Brand.primary, Color.Brand.primaryLight)
        case .active:
            return ("Active", .white, Color.Brand.primary)
        case .onHold:
            return ("On Hold", Color.Brand.warning, Color.Brand.warning.opacity(0.15))
        case .completed:
            return ("Completed", Color.Brand.textSecondary, Color.gray.opacity(0.15))
        case .archived:
            return ("Archived", Color.Brand.textSecondary, Color.gray.opacity(0.10))
        }
    }

    /// "0 tasks" / "1 task" / "N tasks" with simple English pluralization. Foundation-scope
    /// copy — locale-aware pluralization is future work once iOS picks up i18n.
    private static func taskCountLabel(_ count: Int) -> String {
        count == 1 ? "1 task" : "\(count) tasks"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// SwiftUI-native `AsyncImage` with robust fallbacks:
    /// - nil / empty / invalid URL → `person.crop.circle.fill` placeholder
    /// - load failure or in-flight → same placeholder (avatar failure MUST NOT propagate
    ///   into a visible error state; this is purely decorative metadata)
    @ViewBuilder
    private func avatarView(urlString: String?, diameter: CGFloat) -> some View {
        if let s = urlString, !s.isEmpty, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    avatarPlaceholder
                @unknown default:
                    avatarPlaceholder
                }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.Brand.primaryLight.opacity(0.35), lineWidth: 0.5))
        } else {
            avatarPlaceholder
                .frame(width: diameter, height: diameter)
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(Color.Brand.textSecondary.opacity(0.7))
    }
}
