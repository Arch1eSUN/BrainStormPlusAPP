import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Batch C.4d — Settings → 通知偏好 (SwiftUI Form mirror of Web)
//
// Parity with `/dashboard/settings/notifications`:
//   - Section 1 (通知渠道): 浏览器通知 + 邮件通知
//     iOS 将 "浏览器通知" 渲染为 "推送通知" — 移动端语义一致，
//     底层还是同一个 `push_notifications` 列。
//     Web 的 enablePush()/disablePush() 走 VAPID 订阅 — 移动端走 APNs
//     由系统配置决定，这里只管数据库偏好开关（和 Web 一致，存进 user_settings）。
//   - Section 2 (通知类型): mention / approval / task / broadcast / attendance
//   - Section 3 (免打扰时段): enabled + start/end (HH:MM)
// ══════════════════════════════════════════════════════════════════

public struct SettingsNotificationsView: View {
    @StateObject private var viewModel = SettingsNotificationsViewModel()

    // TODO: promote to BsMotion.bannerDuration when Shared editing allowed
    private static let toastDuration: TimeInterval = 2.2

    public init() {}

    public var body: some View {
        ZStack {
            BsColor.pageBackground.ignoresSafeArea()

            Form {
                channelsSection
                typesSection
                quietHoursSection

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(BsTypography.bodySmall)
                            .foregroundStyle(BsColor.warning)
                    }
                }

                Section {
                    saveButton
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("通知偏好")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if viewModel.savedSuccessfully {
                savedBanner
                    .padding(.top, BsSpacing.sm)
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var channelsSection: some View {
        Section {
            Toggle(isOn: $viewModel.pushNotifications) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("推送通知")
                        .font(BsTypography.bodyMedium)
                        .foregroundStyle(BsColor.ink)
                    Text("在设备上弹出实时通知")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                .accessibilityElement(children: .combine)
            }
            .tint(BsColor.brandAzure)
            .onChange(of: viewModel.pushNotifications) { _, _ in Haptic.light() }

            Toggle(isOn: $viewModel.emailNotifications) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("邮件通知")
                        .font(BsTypography.bodyMedium)
                        .foregroundStyle(BsColor.ink)
                    Text("重要事件通过邮件抄送")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                .accessibilityElement(children: .combine)
            }
            .tint(BsColor.brandAzure)
            .onChange(of: viewModel.emailNotifications) { _, _ in Haptic.light() }
        } header: {
            Text("通知渠道")
        } footer: {
            Text("控制系统是否向你的设备或邮箱推送通知。")
        }
    }

    @ViewBuilder
    private var typesSection: some View {
        Section {
            typeToggle(
                key: .mention,
                title: "@提及",
                description: "他人在聊天或评论中 @ 我时"
            )
            typeToggle(
                key: .approval,
                title: "审批结果",
                description: "发起的审批被批准 / 驳回"
            )
            typeToggle(
                key: .task,
                title: "任务分配",
                description: "新任务指派给我或有更新"
            )
            typeToggle(
                key: .broadcast,
                title: "系统广播",
                description: "管理员向全员发布的通知"
            )
            typeToggle(
                key: .attendance,
                title: "考勤异常",
                description: "打卡 / 迟到 / 加班等异常事件"
            )
        } header: {
            Text("通知类型")
        } footer: {
            Text("细粒度控制你希望收到哪些类别的通知。关闭后将不再产生对应通知。")
        }
    }

    @ViewBuilder
    private func typeToggle(
        key: NotificationTypeKey,
        title: String,
        description: String
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { viewModel.preferences.types[key] },
                set: {
                    viewModel.preferences.types[key] = $0
                    Haptic.light()
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.ink)
                Text(description)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
            }
            .accessibilityElement(children: .combine)
        }
        .tint(BsColor.brandAzure)
    }

    @ViewBuilder
    private var quietHoursSection: some View {
        Section {
            Toggle(isOn: $viewModel.preferences.quietHours.enabled) {
                Text("启用免打扰")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.ink)
            }
            .tint(BsColor.brandAzure)
            .onChange(of: viewModel.preferences.quietHours.enabled) { _, _ in Haptic.light() }

            if viewModel.preferences.quietHours.enabled {
                timePickerRow(
                    title: "开始时间",
                    value: Binding(
                        get: { viewModel.preferences.quietHours.start },
                        set: { viewModel.preferences.quietHours.start = $0 }
                    )
                )
                timePickerRow(
                    title: "结束时间",
                    value: Binding(
                        get: { viewModel.preferences.quietHours.end },
                        set: { viewModel.preferences.quietHours.end = $0 }
                    )
                )
            }
        } header: {
            Text("免打扰时段")
        } footer: {
            Text("在此时段内不会推送通知；重要消息仍会进入通知列表。跨日区间（如 22:00 – 08:00）自动识别为次日凌晨结束。")
        }
    }

    @ViewBuilder
    private func timePickerRow(title: String, value: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(BsTypography.bodyMedium)
                .foregroundStyle(BsColor.ink)
            Spacer()
            DatePicker(
                "",
                selection: Binding(
                    get: { Self.dateFromHHMM(value.wrappedValue) },
                    set: { value.wrappedValue = Self.hhmmFromDate($0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
    }

    // MARK: - Save button

    @ViewBuilder
    private var saveButton: some View {
        Button {
            Haptic.medium()
            Task {
                await viewModel.save()
                if viewModel.savedSuccessfully {
                    Haptic.success()
                }
            }
        } label: {
            HStack(spacing: BsSpacing.sm + 2) {
                if viewModel.isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                }
                Text(viewModel.isSaving ? "保存中..." : "保存")
            }
        }
        .buttonStyle(BsPrimaryButtonStyle(size: .large, isLoading: viewModel.isSaving))
        .disabled(viewModel.isSaving || viewModel.isLoading)
        .padding(.horizontal, BsSpacing.lg + 4)
        .padding(.vertical, BsSpacing.sm)
    }

    @ViewBuilder
    private var savedBanner: some View {
        HStack(spacing: BsSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(BsColor.success)
            Text("通知偏好已保存")
                .font(BsTypography.bodySmall)
                .foregroundStyle(BsColor.success)
        }
        .padding(.horizontal, BsSpacing.lg)
        .padding(.vertical, BsSpacing.sm + 2)
        .background(
            Capsule().fill(BsColor.success.opacity(0.12))
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .task {
            // TODO: promote to BsMotion.bannerDuration when Shared editing allowed
            try? await Task.sleep(for: .seconds(Self.toastDuration))
            viewModel.savedSuccessfully = false
        }
    }

    // MARK: - HH:MM <-> Date helpers

    private static let hhmmFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func dateFromHHMM(_ s: String) -> Date {
        hhmmFormatter.date(from: s) ?? hhmmFormatter.date(from: "22:00") ?? Date()
    }

    private static func hhmmFromDate(_ d: Date) -> String {
        hhmmFormatter.string(from: d)
    }
}

#Preview {
    NavigationStack {
        SettingsNotificationsView()
    }
}
