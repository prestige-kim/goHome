import Combine
import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var location: CLLocation?
    @Published private(set) var errorMessage: String?

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestAccessAndLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            errorMessage = "가까운 역을 찾으려면 설정에서 위치 권한을 허용하거나 역을 직접 검색해 주세요."
        @unknown default:
            errorMessage = "위치 권한 상태를 확인할 수 없습니다."
        }
    }

    func refreshLocation() {
        errorMessage = nil
        requestAccessAndLocation()
    }
}

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            errorMessage = nil
            manager.requestLocation()
        case .denied, .restricted:
            errorMessage = "가까운 역을 찾으려면 설정에서 위치 권한을 허용하거나 역을 직접 검색해 주세요."
        case .notDetermined:
            break
        @unknown default:
            errorMessage = "위치 권한 상태를 확인할 수 없습니다."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        errorMessage = nil
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "현재 위치를 가져오지 못했습니다. 다시 시도하거나 역을 직접 검색해 주세요."
    }
}
