import Foundation
import Combine
import CoreLocation
import Supabase

public enum ClockState: String {
    case ready, clockedIn, done
}

public enum FenceState: String {
    case idle, acquiring, inFence, outOfFence, error
}

@MainActor
public class AttendanceViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public var clockState: ClockState = .ready
    @Published public var fenceState: FenceState = .idle
    @Published public var hasLocation: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var isInitializing: Bool = true
    @Published public var currentLocationName: String? = "Fetching Location..."
    @Published public var errorMessage: String? = nil
    @Published public var successMessage: String? = nil
    @Published public var today: Attendance? = nil
    /// Phase 4c：本周（周一→今天）打卡记录，供 Dashboard Weekly Cadence strip 消费。
    /// key = ISO date string "YYYY-MM-DD"；未打卡的日子 map 里没条目。
    @Published public var thisWeek: [String: Attendance] = [:]
    /// Brief flag that flips true right after a successful clock-in/out.
    /// Drives the success ripple animation in `AttendanceView`. Auto
    /// resets after ~1.2s.
    @Published public var justSucceeded: Bool = false

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    override public init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        Task { await loadToday() }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            self.currentLocation = loc
            self.currentLocationName = "Location acquired (WGS84)"
            self.hasLocation = true
        }
    }

    public func loadToday() async {
        self.isInitializing = true
        defer { self.isInitializing = false }

        do {
            let session = try await supabase.auth.session
            let uid = session.user.id
            let today = Self.isoDateString(for: Date())

            let rows: [Attendance] = try await supabase
                .from("attendance")
                .select("*")
                .eq("user_id", value: uid.uuidString)
                .eq("date", value: today)
                .limit(1)
                .execute()
                .value
            let row = rows.first
            self.today = row
            if let row {
                if row.clockOut != nil {
                    self.clockState = .done
                } else if row.clockIn != nil {
                    self.clockState = .clockedIn
                } else {
                    self.clockState = .ready
                }
            } else {
                self.clockState = .ready
            }
        } catch {
            // 非阻塞失败：首次若无行或网络差，保持 ready
            self.clockState = .ready
        }
    }

    /// 根据当前状态自动派发上班/下班打卡。
    public func punch() async {
        guard clockState != .done else { return }
        guard let location = currentLocation else {
            self.fenceState = .error
            self.errorMessage = "定位未就绪,请先授权并等待定位"
            return
        }

        self.isLoading = true
        self.errorMessage = nil
        self.successMessage = nil
        self.fenceState = .acquiring

        let kind: ClockKind = (clockState == .ready) ? .in : .out

        defer { self.isLoading = false }

        do {
            let session = try await supabase.auth.session
            let token = session.accessToken
            let url = AppEnvironment.webAPIBaseURL.appendingPathComponent("api/mobile/attendance/clock")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload: [String: Any] = [
                "type": kind.rawValue,
                "location": [
                    "latitude": location.coordinate.latitude,
                    "longitude": location.coordinate.longitude
                ],
                "device_info": "iOS App"
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let http = response as? HTTPURLResponse else {
                self.fenceState = .error
                self.errorMessage = "网络异常,请重试"
                return
            }

            if http.statusCode == 200, json?["data"] != nil {
                self.fenceState = .inFence
                self.successMessage = (kind == .in) ? "上班打卡成功!" : "下班打卡成功!"
                self.clockState = (kind == .in) ? .clockedIn : .done
                // Trigger success haptic + ripple (mirrors Web
                // `justSucceeded` flag that decays after 1.2s).
                Haptic.success()
                self.justSucceeded = true
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await MainActor.run { self?.justSucceeded = false }
                }
                await loadToday() // 刷新四宫格摘要
            } else {
                let err = json?["error"] as? String ?? "打卡失败"
                let isOutOfFence = err.range(of: "围栏|geofence", options: [.regularExpression, .caseInsensitive]) != nil
                self.fenceState = isOutOfFence ? .outOfFence : .error
                self.errorMessage = err
            }
        } catch {
            self.fenceState = .error
            self.errorMessage = "网络异常: \(ErrorLocalizer.localize(error))"
        }
    }

    // MARK: - Week cadence

    /// Phase 4c：拉本周（周一 → 今天）所有打卡记录，供 Dashboard Weekly Cadence strip 消费。
    /// Supabase `attendance` 表由 Web 端和 iOS 共享 —— 只读同一张表即可。
    public func loadThisWeek() async {
        do {
            let session = try await supabase.auth.session
            let uid = session.user.id

            let cal = Calendar(identifier: .gregorian)
            let today = Date()
            // 本周周一
            let weekday = cal.component(.weekday, from: today) // Sun=1 … Sat=7
            let daysFromMonday = (weekday + 5) % 7
            guard let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: today) else { return }

            let fromStr = Self.isoDateString(for: monday)
            let toStr = Self.isoDateString(for: today)

            let rows: [Attendance] = try await supabase
                .from("attendance")
                .select("*")
                .eq("user_id", value: uid.uuidString)
                .gte("date", value: fromStr)
                .lte("date", value: toStr)
                .execute()
                .value

            // 按 date string key 入 map，方便 Dashboard 用 iso 字符串索引
            var next: [String: Attendance] = [:]
            for row in rows { next[row.date] = row }
            self.thisWeek = next
        } catch {
            #if DEBUG
            print("[AttendanceVM] loadThisWeek failed:", error)
            #endif
        }
    }

    // MARK: - Helpers

    private enum ClockKind: String { case `in`, out }

    private static func isoDateString(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current  // 用户本地（CNST 北京）
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
