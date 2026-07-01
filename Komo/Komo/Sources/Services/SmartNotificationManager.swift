import Foundation
import UserNotifications
import CoreLocation
import Combine

// MARK: - Weather Model (Open-Meteo — 100% free, no API key)
// Docs: https://open-meteo.com/en/docs

struct KomoEnvironmentContext {
    let temperatureCelsius: Double
    let isClear: Bool
    let isRain: Bool
    let latitude: Double
    let longitude: Double

    var weatherSummary: String {
        if isRain { return "pluie" }
        if isClear { return "temps clair" }
        return "temps variable"
    }
}

struct OpenMeteoResponse: Decodable {
    let current: Current

    struct Current: Decodable {
        let temperature2m: Double       // °C
        let precipitation: Double       // mm
        let weathercode: Int            // WMO code

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case precipitation
            case weathercode
        }
    }

    var tempCelsius: Double { current.temperature2m }

    // WMO weather codes: 0=clear, 1-3=partly cloudy, 51-67=rain, 71-77=snow, 80-82=showers
    var isClear: Bool { current.weathercode <= 3 }
    var isRain: Bool {
        (51...67).contains(current.weathercode) ||
        (80...82).contains(current.weathercode)
    }
}



// MARK: - SmartNotificationManager

/// Schedules intelligent, context-aware notifications based on health data,
/// weather conditions, and time of day. All messages come from "Komo".
@MainActor
final class SmartNotificationManager: NSObject, ObservableObject {

    static let shared = SmartNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let locationManager = CLLocationManager()

    @Published var lastLocation: CLLocation?
    @Published private(set) var environmentContext: KomoEnvironmentContext?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let granted = try? await center.requestAuthorization(
            options: [.alert, .sound, .badge]
        )
        if granted == true {
            print("✅ Notifications authorized")
            locationManager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Schedule All Smart Notifications

    /// Call this after every health analysis to reschedule all smart notifications.
    func scheduleAll(from analysis: DayAnalysis?) async {
        // Clear previous Komo notifications (keep system ones)
        center.removePendingNotificationRequests(
            withIdentifiers: KomoNotificationID.all
        )

        // 1. Hydration reminders (every 2 hours, 8h → 20h)
        scheduleHydrationReminders()

        // 2. Stand up reminder (every hour if no steps)
        scheduleStandUpReminder()

        // 3. Bedtime reminder
        scheduleBedtimeReminder()

        // 4. Step-based notifications (uses real analysis data)
        if let analysis = analysis {
            scheduleStepReminders(analysis: analysis)
            scheduleStressRecovery(analysis: analysis)
            scheduleSleepInsight(analysis: analysis)
        }

        // 5. Weather-based notifications (async, needs location)
        if let location = lastLocation {
            await scheduleWeatherNotifications(location: location, analysis: analysis)
        } else {
            locationManager.requestLocation()
        }

        print("📱 Smart notifications scheduled")
    }

    // MARK: - 1. Hydration Reminders

    private func scheduleHydrationReminders() {
        let messages = [
            "Bois un verre d'eau maintenant 💧 — la déshydratation augmente ton stress.",
            "Komo te rappelle : hydrate-toi ! Ton cerveau a besoin d'eau pour rester focus.",
            "💧 Pause hydratation ! Même un petit verre compte.",
            "Tu as bu assez d'eau aujourd'hui ? Komo te dit d'en prendre un verre maintenant.",
            "Hydratation check 💧 — objectif : 8 verres par jour.",
            "L'eau, c'est la vie ! Prends 30 secondes pour boire."
        ]

        let hours = [10, 12, 14, 16, 18, 20]

        for (index, hour) in hours.enumerated() {
            var components = DateComponents()
            components.hour = hour
            components.minute = 0

            let content = UNMutableNotificationContent()
            content.title = "Komo 💧"
            content.body = messages[index % messages.count]
            content.sound = .default
            content.categoryIdentifier = "HYDRATION"

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: true
            )

            let request = UNNotificationRequest(
                identifier: "\(KomoNotificationID.hydration)_\(hour)",
                content: content,
                trigger: trigger
            )

            center.add(request)
        }
    }

