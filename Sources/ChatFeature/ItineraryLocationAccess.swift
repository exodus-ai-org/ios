import CoreLocation
import Foundation
import Observation

/// Where the app stands with location, as the map needs to know it.
enum LocationAuthorization: Equatable, Sendable {
    case notDetermined, authorized, denied, restricted
}

/// What says whether the app may know where the user is, and asks. The real one is Core Location's; tests give their
/// own.
@MainActor
protocol LocationAuthorizationSource: AnyObject {
    var status: LocationAuthorization { get }
    /// Called with the new status whenever the user answers or changes it in Settings.
    var onChange: ((LocationAuthorization) -> Void)? { get set }
    func requestWhenInUse()
}

/// The itinerary map's location button and the user's dot. Nothing ever asked for permission before, so the button
/// spun for ever: the full-screen map asks once, when it first appears, and shows the button and the dot only while
/// the answer is yes — or not given yet — never after a no.
@MainActor
@Observable
final class ItineraryLocationAccess {
    private(set) var status: LocationAuthorization
    @ObservationIgnored private let source: LocationAuthorizationSource
    @ObservationIgnored private var hasAsked = false

    init(source: LocationAuthorizationSource = CoreLocationAuthorization()) {
        self.source = source
        status = source.status
        source.onChange = { [weak self] status in self?.status = status }
    }

    var showsUserLocation: Bool { status == .notDetermined || status == .authorized }

    func requestIfNeeded() {
        #if DEBUG
        // Screenshots of the map: the system's prompt would cover it, and the simulator ignores a granted permission.
        if ProcessInfo.processInfo.arguments.contains("-NoLocationPrompt") { return }
        #endif
        guard !hasAsked, source.status == .notDetermined else { return }
        hasAsked = true
        source.requestWhenInUse()
    }
}

/// Core Location's answer, read and asked through a `CLLocationManager` the map keeps while it is on screen.
@MainActor
final class CoreLocationAuthorization: NSObject, LocationAuthorizationSource, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onChange: ((LocationAuthorization) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var status: LocationAuthorization { Self.map(manager.authorizationStatus) }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onChange?(Self.map(manager.authorizationStatus))
    }

    static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .authorized
        case .restricted: .restricted
        case .denied: .denied
        @unknown default: .denied
        }
    }
}
