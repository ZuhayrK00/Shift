import Foundation
import CoreLocation
import WeatherKit
import Observation

@MainActor @Observable
final class EnduranceWeatherService: NSObject, CLLocationManagerDelegate {
    static let shared = EnduranceWeatherService()
    private(set) var snapshot: OutdoorWeatherSnapshot?
    private(set) var attribution: WeatherAttribution?
    private(set) var alerts: [WeatherAlert] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var enabled = false
    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private var pass = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var wantsLocation = false
    @ObservationIgnored private var selectedCity: String?
    private var preferenceKey: String? { owner.map { "shift.weather.enabled." + $0 } }

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    func activate(owner newOwner: String?) async {
        #if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
        if StoreCaptureConfiguration.enabled {
            owner = newOwner; enabled = true
            let hour = OutdoorWeatherHour(date: Date(), celsius: 14, rainChance: 0.1, windKPH: 9, gustKPH: 12, uv: 1, daylight: true, hazardous: false, condition: "Partly cloudy", symbol: "cloud.sun.fill")
            let hours: [OutdoorWeatherHour] = (0..<192).map { offset in
                let date = Date().addingTimeInterval(Double(offset) * 3_600)
                let clock = Calendar.current.component(.hour, from: date)
                return .init(date: date,celsius: clock > 10 && clock < 18 ? 16 : 12,rainChance: 0.1,windKPH: 9,gustKPH: 12,uv: 1,daylight: clock >= 7 && clock < 18,hazardous: false,condition: "Partly cloudy",symbol: "cloud.sun.fill")
            }
            snapshot = .init(fetchedAt: Date(), place: "London", current: hour, hours: hours)
            return
        }
        #endif
        if owner != newOwner {
            pass = UUID(); task?.cancel(); timeout?.cancel(); geocoder.cancelGeocode()
            wantsLocation = false; loading = false; snapshot = nil; attribution = nil; alerts = []; error = nil
            selectedCity = nil
            owner = newOwner
            enabled = preferenceKey.map { UserDefaults.standard.bool(forKey: $0) } ?? false
        }
        if enabled { refresh() }
    }
    func enable() {
        guard owner != nil else { return }
        pass = UUID(); task?.cancel(); timeout?.cancel(); geocoder.cancelGeocode(); loading = false
        selectedCity = nil
        enabled = true
        if let preferenceKey { UserDefaults.standard.set(true, forKey: preferenceKey) }
        refresh(force: true)
    }
    func disable() {
        pass = UUID(); task?.cancel(); timeout?.cancel(); geocoder.cancelGeocode()
        wantsLocation = false; enabled = false; loading = false; snapshot = nil; attribution = nil; alerts = []; error = nil
        if let preferenceKey { UserDefaults.standard.set(false, forKey: preferenceKey) }
        Task { await WidgetDataService.updateSnapshot(); PhoneSessionManager.shared.sendContextToWatch() }
    }
    func brief(for userID: String) -> OutdoorWeatherBrief? {
        guard owner == userID, enabled, let snapshot, snapshot.isFresh(at: Date()), let attribution else { return nil }
        return .init(fetchedAt: snapshot.fetchedAt, place: snapshot.place, celsius: snapshot.current.celsius,
            symbol: snapshot.current.symbol, condition: snapshot.current.condition, legalURL: attribution.legalPageURL)
    }
    func clearDeletedAccount(_ userID: String) {
        UserDefaults.standard.removeObject(forKey: "shift.weather.enabled." + userID)
    }
    func refresh(force: Bool = false) {
        #if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
        if StoreCaptureConfiguration.enabled { return }
        #endif
        guard enabled, owner != nil, !loading else { return }
        if !force, let snapshot, Date().timeIntervalSince(snapshot.fetchedAt) < 900 { return }
        if let selectedCity { useCity(selectedCity); return }
        pass = UUID(); error = nil; loading = true; wantsLocation = true
        switch locationManager.authorizationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: requestLocation()
        default: failed("Location is off. Choose a city below, or allow location in Settings.")
        }
    }
    func useCity(_ city: String) {
        let query = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 120, owner != nil else { return }
        pass = UUID(); let current = pass
        task?.cancel(); timeout?.cancel(); geocoder.cancelGeocode(); wantsLocation = false
        selectedCity = query
        enabled = true; loading = true; error = nil
        if let preferenceKey { UserDefaults.standard.set(true, forKey: preferenceKey) }
        task = Task {
            do {
                guard let match = try await geocoder.geocodeAddressString(query).first, let location = match.location else {
                    if pass == current { failed("That city wasn't found. Try adding its country.") }; return
                }
                guard pass == current, !Task.isCancelled else { return }
                await fetch(location, place: match.locality ?? match.name ?? query, pass: current)
            } catch { if pass == current { failed("Couldn't find that city. Please try again.") } }
        }
    }
    private func requestLocation() {
        guard wantsLocation else { return }
        locationManager.requestLocation()
        timeout?.cancel(); let current = pass
        timeout = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, pass == current, wantsLocation else { return }
            wantsLocation = false; failed("Location took too long. Try again or choose a city.")
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantsLocation else { return }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { requestLocation() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { wantsLocation = false; failed("Location is off. You can choose a city instead.") }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsLocation, let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 300 else { return }
        wantsLocation = false; timeout?.cancel(); let current = pass
        task = Task {
            let place = (try? await geocoder.reverseGeocodeLocation(location).first?.locality) ?? "Your area"
            guard pass == current, !Task.isCancelled else { return }
            await fetch(location, place: place, pass: current)
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard wantsLocation else { return }; wantsLocation = false; timeout?.cancel()
        failed("Couldn't get your location. Try again or choose a city.")
    }
    private func failed(_ message: String) { loading = false; error = message }
    private func fetch(_ location: CLLocation, place: String, pass current: UUID) async {
        do {
            async let report = WeatherService.shared.weather(for: location)
            async let branding = WeatherService.shared.attribution
            let (weather, mark) = try await (report, branding)
            guard pass == current, owner == authManager.currentUserId, !Task.isCancelled else { return }
            let now = weather.currentWeather
            let hours = weather.hourlyForecast.map { hour in
                OutdoorWeatherHour(date: hour.date, celsius: hour.temperature.converted(to: .celsius).value,
                    rainChance: hour.precipitationChance, windKPH: hour.wind.speed.converted(to: .kilometersPerHour).value,
                    gustKPH: hour.wind.gust?.converted(to: .kilometersPerHour).value ?? 0,
                    uv: hour.uvIndex.value, daylight: hour.isDaylight, hazardous: Self.hazardous(hour.condition),
                    condition: hour.condition.description, symbol: hour.symbolName)
            }
            snapshot = .init(fetchedAt: Date(), place: place,
                current: .init(date: now.date, celsius: now.temperature.converted(to: .celsius).value,
                    rainChance: hours.first(where: { $0.date <= Date() && $0.date.addingTimeInterval(3_600) > Date() })?.rainChance ?? 0,
                    windKPH: now.wind.speed.converted(to: .kilometersPerHour).value, gustKPH: now.wind.gust?.converted(to: .kilometersPerHour).value ?? 0,
                    uv: now.uvIndex.value, daylight: now.isDaylight, hazardous: Self.hazardous(now.condition),
                    condition: now.condition.description, symbol: now.symbolName), hours: hours)
            attribution = mark; alerts = weather.weatherAlerts ?? []; loading = false; error = nil
            await WidgetDataService.updateSnapshot(); PhoneSessionManager.shared.sendContextToWatch()
        } catch {
            guard pass == current else { return }
            failed("Apple Weather is unavailable right now. Try again; planning without a forecast is still available.")
        }
    }
    private static func hazardous(_ value: WeatherCondition) -> Bool {
        switch value {
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .hurricane, .tropicalStorm, .blizzard, .hail, .freezingRain, .freezingDrizzle, .wintryMix: true
        default: false
        }
    }
}
