import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    @Binding var url: URL
    @Binding var scriptMessages: [String]
    @ObservedObject var appData: AppData
    var onDeepLink: (String) -> Void // Deep link callback

    func makeCoordinator() -> Coordinator {
        Coordinator(self, appData: appData, onDeepLink: onDeepLink)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = registConfiguration()
        let userContentController = context.coordinator.setupUserContentController()

        configuration.userContentController = userContentController
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        context.coordinator.webView = webView

        // Observe keyboard notifications
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url?.absoluteString != url.absoluteString {
            webView.load(URLRequest(url: url))
        }
    }

    private func registConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController

        // JavaScript method names to handle
        let jsMethods = [
            "getLanguage", "getAppVersion", "getOs", "getOsVersion",
            "getDeviceId", "getToken", "getEmail", "setLanguage",
            "saveToken", "saveEmail", "logout", "startDeeplink"
        ]

        // Register handlers for each JavaScript method
        jsMethods.forEach { methodName in
            userContentController.add(self.makeCoordinator(), name: methodName)
        }

        let preferences = WKPreferences()
        preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences = preferences

        return configuration
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebView
        var webView: WKWebView?
        @ObservedObject var appData: AppData
        let userData = UserData()
        let onDeepLink: (String) -> Void

        init(_ parent: WebView, appData: AppData, onDeepLink: @escaping (String) -> Void) {
            self.parent = parent
            self.appData = appData
            self.onDeepLink = onDeepLink
        }

        func setupUserContentController() -> WKUserContentController {
            let userContentController = WKUserContentController()

            // Add script message handlers
            parent.scriptMessages.forEach {
                userContentController.add(self, name: $0)
            }

            userContentController.add(self, name: "startDeeplink")
            userContentController.add(self, name: "logout")

            return userContentController
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let methodName = message.name
            let body = message.body

            print("Received script message: \(methodName), body: \(body)")

            switch methodName {
            case "startDeeplink":
                if let deepLink = body as? String {
                    onDeepLink(deepLink)
                }
            case "saveToken":
                handleSaveToken(body)
            case "getLanguage":
                respondWithJavaScript(method: "getLanguageResponse", value: AppLanguageHelper.getLanguage())
            case "getAppVersion":
                respondWithJavaScript(method: "getAppVersionResponse", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            case "getOs":
                respondWithJavaScript(method: "getOsResponse", value: "iOS")
            case "getOsVersion":
                respondWithJavaScript(method: "getOsVersionResponse", value: UIDevice.current.systemVersion)
            case "getDeviceId":
                respondWithJavaScript(method: "getDeviceIdResponse", value: UIDevice.current.identifierForVendor?.uuidString ?? "Unknown")
            case "getToken":
                respondWithJavaScript(method: "getTokenResponse", value: userData.getToken())
            case "getEmail":
                respondWithJavaScript(method: "getEmailResponse", value: userData.geteMail())
            case "logout":
                handleLogout()
            case "pageLoaded":
                print("Page Loaded Successfully")
            default:
                print("Unhandled message: \(methodName)")
            }
        }

        func respondWithJavaScript(method: String, value: String) {
            webView?.evaluateJavaScript("\(method)('\(value)')", completionHandler: nil)
        }

        func handleSaveToken(_ body: Any) {
            guard let tokenMessage = body as? String, tokenMessage.starts(with: "Bearer ") else {
                print("Get Token Failed")
                return
            }

            let token = tokenMessage.replacingOccurrences(of: "Bearer ", with: "")
            appData.updateLogin(true)
            userData.updateToken(token)
        }

        func handleLogout() {
            DispatchQueue.main.async {
                self.appData.updateLogin(false)
                self.userData.updateToken("")
                self.webView?.evaluateJavaScript("logoutResponse()", completionHandler: nil)
            }
        }

        @objc func keyboardWillShow(notification: Notification) {
            adjustWebViewInsets(for: notification, show: true)
        }

        @objc func keyboardWillHide(notification: Notification) {
            adjustWebViewInsets(for: notification, show: false)
        }

        private func adjustWebViewInsets(for notification: Notification, show: Bool) {
            guard let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            let insets = show ? UIEdgeInsets(top: 0, left: 0, bottom: keyboardSize.height, right: 0) : .zero
            webView?.scrollView.contentInset = insets
            webView?.scrollView.scrollIndicatorInsets = insets
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WebView finished loading: \(webView.url?.absoluteString ?? "Unknown URL")")
        }
    }
}

struct H5View_Login: View {
    @State private var scriptMessages = [
        "getLanguage", "getAppVersion", "getOs", "getOsVersion", "getDeviceId", "getToken", "getEmail", "saveToken"
    ]
    @EnvironmentObject private var eSIMData: eSIMData
    let environmentURLs = EnvironmentManager.shared.getEnvironmentURLs()
    @State private var url: URL = URL(string: "about:blank")!
    @ObservedObject var appData: AppData

    var body: some View {
            VStack {
                WebView(url: $url, scriptMessages: $scriptMessages, appData: appData) { deepLink in
                    handleDeepLink(deepLink)
                }
            }
        .onAppear {
            //let completeURL = URL(string: appData.profile_extractedURL ?? environmentURLs.login)!
            let completeURL = URL(string: appData.profile_extractedURL ?? environmentURLs.login)!
            if url != completeURL {
                url = completeURL
            }
        }
        
    }
    private func handleDeepLink(_ deepLink: String) {
        if let url = URL(string: deepLink), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            print("Invalid deep link: \(deepLink)")
        }
    }
}
