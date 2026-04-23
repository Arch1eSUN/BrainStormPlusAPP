import SwiftUI
import Combine

// ══════════════════════════════════════════════════════════════════
// Phase 4.6d — AI 设置主视图
// Parity target: Web `components/settings/ai-settings-section.tsx`
// iOS 形态：Form + Section 分区（激活 / 列表 / 月度评分 / 安全说明）
//
// 安全降级：
//   · api_key 列始终是服务端 AES-256-GCM 密文，iOS 无法解密
//   · 因此 iOS 只展示打码（••••last4），无「查看原文」按钮
//   · 新建/替换 API key → 提示 "请在 Web 管理端修改"，不在 iOS 发起
//   · 可在 iOS 调整：is_active / default_model / fallback_models /
//     evaluations 月度配置
// ══════════════════════════════════════════════════════════════════

public struct AdminAISettingsView: View {
    @StateObject private var vm = AdminAISettingsViewModel()
    @State private var editingProvider: AdminAISettingsViewModel.ProviderRow?
    @State private var pendingDelete: AdminAISettingsViewModel.ProviderRow?

    public init() {}

    public var body: some View {
        Form {
            activeSection
            providersSection
            evaluationSection
            securityNoticeSection
        }
        .navigationTitle("AI 设置")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .zyErrorBanner($vm.errorMessage)
        .overlay(alignment: .top) {
            if let info = vm.infoMessage {
                infoBanner(info)
                    .task(id: info) {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        if vm.infoMessage == info { vm.infoMessage = nil }
                    }
            }
        }
        .sheet(item: $editingProvider) { provider in
            NavigationStack {
                AdminAIProviderEditSheet(provider: provider, viewModel: vm)
            }
        }
        .confirmationDialog(
            pendingDelete.map { "删除供应商 \($0.providerName)？此操作不可撤销。" } ?? "",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let p = pendingDelete {
                    Task { await vm.deleteProvider(providerId: p.id); pendingDelete = nil }
                }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    // ── Section: 当前激活 provider ──
    @ViewBuilder
    private var activeSection: some View {
        Section {
            if vm.isLoading {
                HStack { ProgressView(); Text("加载中…").foregroundStyle(.secondary) }
            } else if let p = vm.activeProvider {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(BsColor.success)
                        Text(p.providerName)
                            .font(.headline)
                        Spacer()
                        Text("已启用")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(BsColor.success.opacity(0.12)))
                            .foregroundStyle(BsColor.success)
                    }
                    if let model = p.defaultModel, !model.isEmpty {
                        Text("默认模型：\(model)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未设默认模型")
                            .font(.footnote)
                            .foregroundStyle(BsColor.warning)
                    }
                    if !p.fallbackModels.isEmpty {
                        Text("降级链：\(p.fallbackModels.joined(separator: " → "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("尚未启用任何 AI 供应商")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("当前激活")
        } footer: {
            Text("AI 调用将优先使用该供应商的默认模型；失败时按降级链顺序重试。")
        }
    }

    // ── Section: providers 列表 ──
    @ViewBuilder
    private var providersSection: some View {
        Section {
            if vm.providers.isEmpty, !vm.isLoading {
                Text("尚未配置任何 AI 供应商。请在 Web 管理端新增。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(vm.providers) { p in
                providerRow(p)
            }
        } header: {
            Text("所有供应商 (\(vm.providers.count))")
        }
    }

    @ViewBuilder
    private func providerRow(_ p: AdminAISettingsViewModel.ProviderRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(p.providerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BsColor.ink)
                Spacer()
                Circle()
                    .fill(p.isActive ? BsColor.success : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(p.isActive ? "已启用" : "已停用")
                    .font(.caption2)
                    .foregroundStyle(p.isActive ? BsColor.success : .secondary)
            }
            Text(p.baseUrl)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                Text("API KEY")
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(p.maskedApiKey)
                    .font(.caption.monospaced())
                    .foregroundStyle(BsColor.ink)
            }
            if let model = p.defaultModel, !model.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "cpu").font(.caption2)
                    Text(model).font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button {
                    Task { await vm.toggleActive(providerId: p.id, to: !p.isActive) }
                } label: {
                    Label(p.isActive ? "停用" : "启用",
                          systemImage: p.isActive ? "pause.circle" : "play.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(vm.isSaving)

                Button {
                    editingProvider = p
                } label: {
                    Label("模型 / 降级链", systemImage: "slider.horizontal.3")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(vm.isSaving)

                Spacer()

                Button(role: .destructive) {
                    pendingDelete = p
                } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(vm.isSaving)
            }
        }
        .padding(.vertical, 4)
    }

    // ── Section: 月度评分 limits ──
    @ViewBuilder
    private var evaluationSection: some View {
        Section {
            Toggle("启用月度自动评分", isOn: Binding(
                get: { vm.evalConfig.enabled },
                set: { newValue in Task { await vm.saveEvaluationEnabled(newValue) } }
            ))
            .disabled(vm.isSaving)

            Stepper(value: Binding(
                get: { vm.evalConfig.day },
                set: { newValue in Task { await vm.saveEvaluationDay(newValue) } }
            ), in: 1...28) {
                HStack {
                    Text("执行日期")
                    Spacer()
                    Text("每月 \(vm.evalConfig.day) 日")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(vm.isSaving || !vm.evalConfig.enabled)

            Stepper(value: Binding(
                get: { vm.evalConfig.hour },
                set: { newValue in Task { await vm.saveEvaluationHour(newValue) } }
            ), in: 0...23) {
                HStack {
                    Text("执行时间")
                    Spacer()
                    Text(String(format: "%02d:00", vm.evalConfig.hour))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(vm.isSaving || !vm.evalConfig.enabled)
        } header: {
            Text("AI 月度评分")
        } footer: {
            Text("仅超管可调。关闭时管理员仍可在成员详情页手动触发评分。")
        }
    }

    // ── Section: 安全说明 ──
    @ViewBuilder
    private var securityNoticeSection: some View {
        Section {
            Label("API Key 始终加密存储，iOS 端仅显示打码。",
                  systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label("新建供应商或替换 API Key 请在 Web 管理端操作。",
                  systemImage: "safari")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("安全说明")
        }
    }

    // ── Info banner ──
    private func infoBanner(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(
                Capsule().fill(BsColor.success)
            )
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
