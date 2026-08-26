import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

enum Tide {
    static let appCode = "6802835318"
    static let relayKey = "nCj6Tei4QYWY7JdCdWgRQW"
    static let suite = "group.oceancast.reef"
    static let cookieJar = "oc_reef_cookies"
    static let tag = "🌊 [OceanCast]"
    static let pushURL = "temp_url"
    static let routeURL = "oc_route_url"
    static let fcm = "fcm_token"
    static let push = "push_token"
    static let sharedFcm = "shared_fcm"
    static let attStatus = "oc_att_status"
    static let primed = "oc_primed"
}

extension Notification.Name {
    static let cast = Notification.Name("ConversionDataReceived")
    static let hooked = Notification.Name("deeplink_values")
    static let reeled = Notification.Name("LoadTempURL")
}

final class AppDelegate: UIResponder, UIApplicationDelegate {

    private var deep: [AnyHashable: Any] = [:]
    private var shallow: [AnyHashable: Any] = [:]
    private var drift: Task<Void, Never>?
    private var probing = false

    private static let lane = URLSession(configuration: .ephemeral)

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()

        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = Tide.relayKey
        sdk.appleAppID = Tide.appCode
        sdk.delegate = self
        sdk.deepLinkDelegate = self
        sdk.isDebug = false

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            snag(cold)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(surfaced), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    @objc private func surfaced() {
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        Task {
            _ = await AppTracking.resolve()
            await MainActor.run {
                AppsFlyerLib.shared().start()
                UserDefaults.standard.set(ATTrackingManager.trackingAuthorizationStatus.rawValue, forKey: Tide.attStatus)
            }
        }
    }

    private func trawl() {
        drift?.cancel()
        drift = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run { self?.net() }
        }
    }

    private func net() {
        drift?.cancel()
        drift = nil
        var haul = deep
        for (key, value) in shallow {
            let tag = "deep_\(key)"
            if haul[tag] == nil { haul[tag] = value }
        }
        Task { await AttributionRelay.shared.deliver(haul) }
    }

    /// Organic re-request of the precise install data from AppsFlyer.
    private static func probe() async -> [String: String] {
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        let raw = "https://gcdsdk.appsflyer.com/install_data/v4.0/\(Tide.appCode)?devkey=\(Tide.relayKey)&device_id=\(uid)"
        guard let url = URL(string: raw) else { return [:] }
        do {
            let (tmp, resp) = try await lane.download(from: url)
            guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return [:] }
            let data = try Data(contentsOf: tmp)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return dict.mapValues { "\($0)" }
        } catch {
            return [:]
        }
    }

    private func snag(_ payload: [AnyHashable: Any]) {
        var caught: String?
        if let direct = payload["url"] as? String, direct.isEmpty == false {
            caught = direct
        } else if let data = payload["data"] as? [AnyHashable: Any], let url = data["url"] as? String, url.isEmpty == false {
            caught = url
        } else if let aps = payload["aps"] as? [AnyHashable: Any],
                  let data = aps["data"] as? [AnyHashable: Any],
                  let url = data["url"] as? String, url.isEmpty == false {
            caught = url
        } else if let custom = payload["custom"] as? [AnyHashable: Any], let url = custom["url"] as? String, url.isEmpty == false {
            caught = url
        }
        guard let link = caught else { return }

        UserDefaults.standard.set(link, forKey: Tide.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .reeled, object: nil, userInfo: ["temp_url": link])
        }
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: Tide.fcm)
            UserDefaults.standard.set(token, forKey: Tide.push)
            UserDefaults(suiteName: Tide.suite)?.set(token, forKey: Tide.sharedFcm)
            Task { await PushTokenReporter.report(token) }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        snag(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        snag(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        snag(userInfo)
        completionHandler(.newData)
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        deep = conversionInfo

        let organic = (conversionInfo["af_status"] as? String)?.caseInsensitiveCompare("Organic") == .orderedSame
        guard organic else {
            trawl()
            if shallow.isEmpty == false { net() }
            return
        }
        
        probing = true
        drift?.cancel()
        drift = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard Task.isCancelled == false else { return }
            let extra = await Self.probe()
            await MainActor.run {
                guard let self else { return }
                for (key, value) in extra where self.deep[key] == nil { self.deep[key] = value }
                self.probing = false
                self.net()
            }
        }
    }

    func onConversionDataFail(_ error: Error) {
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        guard UserDefaults.standard.bool(forKey: Tide.primed) == false else { return }
        shallow = deepLink.clickEvent
        NotificationCenter.default.post(name: .hooked, object: nil, userInfo: ["deeplinksData": deepLink.clickEvent])
        if probing { return }
        drift?.cancel()
        drift = nil
        if deep.isEmpty == false { net() }
    }
}
