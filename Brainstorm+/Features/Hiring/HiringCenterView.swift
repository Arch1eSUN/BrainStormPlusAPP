import SwiftUI

// Phase 4.4 — iOS port of BrainStorm+-Web/src/app/dashboard/hiring.
// Web splits the page into four tabs (positions / candidates / contracts /
// seniority). iOS keeps the first two as full tabs and folds contracts +
// seniority into a combined "数据" tab since both are thin tables driven by
// the same backing pickers. Capability gate mirrors Web's `hr_ops` check;
// admin+ roles pick up `hr_ops` via the default capability map in
// `RBACManager.defaultCapabilities`.

public struct HiringCenterView: View {
    @Environment(SessionManager.self) private var sessionManager
    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(isEmbedded: Bool = false) {
        self.isEmbedded = isEmbedded
    }

    public enum Tab: String, CaseIterable, Identifiable {
        case candidates
        case jobs
        case data

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .candidates: return "候选人"
            case .jobs:       return "岗位"
            case .data:       return "数据"
            }
        }
    }

    @State private var selectedTab: Tab = .candidates

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    private var coreContent: some View {
        Group {
            if hasAccess {
                gateContent
            } else {
                BsEmptyState(
                    title: "无权访问",
                    systemImage: "lock",
                    description: "招聘管理需要「hr_ops」能力或 admin+ 角色。请联系管理员开通权限。"
                )
            }
        }
        .navigationTitle("招聘管理")
        .navigationBarTitleDisplayMode(.large)
    }

    private var hasAccess: Bool {
        guard let profile = sessionManager.currentProfile else { return false }
        let caps = RBACManager.shared.getEffectiveCapabilities(for: profile)
        if RBACManager.shared.hasCapability(.hr_ops, in: caps) { return true }
        let role = RBACManager.shared.migrateLegacyRole(profile.role).primaryRole
        return role == .admin || role == .superadmin
    }

    @ViewBuilder
    private var gateContent: some View {
        // Bug-fix: tab 切换时整条 picker bar 向下 "jump"。
        // Root cause: 内层子 view（HiringCandidatesView / HiringJobsView / HiringDataView）
        // 在 loading / empty 状态下只返回 ProgressView 或 BsEmptyState，没有撑满到屏幕底部，
        // VStack 不带 alignment 会把 Picker 往下推或让 navigationBar large-title collapse 失效。
        // 修法：VStack 明确 .frame(maxHeight: .infinity, alignment: .top)，让 Picker 钉顶；
        // 子内容容器在各自 view 里配合 .frame(maxWidth: .infinity, maxHeight: .infinity)。
        VStack(spacing: 0) {
            Picker("视图", selection: $selectedTab) {
                ForEach(Tab.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .onChange(of: selectedTab) { _, _ in Haptic.selection() }

            Group {
                switch selectedTab {
                case .candidates:
                    HiringCandidatesView()
                case .jobs:
                    HiringJobsView()
                case .data:
                    HiringDataView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
