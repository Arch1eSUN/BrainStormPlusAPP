import Foundation
import Combine
import CoreLocation
import Supabase

@MainActor
public class AttendanceViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public var canClockIn: Bool = true
    @Published public var isLoading: Bool = false
    @Published public var currentLocationName: String? = "Fetching Location..."
    @Published public var errorMessage: String? = nil
    @Published public var currentStatus: String? = nil
    
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    override public init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            self.currentLocation = loc
            self.currentLocationName = "Location acquired (WGS84)"
            self.canClockIn = true
        }
    }
    
    public func clockIn(isOut: Bool = false) async {
        guard let location = currentLocation else {
            self.errorMessage = "GPS location disabled or not found."
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        self.currentStatus = nil
        
        do {
            let session = try await supabase.auth.session
            let currentToken = session.accessToken
            
            // API Route url
            let urlStr = "http://127.0.0.1:3000/api/mobile/attendance/clock"
            guard let url = URL(string: urlStr) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload: [String: Any] = [
                "type": isOut ? "out" : "in",
                "location": [
                    "latitude": location.coordinate.latitude,
                    "longitude": location.coordinate.longitude
                ],
                "device_info": "iOS App"
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpRes = response as? HTTPURLResponse {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                if httpRes.statusCode == 200, let result = json?["data"] as? [String: Any] {
                    let status = result["status"] as? String ?? "unknown"
                    let dist = result["distance"] as? Double ?? 0
                    self.currentStatus = "Success (\(status)). Distance: \(Int(dist))m"
                } else {
                    let err = json?["error"] as? String ?? "Unknown error"
                    self.errorMessage = "Failed: \(err)"
                }
            }
                
        } catch {
            self.errorMessage = "Network error: \(error.localizedDescription)"
        }
        
        self.isLoading = false
    }
}
