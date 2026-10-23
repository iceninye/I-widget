import CoreLocation

/// 天氣要「使用 App 期間」定位授權：由 app 提出一次，widget 之後先可以取位置。
final class LocationAuth: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorised: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    var text: String {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return "已允許"
        case .denied, .restricted: return "已拒絕（請喺「設定」開啟）"
        default: return "未決定"
        }
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }
}
