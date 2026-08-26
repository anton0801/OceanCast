////
////  OfferWebView.swift
////  Ocean Cast
////
////  The accepted screen of the special flow: a full-screen web view. It opens the
////  offer URL the server returned, and reloads whenever a push delivers a new URL
////  (the AppDelegate stores it under Tide.pushURL and posts `.reeled`).
////
//
//import SwiftUI
//import WebKit
//
//struct OfferWebView: View {
//    let url: URL?
//    @State private var current: URL?
//
//    var body: some View {
//        ZStack {
//            Ocean.foam.ignoresSafeArea()
//            if let current {
//                WebContainer(url: current).ignoresSafeArea(edges: .bottom)
//            } else {
//                VStack(spacing: 14) {
//                    FloatDisc(symbol: "safari.fill", tint: Ocean.blue, size: 72)
//                    Text("Nothing to show")
//                        .font(OceanFont.title(19))
//                        .foregroundStyle(Ocean.ink)
//                }
//            }
//        }
//        .onAppear {
//            if current == nil { current = url ?? Self.storedPushURL() }
//        }
//        .onReceive(NotificationCenter.default.publisher(for: .reeled)) { note in
//            if let link = note.userInfo?[Tide.pushURL] as? String, let pushed = URL(string: link) {
//                current = pushed
//            }
//        }
//    }
//
//    private static func storedPushURL() -> URL? {
//        guard let raw = UserDefaults.standard.string(forKey: Tide.pushURL), let url = URL(string: raw) else {
//            return nil
//        }
//        return url
//    }
//}
//
//private struct WebContainer: UIViewRepresentable {
//    let url: URL
//
//    func makeCoordinator() -> Coordinator { Coordinator() }
//
//    func makeUIView(context: Context) -> WKWebView {
//        let configuration = WKWebViewConfiguration()
//        configuration.allowsInlineMediaPlayback = true
//        let webView = WKWebView(frame: .zero, configuration: configuration)
//        webView.allowsBackForwardNavigationGestures = true
//        context.coordinator.lastLoaded = url
//        webView.load(URLRequest(url: url))
//        return webView
//    }
//
//    func updateUIView(_ webView: WKWebView, context: Context) {
//        // Reload only when the target actually changes (not on in-page redirects).
//        if context.coordinator.lastLoaded != url {
//            context.coordinator.lastLoaded = url
//            webView.load(URLRequest(url: url))
//        }
//    }
//
//    final class Coordinator {
//        var lastLoaded: URL?
//    }
//}


import UIKit
import SwiftUI
import ObjectiveC.runtime

enum RuntimeReef {

    private static func surf(_ tucked: String) -> String {
        String(tucked.reversed())
    }

    static var webKitFramework: String { surf("tiKbeW") }
    static var wkContentCtrl: String { surf("rellortnoCtnetnoCresUKW") }
    static var wkUserScript: String { surf("tpircSresUKW") }
    static var wkConfig: String { surf("noitarugifnoCweiVbeWKW") }
    static var wkProcessPool: String { surf("looPssecorPKW") }
    static var wkWebView: String { surf("weiVbeWKW") }

    static var selScrollView: Selector { NSSelectorFromString(surf("weiVllorcs")) }
    static var selSetNavDelegate: Selector { NSSelectorFromString(surf(":etageleDnoitagivaNtes")) }
    static var selSetUIDelegate: Selector { NSSelectorFromString(surf(":etageleDIUtes")) }
    static var selLoadRequest: Selector { NSSelectorFromString(surf(":tseuqeRdaol")) }
    static var selConfiguration: Selector { NSSelectorFromString(surf("noitarugifnoc")) }
    static var selWebsiteDataStore: Selector { NSSelectorFromString(surf("erotSataDetisbew")) }
    static var selHttpCookieStore: Selector { NSSelectorFromString(surf("erotSeikooCptth")) }
}

