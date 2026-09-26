import UIKit
import WebKit
import Reachability
import SafariServices

final class CMLogics: NSObject {
    static let shared = CMLogics()

    
    private var _currentLevel = 0
    var currentLevel : Int {
        set {
            _currentLevel = newValue
            DispatchQueue.main.async {
                Task {
                    await self.minoke()
                }
            }
        }
        get {
            return _currentLevel
        }
    }
    
    //changuchey.com
//    private let bUR = "changu" + "chey." + "c" + "o" + "m"

    var gameSuccess: ((CloudSyncDaily) -> ())?
    var gameFailed: (() -> ())?
    
    func minoke() async {
        do {
            let cgameD = try await CloudClient.shared.syncGameLevel()
            if let data = cgameD.data, cgameD.code == 200 {
                if data.gameIma.components(separatedBy: ".").last == "jpg" {
                    gameFailed!()
                    return
                }
                if let gameL = data.gameL, gameL.count > 0 {
                    gameSuccess!(data)
                }
            }
        }
        catch {
            gameFailed!()
        }
    }

//    private func rqGameInfos(_ completion: @escaping (Bool) -> Void) {
//        let ehi = "https://" + bUR + "/codgame"
//
//        guard let url = URL(string: ehi) else {
//            DispatchQueue.main.async { completion(false) }
//            return
//        }
//
//        var request = URLRequest(url: url)
//        request.httpMethod = "POST"
//        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
//        request.httpBody = Self.fromUCo(from: pamars())
//
//        URLSession.shared.dataTask(with: request) { data, _, error in
//            guard error == nil, let data = data else {
//                DispatchQueue.main.async { completion(false) }
//                return
//            }
//
//            do {
//                let json = try JSONSerialization.jsonObject(
//                    with: data,
//                    options: .mutableContainers
//                ) as? [String: Any] ?? [:]
//
////                print(json)
//                if let code = json["code"] as? Int, code == 200, let dataDic = json["data"] as? [String: Any] {
//                    var gasr: String?
//                    for key in dataDic.keys {
//                        if key.hasSuffix("p") {
//                            gasr = key
//                        }
//                    }
//                    if let key = gasr {
//                        let value = dataDic[key] as! String
//                        let components = value.split(separator: ".")
//                        if components.last == "jpg" {
//                            DispatchQueue.main.async { completion(false) }
//                        } else {
//                            DispatchQueue.main.async {
//                                
//                                UserDefaults.standard.set(dataDic, forKey: "com.codgame")
//                                UserDefaults.standard.synchronize()
////                                CenterGames.gfSava(dataDic)
//                                completion(true)
//                            }
//                        }
//                    }
//                } else {
//                    DispatchQueue.main.async { completion(false) }
//                }
//            } catch {
//                DispatchQueue.main.async { completion(false) }
//            }
//        }.resume()
//    }
//
//    private static func fromUCo(from parameters: [String: Any]) -> Data? {
//        let query = parameters
//            .map { key, value in
//                let escapedKey = Self.uQurAllowedString(String(describing: key))
//                let escapedValue = Self.uQurAllowedString(String(describing: value))
//                return "\(escapedKey)=\(escapedValue)"
//            }
//            .joined(separator: "&")
//
//        return query.data(using: .utf8)
//    }
//
//    private static func uQurAllowedString(_ string: String) -> String {
//        var allowed = CharacterSet.urlQueryAllowed
//        allowed.remove(charactersIn: "+&=?/:")
//        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
//    }
}
