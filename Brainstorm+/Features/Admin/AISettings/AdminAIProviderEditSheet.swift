import SwiftUI
import Combine

// ══════════════════════════════════════════════════════════════════
// Phase 4.6d — AI 供应商编辑 Sheet
// Parity target: Web `ai-settings-section.tsx` 的 ProviderCard 内联编辑
// iOS 端仅允许改 default_model / fallback_models（非敏感字段）
// API key 字段只展示打码，不支持在 iOS 写入（RLS + 服务端加密）
// ══════════════════════════════════════════════════════════════════

public struct AdminAIProviderEditSheet: View {
    let provider: AdminAISettingsViewModel.ProviderRow
    @ObservedObject var viewModel: AdminAISettingsViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var selectedModel: String
    @State private var fallbackText: String
    @State private var apiKeyPlaceholder: String = ""  // SecureField，仅 UI，永不提交

    public init(provider: AdminAISettingsViewModel.ProviderRow, viewModel: AdminAISettingsViewModel) {
        self.provider = provider
        self.viewModel = viewModel
        _selectedModel = State(initialValue: provider.defaultModel ?? "")
        _fallbackText = State(initialValue: provider.fallbackModels.joined(separator: ", "))
    }

    public var body: some View {
        Form {
            Section {
                LabeledContent("供应商名称", value: provider.providerName)
                LabeledContent("Base URL") {
                    Text(provider.baseUrl)
                        .font(.caption.monospaced())
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text("基础信息")
            } footer: {
                Text("基础信息只读。如需修改，请在 Web 管理端操作。")
            }

            Section {
                HStack {
                    Text("当前 KEY")
                        .foregroundStyle(BsColor.inkMuted)
                    Spacer()
                    Text(provider.maskedApiKey)
                        .font(.caption.monospaced())
                }
                SecureField("新 API Key（iOS 不支持替换）", text: $apiKeyPlaceholder)
                    .disabled(true)
                    .foregroundStyle(BsColor.inkMuted)
            } header: {
                Text("API Key")
            } footer: {
                Text("API Key 使用 AES-256-GCM 加密存储，iOS 端无法解密或替换。请前往 Web 管理端新建或替换。")
            }

            Section {
                if provider.availableModels.isEmpty {
                    Text("该供应商尚未发现可用模型，请先在 Web 端运行「发现模型」。")
                        .font(.footnote)
                        .foregroundStyle(BsColor.inkMuted)
                } else {
                    Picker("默认模型", selection: $selectedModel) {
                        Text("未选择").tag("")
                        ForEach(provider.availableModels, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                }
            } header: {
                Text("默认模型")
            }

            Section {
                TextEditor(text: $fallbackText)
                    .frame(minHeight: 80)
                    .font(.footnote.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("降级链")
            } footer: {
                Text("默认模型失败时按顺序尝试。用逗号或换行分隔。")
            }
        }
        .navigationTitle("编辑供应商")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(viewModel.isSaving ? "保存中…" : "保存") {
                    // Haptic removed: 用户反馈管理模块按钮震动过密
                    Task { await save() }
                }
                .disabled(viewModel.isSaving || !hasChanges)
            }
        }
    }

    private var parsedFallbacks: [String] {
        fallbackText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var hasChanges: Bool {
        let modelChanged = selectedModel != (provider.defaultModel ?? "")
        let fallbacksChanged = parsedFallbacks != provider.fallbackModels
        return modelChanged || fallbacksChanged
    }

    private func save() async {
        let modelChanged = selectedModel != (provider.defaultModel ?? "")
        let fallbacksChanged = parsedFallbacks != provider.fallbackModels
        if modelChanged, !selectedModel.isEmpty {
            await viewModel.setDefaultModel(providerId: provider.id, model: selectedModel)
        }
        if fallbacksChanged {
            await viewModel.saveFallbackModels(providerId: provider.id, models: parsedFallbacks)
        }
        if viewModel.errorMessage == nil {
            dismiss()
        }
    }
}