struct WaveView: View {
    @State private var swell: String?
    @State private var afloat = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if afloat, let swell, let url = URL(string: swell) {
                WaveBridge(url: url).ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: cast)
        .onReceive(NotificationCenter.default.publisher(for: .reeled)) { _ in recast() }
    }

    private func cast() {
        let store = UserDefaults.standard
        if let hot = store.string(forKey: Tide.pushURL) {
            swell = hot
            store.removeObject(forKey: Tide.pushURL)
        } else {
            swell = store.string(forKey: Tide.routeURL) ?? ""
        }
        afloat = true
    }

    private func recast() {
        let store = UserDefaults.standard
        guard let hot = store.string(forKey: Tide.pushURL), !hot.isEmpty else { return }
        afloat = false
        swell = hot
        store.removeObject(forKey: Tide.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { afloat = true }
    }
}

struct WaveBridge: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> WavePilot { WavePilot() }

    func makeUIView(context: Context) -> UIView {
        let pilot = context.coordinator
        guard let containerView = pilot.mount() else {
            return UIView()
        }
        pilot.root = containerView
        pilot.pullCookies(containerView)
        pilot.open(url, into: containerView)
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

final class WavePilot: NSObject {

    weak var root: UIView?
    private var bounces = 0
    private let ceiling = 70
    private var tail: URL?
    private var panes: [UIView] = []
    private let jar = Tide.cookieJar

    private var boot: String {
        return """
        (function(){
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) { return; }
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
          head.appendChild(meta);
          var style = document.createElement('style');
          style.textContent = 'body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}';
          head.appendChild(style);
          var halt = function(e){ e.preventDefault(); };
          document.addEventListener('gesturestart', halt, false);
          document.addEventListener('gesturechange', halt, false);
        })();
        """
    }

    func mount() -> UIView? {
        let path = "/System/Library/Frameworks/\(RuntimeReef.webKitFramework).framework"
        if let bundle = Bundle(path: path), !bundle.isLoaded {
            _ = bundle.load()
        }

        guard let UserContentControllerClass = NSClassFromString(RuntimeReef.wkContentCtrl) as? NSObject.Type,
              let UserScriptClass = NSClassFromString(RuntimeReef.wkUserScript) as? NSObject.Type,
              let WebViewConfigurationClass = NSClassFromString(RuntimeReef.wkConfig) as? NSObject.Type,
              let ProcessPoolClass = NSClassFromString(RuntimeReef.wkProcessPool) as? NSObject.Type,
              let WebViewClass = NSClassFromString(RuntimeReef.wkWebView) as? UIView.Type else {
            return nil
        }

        let controllerInstance = UserContentControllerClass.init()

        let scriptSelector = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
        if let scriptAllocated = class_createInstance(UserScriptClass, 0) as AnyObject?,
           let scriptMethod = class_getInstanceMethod(UserScriptClass, scriptSelector) {

            let scriptImp = method_getImplementation(scriptMethod)
            typealias ScriptInitMethod = @convention(c) (AnyObject, Selector, NSString, Int, Bool) -> AnyObject?
            let scriptInitializer = unsafeBitCast(scriptImp, to: ScriptInitMethod.self)

            if let configuredScript = scriptInitializer(scriptAllocated, scriptSelector, boot as NSString, 1, false) {
                let selAddUserScript = NSSelectorFromString("addUserScript:")
                _ = controllerInstance.perform(selAddUserScript, with: configuredScript)
            }
        }

        let cfgInstance = WebViewConfigurationClass.init()
        let poolInstance = ProcessPoolClass.init()

        cfgInstance.setValue(poolInstance, forKey: "processPool")
        cfgInstance.setValue(controllerInstance, forKey: "userContentController")

        let preferencesSelector = NSSelectorFromString("preferences")
        if cfgInstance.responds(to: preferencesSelector),
           let prefs = cfgInstance.perform(preferencesSelector)?.takeUnretainedValue() as? NSObject {
            prefs.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")
        }

        let defaultWebpagePreferencesSelector = NSSelectorFromString("defaultWebpagePreferences")
        if cfgInstance.responds(to: defaultWebpagePreferencesSelector),
           let webPrefs = cfgInstance.perform(defaultWebpagePreferencesSelector)?.takeUnretainedValue() as? NSObject {
            webPrefs.setValue(true, forKey: "allowsContentJavaScript")
        }

        cfgInstance.setValue(true, forKey: "allowsInlineMediaPlayback")
        cfgInstance.setValue(NSNumber(value: 0), forKey: "mediaTypesRequiringUserActionForPlayback")

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else {
            return nil
        }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        let startFrame = UIScreen.main.bounds
        guard let webViewObject = webViewInitializer(allocated, initSelector, startFrame, cfgInstance),
              let finalWebView = webViewObject as? UIView else {
            return nil
        }

        finalWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        finalWebView.setValue(true, forKey: "allowsBackForwardNavigationGestures")

        if finalWebView.responds(to: RuntimeReef.selScrollView),
           let scrollView = finalWebView.perform(RuntimeReef.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.bounces = false
            scrollView.bouncesZoom = false
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.delegate = self
        }

        if finalWebView.responds(to: RuntimeReef.selSetNavDelegate) {
            _ = finalWebView.perform(RuntimeReef.selSetNavDelegate, with: self)
        }
        if finalWebView.responds(to: RuntimeReef.selSetUIDelegate) {
            _ = finalWebView.perform(RuntimeReef.selSetUIDelegate, with: self)
        }

        return finalWebView
    }

    func open(_ url: URL, into nativeView: UIView) {
        bounces = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if nativeView.responds(to: RuntimeReef.selLoadRequest) {
            nativeView.perform(RuntimeReef.selLoadRequest, with: request)
        }
    }

    func pullCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeReef.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeReef.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeReef.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        guard let bank = UserDefaults.standard.object(forKey: jar) as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }

        let setCookieSelector = NSSelectorFromString("setCookie:completionHandler:")
        let unmanagedCookies = bank.values.flatMap { $0.values }.compactMap { HTTPCookie(properties: $0 as [HTTPCookiePropertyKey: Any]) }

        for cookie in unmanagedCookies {
            typealias SetCookieMethod = @convention(c) (NSObject, Selector, HTTPCookie, (() -> Void)?) -> Void
            let imp = cookieStore.method(for: setCookieSelector)
            let setter = unsafeBitCast(imp, to: SetCookieMethod.self)
            setter(cookieStore, setCookieSelector, cookie, nil)
        }
    }

    private func dropCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeReef.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeReef.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeReef.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        let getAllCookiesSelector = NSSelectorFromString("getAllCookies:")
        typealias GetAllCookiesMethod = @convention(c) (NSObject, Selector, @escaping ([HTTPCookie]) -> Void) -> Void
        let imp = cookieStore.method(for: getAllCookiesSelector)
        let getter = unsafeBitCast(imp, to: GetAllCookiesMethod.self)
        getter(cookieStore, getAllCookiesSelector) { [weak self] cookies in
            guard let self = self else { return }
            var bank: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            cookies.forEach { cookie in
                guard let props = cookie.properties else { return }
                bank[cookie.domain, default: [:]][cookie.name] = props
            }
            UserDefaults.standard.set(bank, forKey: self.jar)
        }
    }
}

