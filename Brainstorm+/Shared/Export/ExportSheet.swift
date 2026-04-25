import SwiftUI
import UniformTypeIdentifiers
import Supabase
import Auth

// ══════════════════════════════════════════════════════════════════
// ExportSheet — Iter 6 §B.7 数据导出
//
// 通用导出弹窗，每个 list view 通过 toolbar 菜单触发。流程:
//   1. 用户选择起始/结束日期
//   2. 调用 GET <web>/api/export/<module>?from&to&format=csv
//      头部带 Bearer access_token —— Web 端会用 RLS 过滤
//   3. CSV 落盘 → 弹 ShareSheet 让用户分享 / 保存到 Files
//
// Web 端 RLS 自动按调用者权限过滤：员工本人，admin 全员。
// ══════════════════════════════════════════════════════════════════

public struct ExportSheet: View {
    public enum Module: String {
        case tasks
        case approvals
        case dailyLogs = "daily-logs"
        case weeklyReports = "weekly-reports"
        case attendance

        var cnLabel: String {
            switch self {
            case .tasks: return "任务"
            case .approvals: return "审批"
            case .dailyLogs: return "日报"
            case .weeklyReports: return "周报"
            case .attendance: return "考勤"
            }
        }
    }

    public let module: Module

    @Environment(\.dismiss) private var dismiss

    @State private var fromDate: Date
    @State private var toDate: Date
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var exportedFileURL: URL?
    @State private var isShowingShareSheet = false

    public init(module: Module) {
        self.module = module
        let today = Date()
        let cal = Calendar.current
        _toDate = State(initialValue: today)
        _fromDate = State(initialValue: cal.date(byAdding: .day, value: -90, to: today) ?? today)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "起始日期",
                        selection: $fromDate,
                        in: ...toDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "结束日期",
                        selection: $toDate,
                        in: fromDate...,
                        displayedComponents: .date
                    )
                } header: {
                    Text("日期范围")
                } footer: {
                    Text("范围按你的权限自动过滤——普通员工仅本人记录，管理员可导出全员（受 RLS 保护）。")
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await performExport() }
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView().padding(.trailing, 6)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text(isExporting ? "导出中…" : "导出 CSV")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting || fromDate > toDate)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("导出\(module.cnLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingShareSheet, onDismiss: {
                // Auto-close after share to keep stack tidy.
                dismiss()
            }) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    // MARK: - Export

    private func performExport() async {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let token = try await currentAccessToken()
            let url = try buildExportURL()

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("text/csv", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw ExportError.transport("无效响应")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ExportError.server("HTTP \(http.statusCode): \(body)")
            }

            let filename = filenameFrom(response: http) ?? defaultFilename()
            let fileURL = try writeToTemp(data: data, filename: filename)

            await MainActor.run {
                self.exportedFileURL = fileURL
                self.isShowingShareSheet = true
            }
        } catch {
            await MainActor.run {
                self.errorMessage = (error as? ExportError)?.message ?? error.localizedDescription
            }
        }
    }

    private func currentAccessToken() async throws -> String {
        let session = try await supabase.auth.session
        return session.accessToken
    }

    private func buildExportURL() throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let from = formatter.string(from: fromDate)
        let to = formatter.string(from: toDate)

        var comps = URLComponents(
            url: AppEnvironment.webAPIBaseURL.appendingPathComponent("/api/export/\(module.rawValue)"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "format", value: "csv"),
        ]
        guard let url = comps?.url else {
            throw ExportError.transport("URL 构建失败")
        }
        return url
    }

    private func filenameFrom(response: HTTPURLResponse) -> String? {
        guard let cd = response.value(forHTTPHeaderField: "Content-Disposition") else { return nil }
        // filename="tasks-2026-04-25.csv"
        guard let range = cd.range(of: #"filename=\"([^\"]+)\""#, options: .regularExpression) else {
            return nil
        }
        let match = String(cd[range])
        if let inner = match.range(of: #"\"([^\"]+)\""#, options: .regularExpression) {
            return String(match[inner]).replacingOccurrences(of: "\"", with: "")
        }
        return nil
    }

    private func defaultFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "\(module.rawValue)-\(f.string(from: Date())).csv"
    }

    private func writeToTemp(data: Data, filename: String) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("brainstorm-exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let url = tmpDir.appendingPathComponent(filename)
        // Overwrite if exists
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Errors

    private enum ExportError: Error {
        case transport(String)
        case server(String)

        var message: String {
            switch self {
            case .transport(let s): return "网络错误: \(s)"
            case .server(let s): return "服务器错误: \(s)"
            }
        }
    }
}

// MARK: - ShareSheet wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
