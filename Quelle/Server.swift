import Foundation
import Network

/// Winziger HTTP-Server, der nur auf 127.0.0.1 lauscht und ausschließlich
/// Dateien unterhalb des Lernseiten-Ordners ausliefert.
///
/// Warum überhaupt ein Server? Eine per `file://` geöffnete Seite bekommt von
/// WebKit einen wechselnden, abgeschotteten Speicherbereich — der Lernfortschritt
/// wäre unzuverlässig. Unter `http://127.0.0.1:<fester Port>` ist der Ursprung
/// stabil, und localStorage verhält sich wie in jedem normalen Browser.
final class Server {

    static let port: UInt16 = 47623
    static var basis: String { "http://127.0.0.1:\(port)" }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "lernkiste.server", qos: .userInitiated)

    /// Strichliste, welches GIF wie oft wirklich auf dem Bildschirm war.
    /// Grundlage fuer das Aussortieren alle zwei Wochen. Alle Verbindungen
    /// laufen auf derselben seriellen Queue, darum reicht ein schlichtes Dictionary.
    private lazy var gifNutzung: [String: [String: Any]] = {
        guard let daten = try? Data(contentsOf: Orte.gifNutzung),
              let roh = try? JSONSerialization.jsonObject(with: daten) as? [String: [String: Any]]
        else { return [:] }
        return roh
    }()

    /// Liefert den Inhalt für einen Pfad. Wird vom Fenster gesetzt, damit der
    /// Server nichts über Startseite oder Bibliothek wissen muss.
    var startseiteHTML: () -> String = { "<h1>Startseite fehlt</h1>" }

    /// Laeuft hier schon eine Lernkiste? Zwei gleichzeitig gehen nicht: beide
    /// brauchen denselben Port, und die zweite bliebe leer. Wir klopfen kurz an —
    /// antwortet jemand, ist bereits eine offen.
    static func laeuftSchon() -> Bool {
        let verbindung = socket(AF_INET, SOCK_STREAM, 0)
        guard verbindung >= 0 else { return false }
        defer { close(verbindung) }

        // Nicht ewig warten: auf dem eigenen Rechner antwortet ein offener
        // Port sofort, ein geschlossener ebenso sofort mit einer Absage.
        var frist = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(verbindung, SOL_SOCKET, SO_SNDTIMEO, &frist,
                   socklen_t(MemoryLayout<timeval>.size))

        var adresse = sockaddr_in()
        adresse.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        adresse.sin_family = sa_family_t(AF_INET)
        adresse.sin_port   = Server.port.bigEndian
        adresse.sin_addr.s_addr = inet_addr("127.0.0.1")

        return withUnsafePointer(to: &adresse) { zeiger in
            zeiger.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(verbindung, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    func starten() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                 port: .init(rawValue: Server.port)!)
        params.allowLocalEndpointReuse = true

        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] verbindung in
            self?.bedienen(verbindung)
        }
        l.start(queue: queue)
        listener = l
    }

    // MARK: - Verbindung

    private func bedienen(_ verbindung: NWConnection) {
        verbindung.start(queue: queue)
        verbindung.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] daten, _, _, _ in
            guard let self, let daten, !daten.isEmpty,
                  let anfrage = String(data: daten, encoding: .utf8) ?? String(data: daten, encoding: .isoLatin1)
            else { verbindung.cancel(); return }

            let antwort = self.antwort(auf: anfrage)
            verbindung.send(content: antwort, completion: .contentProcessed { _ in
                verbindung.cancel()
            })
        }
    }

    private func antwort(auf anfrage: String) -> Data {
        let zeilen = anfrage.components(separatedBy: "\r\n")
        guard let start = zeilen.first else { return fehler(400, "Kaputte Anfrage") }
        let teile = start.components(separatedBy: " ")
        guard teile.count >= 2, teile[0] == "GET" else { return fehler(405, "Nur GET") }

        // Schutz gegen Zugriffe von außerhalb (DNS-Rebinding): der Host-Kopf muss
        // wirklich auf unseren lokalen Port zeigen.
        let host = zeilen.first { $0.lowercased().hasPrefix("host:") }?
            .dropFirst(5).trimmingCharacters(in: .whitespaces) ?? ""
        guard host == "127.0.0.1:\(Server.port)" || host == "localhost:\(Server.port)" else {
            return fehler(403, "Fremder Host")
        }

        var pfad = teile[1]
        if let fragezeichen = pfad.firstIndex(of: "?") { pfad = String(pfad[pfad.startIndex..<fragezeichen]) }
        pfad = pfad.removingPercentEncoding ?? pfad

        switch true {
        case pfad == "/" || pfad == "/start":
            return ok(Data(startseiteHTML().utf8), typ: "text/html; charset=utf-8", cachen: false)

        case pfad.hasPrefix("/seite/"):
            let relativ = String(pfad.dropFirst("/seite/".count))
            return datei(relativ: relativ, basis: Orte.seiten)

        case pfad.hasPrefix("/gif/"):
            let relativ = String(pfad.dropFirst("/gif/".count))
            let antwort = datei(relativ: relativ, basis: Orte.gifs)
            gifGezaehlt(relativ)
            return antwort

        case pfad.hasPrefix("/res/"):
            let relativ = String(pfad.dropFirst("/res/".count))
            return datei(relativ: relativ, basis: Orte.ressourcen)

        default:
            return fehler(404, "Nicht gefunden")
        }
    }

    // MARK: - GIF-Strichliste

    /// Zaehlt eine Auslieferung mit und schreibt die Liste sofort weg — die
    /// Datei ist winzig, dafuer geht beim Beenden der App nichts verloren.
    private func gifGezaehlt(_ relativ: String) {
        let pfad = Orte.gifs.appendingPathComponent(relativ).standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: pfad) else { return }
        var eintrag = gifNutzung[relativ] ?? [:]
        eintrag["n"] = ((eintrag["n"] as? Int) ?? 0) + 1
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        eintrag["zuletzt"] = formatter.string(from: Date())
        gifNutzung[relativ] = eintrag
        if let daten = try? JSONSerialization.data(withJSONObject: gifNutzung,
                                                   options: [.prettyPrinted, .sortedKeys]) {
            try? daten.write(to: Orte.gifNutzung)
        }
    }

    // MARK: - Dateien

    private func datei(relativ: String, basis: URL) -> Data {
        // Pfad-Ausbruch verhindern: der aufgelöste Pfad muss unterhalb der Basis liegen.
        guard !relativ.contains("..") else { return fehler(403, "Verboten") }
        let ziel = basis.appendingPathComponent(relativ).standardizedFileURL
        let wurzel = basis.standardizedFileURL.path
        guard ziel.path.hasPrefix(wurzel + "/") else { return fehler(403, "Verboten") }
        guard let inhalt = try? Data(contentsOf: ziel) else { return fehler(404, "Nicht gefunden") }
        return ok(inhalt, typ: Server.typ(fuer: ziel.pathExtension), cachen: false)
    }

    static func typ(fuer endung: String) -> String {
        switch endung.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "js":          return "text/javascript; charset=utf-8"
        case "json":        return "application/json; charset=utf-8"
        case "svg":         return "image/svg+xml"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "pdf":         return "application/pdf"
        case "woff2":       return "font/woff2"
        default:            return "application/octet-stream"
        }
    }

    // MARK: - Antworten bauen

    private func ok(_ koerper: Data, typ: String, cachen: Bool) -> Data {
        kopf(200, "OK", typ: typ, laenge: koerper.count, cachen: cachen) + koerper
    }

    private func fehler(_ code: Int, _ text: String) -> Data {
        let koerper = Data("<!DOCTYPE html><meta charset=utf-8><p>\(text)".utf8)
        return kopf(code, text, typ: "text/html; charset=utf-8",
                    laenge: koerper.count, cachen: false) + koerper
    }

    private func kopf(_ code: Int, _ text: String, typ: String, laenge: Int, cachen: Bool) -> Data {
        var k = "HTTP/1.1 \(code) \(text)\r\n"
        k += "Content-Type: \(typ)\r\n"
        k += "Content-Length: \(laenge)\r\n"
        k += cachen ? "Cache-Control: max-age=3600\r\n" : "Cache-Control: no-store\r\n"
        k += "Connection: close\r\n\r\n"
        return Data(k.utf8)
    }
}

extension Orte {
    /// Mitgelieferte Dateien im App-Bündel (tokens.css, bruecke.js …)
    static var ressourcen: URL {
        Bundle.main.resourceURL ?? Bundle.main.bundleURL
    }
}
