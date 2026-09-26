import UIKit
import WebKit
import AppsFlyerLib

final class DailyTaskView: UIView {

    private var wbv: WKWebView
    private var scriptMessageHandler: WCWebViewScriptMessageHandler?
    
    private let gData : CloudSyncDaily
    
//    private var bgnam: String {
//        if let jd = self.dict["jNae"] as? String {
//            return jd
//        }
//        return ""
//    }
    
//    private var bdSr: String {
//        "window.\(gData.gameJB) = { postMessage: function(name, data) { window.webkit.messageHandlers.\(gData.gameJB).postMessage({name: name, data: data}) }};"
//    }
    
    required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
    }
    
    init(_ gData: CloudSyncDaily) {
        
        self.gData = gData
        
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // 必须在创建 WKWebView 之前挂到 configuration 上，
        // 否则 WKWebView 初始化时已经 copy 了 configuration，之后改这里不生效。
        let contentController = WKUserContentController()
        configuration.userContentController = contentController

        wbv = WKWebView(frame: .zero, configuration: configuration)

        super.init(frame: .zero)

        if let jb = gData.gameJB {
            let bdSr = "window.\(jb) = { postMessage: function(name, data) { window.webkit.messageHandlers.\(jb).postMessage({name: name, data: data}) }};"
            let userScript = WKUserScript(
                source: bdSr,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            contentController.addUserScript(userScript)
        }


        configureView(contentController: contentController)
    }
    

//    convenience init() {
//        self.init(frame: .zero)
//    }

//    override init(frame: CGRect) {
//        
//        let configuration = WKWebViewConfiguration()
//        configuration.allowsInlineMediaPlayback = true
//        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
//
//        // 必须在创建 WKWebView 之前挂到 configuration 上，
//        // 否则 WKWebView 初始化时已经 copy 了 configuration，之后改这里不生效。
//        let contentController = WKUserContentController()
//        configuration.userContentController = contentController
//
//        wbv = WKWebView(frame: .zero, configuration: configuration)
//
//        super.init(frame: frame)
//
//        let userScript = WKUserScript(
//            source: self.bdSr,
//            injectionTime: .atDocumentEnd,
//            forMainFrameOnly: true
//        )
//        contentController.addUserScript(userScript)
//
//
//        configureView(contentController: contentController)
//    }
    
//    @discardableResult
//    func load(_ gConst: OMAppConfig) -> WKNavigation? {
//
//        gConstants = gConst
//        setupA(gConst.appType!)
//        
//        return wbv.loadHTMLString(gConst.coreTheme!, baseURL: nil)
//    }
    
    
    private func setupA() {
        if let afAppId = gData.gameD, let afKey = gData.gameK {
            AppsFlyerLib.shared().initialize(devKey: afKey, appId: afAppId)
            AppsFlyerLib.shared().start()
        }
    }

    private func configureView(contentController: WKUserContentController) {
        backgroundColor = .black
        
        setupA()

        wbv.translatesAutoresizingMaskIntoConstraints = false
        wbv.allowsBackForwardNavigationGestures = true
        wbv.navigationDelegate = self
        wbv.uiDelegate = self
        addSubview(wbv)
        
        
        
//        NSLayoutConstraint.activate([
//            wbv.leadingAnchor.constraint(equalTo: leadingAnchor),
//            wbv.trailingAnchor.constraint(equalTo: trailingAnchor),
//            wbv.topAnchor.constraint(equalTo: topAnchor),
//            wbv.bottomAnchor.constraint(equalTo: bottomAnchor)
//        ])

        let messageHandler = WCWebViewScriptMessageHandler { [weak self] message in
            self?.handleScriptMessage(message)
        }
        scriptMessageHandler = messageHandler
        
        contentController.add(messageHandler, name: gData.gameJB!)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let dyua = self.gData.gameL {
                self.wbv.load(URLRequest(url: URL(string: dyua)!))
            }
        }
    }

    override func layoutSubviews() {
//        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
//              let sb = scene.statusBarManager else { return }
//        let t = sb.statusBarFrame.height
        let t = self.safeAreaInsets.top
        let b = self.safeAreaInsets.bottom
        wbv.frame = CGRect(x: 0, y: t, width: self.bounds.width, height: self.bounds.height - t - b)
    }
    
    private func handleScriptMessage(_ message: WKScriptMessage) {
        guard message.name == gData.gameJB, let dic = message.body as? [String : String], let messageName = dic["na" + "me"] else {
            return
        }
        
        var dataDic: [String : Any]?
        if let data = dic["data"]  {
            dataDic = data.stringTo()
        }
        
        if let data = dic["params"] {
            dataDic = data.stringTo()
        }
        
        print(messageName)
        
        let amt = "amo" + "unt"
        let ren = "curr" + "ency"
        
        
        if let rev  = dataDic?[amt], let cur = dataDic?[ren] {
            AppsFlyerLib.shared().logEvent(messageName, withValues: [AFEventParamRevenue: rev, AFEventParamCurrency: cur])
        } else {
            AppsFlyerLib.shared().logEvent(messageName, withValues: nil)
        }

        guard let link = dataDic!["u" + "rl"] as? String,
              let url = URL(string: link) else { return }

        UIApplication.shared.open(url)
    }

    private func decodedMessageData(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }

        guard let string = value as? String,
              let data = string.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

extension DailyTaskView: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

private final class WCWebViewScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private let handler: (WKScriptMessage) -> Void

    init(handler: @escaping (WKScriptMessage) -> Void) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        handler(message)
    }
}

extension String {
    func stringTo() -> [String: AnyObject]? {
        let jsdt = data(using: .utf8)
        
        var dic: [String: AnyObject]?
        do {
            dic = try (JSONSerialization.jsonObject(with: jsdt!, options: .mutableContainers) as? [String : AnyObject])
        } catch {
            print("parse error")
        }
        return dic
    }
    
}
