import Foundation
import Combine
import Supabase

public struct AppEnvironment {
    public static let supabaseURL = URL(string: "https://scaicmjprkqlkpagbnbh.supabase.co")!
    public static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNjYWljbWpwcmtxbGtwYWdibmJoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyODU1MDgsImV4cCI6MjA4OTg2MTUwOH0.6K6yKMkkH9D-XsZmMdBk4tRsl5X6b3V4uVmYLP_lkaQ"

    // BrainStorm+ Web API base URL. 用于调用 Next.js 侧 API route（mobile/attendance、AI chat 等）。
    //
    // RELEASE：固定走 zyoffice.me 自定义域名（Vercel 托管）。
    // DEBUG：默认也走 zyoffice.me，避免开发者忘开 `next dev` 时
    //        AI 分析等模块直接报 "could not connect to the server"。
    //        若需调本地服务器，运行前在 scheme env 设
    //          BS_USE_LOCAL_DEV=1
    //        或在 UserDefaults 写 `BSUseLocalDev = true` (`defaults write` /
    //        Settings) 即可切到 http://127.0.0.1:3000。
    public static let webAPIBaseURL: URL = {
        let production = URL(string: "https://www.zyoffice.me")!
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let useLocal =
            env["BS_USE_LOCAL_DEV"] == "1" ||
            UserDefaults.standard.bool(forKey: "BSUseLocalDev")
        if useLocal {
            return URL(string: "http://127.0.0.1:3000")!
        }
        return production
        #else
        return production
        #endif
    }()
}

// ══════════════════════════════════════════════════════════════════
// Supabase client —— 自定义 decoder 兼容多日期格式
//
// 默认 iso8601 无法解码：
//   • YYYY-MM-DD (如 daily_logs.date / schedules.date / leaves.start_date)
//   • Postgres timestamptz 带微秒 "2026-04-24T01:23:45.678+00:00"
//   • 纯日期无时区
//
// 自定义 decoder 按顺序尝试多格式，失败时抛错。
// Encoder 同步改，保证写入兼容。
// ══════════════════════════════════════════════════════════════════

private func makeSupabaseDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)

        // 1. ISO8601 带/不带 fractional seconds
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso1.date(from: s) { return d }

        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        if let d = iso2.date(from: s) { return d }

        // 2. 纯日期 YYYY-MM-DD
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"
        if let d = df.date(from: s) { return d }

        // 3. Postgres timestamp without timezone "2026-04-24 01:23:45"
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = df.date(from: s) { return d }

        // 4. Postgres timestamptz space-separated "2026-04-24 01:23:45+00"
        df.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        if let d = df.date(from: s) { return d }

        // 5. 带 fractional "2026-04-24 01:23:45.678+00"
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
        if let d = df.date(from: s) { return d }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "无法识别的日期格式: \(s)"
        )
    }
    return decoder
}

private func makeSupabaseEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

public let supabase = SupabaseClient(
    supabaseURL: AppEnvironment.supabaseURL,
    supabaseKey: AppEnvironment.supabaseAnonKey,
    options: SupabaseClientOptions(
        db: SupabaseClientOptions.DatabaseOptions(
            encoder: makeSupabaseEncoder(),
            decoder: makeSupabaseDecoder()
        )
    )
)

@MainActor
public class RealtimeSyncManager: ObservableObject {
    public static let shared = RealtimeSyncManager()
    
    @Published public var isConnected = false
    
    private var channels: [String: RealtimeChannelV2] = [:]
    
    private init() {}
    
    /// Listens to global changes for the given table.
    /// In a real usage, you'd filter by user_id or specific row ID depending on RLS.
    public func subscribeToTableChanges(tableName: String, callback: @escaping (Any) -> Void) async {
        guard channels[tableName] == nil else { return }
        
        let channel = supabase.channel(tableName)
        
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: tableName
        )
        
        self.channels[tableName] = channel
        
        await channel.subscribe()
        DispatchQueue.main.async {
            self.isConnected = true
        }
        
        Task {
            for await change in changes {
                // Here we pass the change to the main app loop
                DispatchQueue.main.async {
                    callback(change)
                }
            }
        }
    }
    
    public func unsubscribe(tableName: String) async {
        guard let channel = channels[tableName] else { return }
        await channel.unsubscribe()
        channels.removeValue(forKey: tableName)
    }
}
