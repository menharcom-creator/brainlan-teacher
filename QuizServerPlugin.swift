import Foundation
import Capacitor
import Network
import CryptoKit
import UIKit

private final class Client {
    let conn: NWConnection
    var buf = Data()
    var frag = Data()
    var ws = false
    var id: String?
    init(_ c: NWConnection) { conn = c }
}

/// Runs the classroom server on the teacher's iPhone.
/// GET /        -> student page (student.html)
/// GET /info    -> {"urls":[...]}
/// WS  /ws      -> students <-> teacher messages
@objc(QuizServerPlugin)
public class QuizServerPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "QuizServerPlugin"
    public let jsName = "QuizServer"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "send", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise)
    ]

    private let q = DispatchQueue(label: "brainlan.server")
    private var listener: NWListener?
    private var clients = [ObjectIdentifier: Client]()
    private var port: UInt16 = 8080
    private lazy var page: Data = {
        if let p = Bundle.main.path(forResource: "student", ofType: "html", inDirectory: "public"),
           let d = FileManager.default.contents(atPath: p) { return d }
        return Data("Student page missing from the app.".utf8)
    }()

    // MARK: JS API
    @objc func start(_ call: CAPPluginCall) {
        port = UInt16(call.getInt("port") ?? 8080)
        q.async {
            self.shutdown()
            do {
                let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: self.port)!)
                var answered = false
                l.stateUpdateHandler = { st in
                    switch st {
                    case .ready:
                        if !answered { answered = true; call.resolve(["urls": self.urls()]) }
                    case .failed(let e):
                        if !answered { answered = true; call.reject("Port \(self.port) unavailable: \(e)") }
                    default: break
                    }
                }
                l.newConnectionHandler = { self.accept($0) }
                self.listener = l
                l.start(queue: self.q)
                DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = true } // keep screen on while hosting
            } catch { call.reject("Could not start server: \(error)") }
        }
    }

    @objc func send(_ call: CAPPluginCall) {
        guard let s = call.getString("text") else { return call.reject("text required") }
        q.async {
            var to: String?
            if let d = s.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let t = o["to"] { to = "\(t)" }
            let f = self.frame(0x1, Data(s.utf8))
            for cl in self.clients.values where cl.ws && (to == nil || cl.id == to) {
                cl.conn.send(content: f, completion: .contentProcessed { _ in })
            }
            call.resolve()
        }
    }

    @objc func stop(_ call: CAPPluginCall) { q.async { self.shutdown(); call.resolve() } }

    // MARK: server
    private func shutdown() {
        listener?.cancel(); listener = nil
        clients.values.forEach { $0.conn.cancel() }
        clients.removeAll()
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func accept(_ c: NWConnection) {
        let cl = Client(c)
        clients[ObjectIdentifier(cl)] = cl
        c.stateUpdateHandler = { [weak self, weak cl] s in
            switch s {
            case .failed, .cancelled: if let cl = cl { self?.drop(cl) }
            default: break
            }
        }
        c.start(queue: q)
        read(cl)
    }

    private func drop(_ cl: Client) { clients[ObjectIdentifier(cl)] = nil; cl.conn.cancel() }

    private func read(_ cl: Client) {
        cl.conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self = self else { return }
            if let d = data, !d.isEmpty { cl.buf.append(d); self.process(cl) }
            if err != nil || done { self.drop(cl) } else { self.read(cl) }
        }
    }

    private func process(_ cl: Client) {
        if !cl.ws {
            guard let r = cl.buf.range(of: Data("\r\n\r\n".utf8)) else { return }
            let head = String(decoding: cl.buf[..<r.lowerBound], as: UTF8.self)
            cl.buf.removeSubrange(..<r.upperBound)
            let lines = head.components(separatedBy: "\r\n")
            let parts = lines[0].split(separator: " ")
            let path = parts.count > 1 ? String(parts[1]) : "/"
            var h = [String: String]()
            for l in lines.dropFirst() {
                if let i = l.firstIndex(of: ":") {
                    h[String(l[..<i]).lowercased()] = String(l[l.index(after: i)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            if path.hasPrefix("/ws"), let key = h["sec-websocket-key"] {
                let acc = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
                let resp = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(acc)\r\n\r\n"
                cl.conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in })
                cl.ws = true
                if !cl.buf.isEmpty { process(cl) }
            } else if path.hasPrefix("/info") {
                let u = urls().map { "\"\($0)\"" }.joined(separator: ",")
                http(cl, "application/json", Data("{\"urls\":[\(u)]}".utf8))
            } else if path == "/" || path.hasPrefix("/?") || path.hasPrefix("/index") || path.hasPrefix("/student") {
                http(cl, "text/html; charset=utf-8", page)
            } else {
                http(cl, "text/plain", Data("Not found".utf8), "404 Not Found")
            }
            return
        }
        while true {
            let b = [UInt8](cl.buf)
            guard b.count >= 2 else { return }
            let op = b[0] & 0x0F, fin = b[0] & 0x80 != 0, masked = b[1] & 0x80 != 0
            var len = Int(b[1] & 0x7F), off = 2
            if len == 126 { guard b.count >= 4 else { return }; len = Int(b[2]) << 8 | Int(b[3]); off = 4 }
            else if len == 127 { guard b.count >= 10 else { return }; len = 0; for i in 2..<10 { len = len << 8 | Int(b[i]) }; off = 10 }
            let mlen = masked ? 4 : 0
            guard b.count >= off + mlen + len else { return }
            var p = Array(b[(off + mlen)..<(off + mlen + len)])
            if masked { for i in 0..<p.count { p[i] ^= b[off + i % 4] } }
            cl.buf.removeSubrange(0..<(off + mlen + len))
            switch op {
            case 0x8: drop(cl); return
            case 0x9: cl.conn.send(content: frame(0xA, Data(p)), completion: .contentProcessed { _ in })
            case 0x0, 0x1, 0x2:
                cl.frag.append(contentsOf: p)
                if fin {
                    let s = String(decoding: cl.frag, as: UTF8.self)
                    cl.frag = Data()
                    inbound(cl, s)
                }
            default: break
            }
        }
    }

    private func inbound(_ cl: Client, _ s: String) {
        if let d = s.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let f = o["from"] { cl.id = "\(f)" }
        notifyListeners("msg", data: ["text": s])
    }

    private func http(_ cl: Client, _ type: String, _ body: Data, _ status: String = "200 OK") {
        let h = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var d = Data(h.utf8); d.append(body)
        cl.conn.send(content: d, completion: .contentProcessed { [weak self] _ in self?.drop(cl) })
    }

    private func frame(_ op: UInt8, _ p: Data) -> Data {
        var d = Data([0x80 | op])
        if p.count < 126 { d.append(UInt8(p.count)) }
        else if p.count < 65536 { d.append(126); d.append(UInt8(p.count >> 8)); d.append(UInt8(p.count & 255)) }
        else { d.append(127); for i in (0..<8).reversed() { d.append(UInt8((p.count >> (8 * i)) & 255)) } }
        d.append(p)
        return d
    }

    /// Wi-Fi (en*) and Personal Hotspot (bridge*) IPv4 addresses.
    private func urls() -> [String] {
        var out = [String]()
        var ifa: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifa) == 0, let first = ifa else { return out }
        defer { freeifaddrs(ifa) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: a.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            out.append("http://\(String(cString: host)):\(port)")
        }
        return out
    }
}