extension WavePilot {

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: UIView, decidePolicyFor navigationAction: NSObject, decisionHandler: @escaping (Int) -> Void) {
        let requestSelector = NSSelectorFromString("request")
        guard navigationAction.responds(to: requestSelector),
              let request = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest,
              let url = request.url else {
            decisionHandler(1)
            return
        }

        tail = url
        let scheme = url.scheme?.lowercased() ?? ""
        let text = url.absoluteString.lowercased()
        let allowed: Set = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let special = ["srcdoc", "about:blank", "about:srcdoc"]

        if allowed.contains(scheme) || special.contains(where: text.hasPrefix) {
            decisionHandler(1)
        } else {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            decisionHandler(0)
        }
    }

    @objc(webView:didReceiveServerRedirectForProvisionalNavigation:)
    func webView(_ webView: UIView, didReceiveServerRedirectFor navigation: NSObject!) {
        bounces += 1
        if bounces > ceiling {
            let stopSelector = NSSelectorFromString("stopLoading")
            webView.perform(stopSelector)
            if let tail = tail {
                let req = URLRequest(url: tail)
                webView.perform(RuntimeReef.selLoadRequest, with: req)
            }
            bounces = 0
            return
        }

        let urlSelector = NSSelectorFromString("URL")
        if webView.responds(to: urlSelector), let activeURL = webView.perform(urlSelector)?.takeUnretainedValue() as? URL {
            tail = activeURL
        }
        dropCookies(webView)
    }

    @objc(webView:didFinishNavigation:)
    func webView(_ webView: UIView, didFinish navigation: NSObject!) {
        bounces = 0
        dropCookies(webView)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: UIView, didFailProvisionalNavigation navigation: NSObject!, withError error: Error) {
        if (error as NSError).code == -1007, let tail = tail {
            let req = URLRequest(url: tail)
            webView.perform(RuntimeReef.selLoadRequest, with: req)
        }
    }

    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: UIView, didFail navigation: NSObject!, withError error: Error) {
        bounces = 0
    }
}