    // MARK: - 2. Stand Up Reminder

    private func scheduleStandUpReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Komo 🧍"
        content.body = "Tu es assis depuis un moment — lève-toi 2 minutes ! Ton dos et ton cœur te remercieront."
        content.sound = .default

        // Every hour from 9h to 18h (workday)
        let hours = [9, 10, 11, 13, 15, 17]
        for hour in hours {
            var components = DateComponents()
            components.hour = hour
            components.minute = 45  // 45 min into each hour

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "\(KomoNotificationID.standUp)_\(hour)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    // MARK: - 3. Bedtime Reminder

    private func scheduleBedtimeReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Komo 🌙"
        content.body = "Il est l'heure de te préparer à dormir. Pose ton téléphone, baisse la lumière — ton sommeil de demain commence maintenant."
        content.sound = .default

        var components = DateComponents()
        components.hour = 22
        components.minute = 30

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: KomoNotificationID.bedtime,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - 4. Step-Based Notifications

    private func scheduleStepReminders(analysis: DayAnalysis) {
        let steps = analysis.totalSteps

        // Evening check at 17h
        var components = DateComponents()
        components.hour = 17
        components.minute = 0

        let body: String
        if steps < 2000 {
            body = "Tu n'as fait que \(steps) pas aujourd'hui 😮 — même 10 minutes de marche ferait une vraie différence pour ta santé."
        } else if steps < 5000 {
            body = "Komo a compté \(steps) pas ! Il t'en reste \(5000 - steps) pour atteindre un minimum sain. Une balade de 15 min ?"
        } else if steps < 8000 {
            body = "\(steps) pas — presque là ! Encore \(8000 - steps) pas pour atteindre les 8000. Marche jusqu'au prochain coin de rue 🚶"
        } else {
            body = "\(steps) pas aujourd'hui 💪 — objectif atteint ! Komo est fier de toi."
        }

        let content = UNMutableNotificationContent()
        content.title = steps >= 8000 ? "Komo 🏃" : "Komo 🚶"
        content.body = body
        content.sound = .default

        // Fire in 5 seconds from now if it's past 17h, else at 17h
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)

        if hour >= 17 {
            // Schedule for right now (analysis just ran)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(
                identifier: KomoNotificationID.steps,
                content: content,
                trigger: trigger
            )
            center.add(request)
        } else {
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: KomoNotificationID.steps,
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    // MARK: - 5. Stress Recovery

    private func scheduleStressRecovery(analysis: DayAnalysis) {
        guard analysis.highStressHours >= 2 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Komo 🧘"

        if let peak = analysis.peakStressHour {
            content.body = "Ta matinée était intense — ton HR a atteint \(Int(peak.meanHR)) BPM. Prends 5 minutes pour respirer : inspire 4 sec, expire 6 sec. Ton corps en a besoin."
        } else {
            content.body = "Komo a détecté \(analysis.highStressHours)h de stress élevé. Une pause de 5 min maintenant peut changer toute ta journée — sors marcher un peu."
        }
        content.sound = .default

        // Fire 30 minutes after analysis
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: KomoNotificationID.stress,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - 6. Sleep Insight

    private func scheduleSleepInsight(analysis: DayAnalysis) {
        guard let sleep = analysis.sleepAssessment else { return }
        let hours = sleep.data.totalSleepMinutes / 60.0
        guard hours < 6.5 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Komo 😴"
        content.body = "Tu as dormi seulement \(String(format: "%.1f", hours))h cette nuit. Aujourd'hui : évite la caféine après 14h, et essaie de te coucher 30 min plus tôt ce soir."
        content.sound = .default

        var components = DateComponents()
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: KomoNotificationID.sleep,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - 7. Weather-Based Notifications (Open-Meteo — free, no capability needed)

    func refreshEnvironmentContext() async {
        guard let location = lastLocation else {
            locationManager.requestLocation()
            return
        }

        guard let weather = await fetchWeather(for: location) else { return }
        environmentContext = KomoEnvironmentContext(
            temperatureCelsius: weather.tempCelsius,
            isClear: weather.isClear,
            isRain: weather.isRain,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    private func fetchWeather(for location: CLLocation) async -> OpenMeteoResponse? {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,precipitation,weathercode"

        let decoder = JSONDecoder()
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let weather = try? decoder.decode(OpenMeteoResponse.self, from: data) else {
            print("⚠️ Weather fetch failed")
            return nil
        }

        environmentContext = KomoEnvironmentContext(
            temperatureCelsius: weather.tempCelsius,
            isClear: weather.isClear,
            isRain: weather.isRain,
            latitude: lat,
            longitude: lon
        )
        print("🌤️ Weather: \(Int(weather.tempCelsius))°C, clear:\(weather.isClear), rain:\(weather.isRain)")
        return weather
    }

    private func scheduleWeatherNotifications(location: CLLocation, analysis: DayAnalysis?) async {
        guard let weather = await fetchWeather(for: location) else { return }
        let tempC = weather.tempCelsius
        let steps = analysis?.totalSteps ?? 0
        var notifications: [(id: String, title: String, body: String, hour: Int)] = []

        // Hot weather → hydration warning
        if tempC >= 28 {
            notifications.append((
                id: KomoNotificationID.weatherHot,
                title: "Komo 🌡️",
                body: "Il fait \(Int(tempC))°C dehors ! Bois au moins 2L d'eau aujourd'hui — la chaleur augmente ta déshydratation de 30%.",
                hour: 12
            ))
        }

        // Sunny + low steps → go outside
        if weather.isClear && steps < 5000 {
            notifications.append((
                id: KomoNotificationID.weatherWalk,
                title: "Komo ☀️",
                body: "Il fait \(Int(tempC))° et le soleil brille — conditions parfaites pour marcher ! Tu n'as fait que \(steps) pas. 15 minutes dehors ?",
                hour: 14
            ))
        }

        // Rain → indoor workout
        if weather.isRain {
            notifications.append((
                id: KomoNotificationID.weatherRain,
                title: "Komo 🌧️",
                body: "Il pleut dehors mais ton corps a quand même besoin de bouger. 20 min d'étirements ou de yoga à l'intérieur ?",
                hour: 11
            ))
        }

        for notif in notifications {
            var components = DateComponents()
            components.hour = notif.hour
            components.minute = 0

            let content = UNMutableNotificationContent()
            content.title = notif.title
            content.body = notif.body
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notif.id,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }

    }

    // MARK: - Send Immediate Notification (for testing)


    func sendImmediate(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}

// MARK: - CLLocationManagerDelegate

extension SmartNotificationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
        print("📍 Location updated: \(locations.last?.coordinate ?? CLLocationCoordinate2D())")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("⚠️ Location error: \(error.localizedDescription)")
    }
}

// MARK: - Notification IDs

enum KomoNotificationID {
    static let hydration = "komo.hydration"
    static let standUp   = "komo.standup"
    static let bedtime   = "komo.bedtime"
    static let steps     = "komo.steps"
    static let stress    = "komo.stress"
    static let sleep     = "komo.sleep"
    static let weatherHot  = "komo.weather.hot"
    static let weatherWalk = "komo.weather.walk"
    static let weatherRain = "komo.weather.rain"
    static let weatherUV   = "komo.weather.uv"

    static var all: [String] {
        var ids: [String] = [bedtime, steps, stress, sleep, weatherHot, weatherWalk, weatherRain, weatherUV]
        // Add hourly hydration + standup IDs
        for h in [10, 12, 14, 16, 18, 20] { ids.append("\(hydration)_\(h)") }
        for h in [9, 10, 11, 13, 15, 17]  { ids.append("\(standUp)_\(h)") }
        return ids
    }
}
