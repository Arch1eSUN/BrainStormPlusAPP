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
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(BsTypography.outfit(18, weight: "SemiBold"))
                        .foregroundColor(BsColor.ink)
                        .lineLimit(2)

                    if let description = project.description, !description.isEmpty {
                        Text(description)
                            .font(BsTypography.inter(13, weight: "Regular"))
                            .foregroundColor(BsColor.inkMuted)
                            .lineLimit(2)
                    }

                    if let byline = ownerByline {
                        HStack(spacing: 6) {
                            // 1.8: render the owner avatar when `avatar_url` is present; falls
                            // through to an SF-symbol placeholder for nil / invalid / load-failure.
                            avatarView(urlString: owner?.avatarUrl, diameter: 16)
                            Text(byline)
                                .font(BsTypography.inter(11, weight: "Medium"))
                                .foregroundColor(BsColor.inkMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Spacer()

                statusBadge
            }

            HStack(spacing: BsSpacing.md) {
                if let endDate = project.endDate {
                    Label(Self.dateFormatter.string(from: endDate), systemImage: "calendar")
                        .font(BsTypography.captionSmall)
                        .foregroundColor(BsColor.inkMuted)
                }

                // 2.1: task count read from the list VM's batched `tasks` aggregate. Hidden
                // when `taskCount == nil` so a failed / pending hydrate doesn't render a
                // misleading "0 tasks". A resolved `0` IS rendered so users can see a
                // project genuinely has no tasks.
                if let taskCount {
                    Label(Self.taskCountLabel(taskCount), systemImage: "checklist")
                        .font(BsTypography.captionSmall)
                        .foregroundColor(BsColor.inkMuted)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("\(project.progress)%")
                        .font(BsTypography.inter(12, weight: "SemiBold"))
                        .foregroundColor(BsColor.brandAzure)

                    ProgressView(value: Double(min(max(project.progress, 0), 100)) / 100.0)
                        .progressViewStyle(.linear)
                        .tint(BsColor.brandAzure)
                        .frame(width: 80)
                }
            }
        }
        .padding(BsSpacing.lg)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
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
            .font(BsTypography.inter(11, weight: "SemiBold"))
            .padding(.horizontal, BsSpacing.md - 2)
            .padding(.vertical, 5)
            .background(bg)
            .foregroundColor(fg)
            .clipShape(Capsule())
    }

    // D.2a: Chinese labels matching Web STATUS_CFG.
    private static func statusStyle(for status: Project.ProjectStatus) -> (String, Color, Color) {
        switch status {
        case .planning:
            return ("规划中", BsColor.brandAzure, BsColor.brandAzureLight)
        case .active:
            return ("进行中", .white, BsColor.brandAzure)
        case .onHold:
            return ("暂停", BsColor.brandCoral, BsColor.brandCoral.opacity(0.15))
        case .completed:
            return ("已完成", BsColor.inkMuted, BsColor.inkFaint.opacity(0.2))
        case .archived:
            return ("归档", BsColor.inkMuted, BsColor.inkFaint.opacity(0.15))
        }
    }

    /// D.2a: Chinese units, no pluralization needed.
    private static func taskCountLabel(_ count: Int) -> String {
        "\(count) 个任务"
    }

    // D.2a: Chinese date format matching Web `toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' })`.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        f.locale = Locale(identifier: "zh_CN")
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
            .overlay(Circle().stroke(BsColor.brandAzureLight.opacity(0.35), lineWidth: 0.5))
        } else {
            avatarPlaceholder
                .frame(width: diameter, height: diameter)
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(BsColor.inkMuted.opacity(0.8))
    }
}