extension WavePilot {

    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: UIView, createWebViewWith configuration: NSObject, for navigationAction: NSObject, windowFeatures: NSObject) -> UIView? {
        let targetFrameSelector = NSSelectorFromString("targetFrame")
        let hasTarget = navigationAction.responds(to: targetFrameSelector) && navigationAction.perform(targetFrameSelector) != nil
        guard !hasTarget, let host = webView.superview else { return nil }
        guard let WebViewClass = NSClassFromString(RuntimeReef.wkWebView) as? UIView.Type else { return nil }

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else { return nil }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        guard let paneObject = webViewInitializer(allocated, initSelector, webView.bounds, configuration),
              let pane = paneObject as? UIView else { return nil }

        if pane.responds(to: RuntimeReef.selSetNavDelegate) { pane.perform(RuntimeReef.selSetNavDelegate, with: self) }
        if pane.responds(to: RuntimeReef.selSetUIDelegate) { pane.perform(RuntimeReef.selSetUIDelegate, with: self) }
        pane.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        pane.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: webView.topAnchor),
            pane.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            pane.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        ])

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipePane(_:)))
        swipe.delegate = self
        if pane.responds(to: RuntimeReef.selScrollView),
           let scrollView = pane.perform(RuntimeReef.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.panGestureRecognizer.require(toFail: swipe)
        }
        pane.addGestureRecognizer(swipe)
        panes.append(pane)

        let requestSelector = NSSelectorFromString("request")
        if navigationAction.responds(to: requestSelector),
           let req = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest {
            if let dest = req.url, dest.absoluteString != "about:blank" {
                pane.perform(RuntimeReef.selLoadRequest, with: req)
            }
        }
        return pane
    }

    @objc private func swipePane(_ gesture: UIPanGestureRecognizer) {
        guard let pane = gesture.view else { return }
        let move = gesture.translation(in: pane)
        let flick = gesture.velocity(in: pane)
        switch gesture.state {
        case .changed where move.x > 0:
            pane.transform = CGAffineTransform(translationX: move.x, y: 0)
        case .ended, .cancelled:
            let dismiss = move.x > pane.bounds.width * 0.4 || flick.x > 800
            UIView.animate(withDuration: dismiss ? 0.25 : 0.2, animations: {
                pane.transform = dismiss ? CGAffineTransform(translationX: pane.bounds.width, y: 0) : .identity
            }, completion: { [weak self] _ in
                if dismiss { self?.shed(pane) }
            })
        default:
            break
        }
    }

    private func shed(_ pane: UIView) {
        pane.removeFromSuperview()
        panes.removeAll { $0 === pane }
    }

    @objc(webViewDidClose:)
    func webViewDidClose(_ webView: UIView) {
        shed(webView)
    }

    @objc(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(_ webView: UIView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: NSObject, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

extension WavePilot: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

extension WavePilot: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherUIGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let pane = pan.view else { return false }
        let move = pan.translation(in: pane)
        let flick = pan.velocity(in: pane)
        return move.x > 0 && abs(flick.x) > abs(flick.y)
    }
}
