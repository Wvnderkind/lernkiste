import Foundation

// MARK: - Was eine Seite über ihren Stand verrät

struct Tagespensum: Codable {
    var datum: String?
    var ziel: Int?
    var geschafft: Int?
    var treffer: Int?

    var erledigt: Bool {
        guard let ziel, let geschafft, ziel > 0 else { return false }
        return geschafft >= ziel && datum == Datum.heute
    }
}

struct SeitenStand: Codable {
    var seite: String
    var titel: String
    var fach: String
    var thema: String
    var typ: String

    /// Anzahl abfragbarer Items laut Seite.
    var gesamt: Int?
    /// Items, deren letzter Versuch "saß" war.
    var sitzen: Int = 0
    /// Items, deren letzter Versuch "saß nicht" war — die Wackelkandidaten.
    var wackel: Int = 0
    /// Items, die überhaupt schon einmal drankamen.
    var geuebt: Int = 0

    var tagespensum: Tagespensum?
    var zuletztGeoeffnet: String?
    var zuletztGeuebt: String?

    /// Namen der Wackelkandidaten — damit Claude gezielt nachfragen kann.
    var wackelItems: [String] = []

    /// Alles, was die Seite gespeichert hat, unverändert. Rettungsanker für
    /// Seiten, die den Vertrag (noch) nicht erfüllen.
    var roh: [String: String] = [:]

    var anteilSitzen: Double {
        guard let gesamt, gesamt > 0 else { return 0 }
        return Double(sitzen) / Double(gesamt)
    }
}

// MARK: - Auswerten und Ablegen

enum Fortschritt {

    /// Wertet den rohen localStorage einer Seite aus.
    /// `roh` enthält alle Schlüssel, die mit "lern:" anfangen.
    static func auswerten(roh: [String: String], seite: Seite) -> SeitenStand {
        var stand = SeitenStand(seite: seite.id, titel: seite.titel, fach: seite.fach,
                                thema: seite.thema, typ: seite.typ)
        // Alle Seiten teilen sich denselben Ursprung (127.0.0.1) und damit einen
        // localStorage. Hier nur behalten, was wirklich zu dieser Seite gehoert —
        // sonst steht in jeder Datei der Stand aller anderen Seiten mit drin.
        stand.roh = roh.filter { $0.key.hasPrefix("lern:\(seite.id)@") }
        stand.zuletztGeoeffnet = ISO.jetzt

        let hauptschluessel = "lern:\(seite.id)@v\(seite.version)"
        guard let text = roh[hauptschluessel],
              let daten = text.data(using: .utf8),
              let objekt = try? JSONSerialization.jsonObject(with: daten) as? [String: Any]
        else {
            // Seite erfüllt den Vertrag nicht — wir wissen nur, dass sie offen war.
            return stand
        }

        stand.gesamt = objekt["gesamt"] as? Int

        if let items = objekt["items"] as? [String: [String: Any]] {
            for (name, wert) in items {
                let sass      = wert["sass"] as? Int ?? 0
                let sassNicht = wert["sassNicht"] as? Int ?? 0
                guard sass + sassNicht > 0 else { continue }
                stand.geuebt += 1
                // "zuletzt" entscheidet, ob das Item aktuell sitzt.
                if let letzter = wert["letzter"] as? String {
                    if letzter == "sass" { stand.sitzen += 1 }
                    else { stand.wackel += 1; stand.wackelItems.append(name) }
                } else if sassNicht >= sass {
                    stand.wackel += 1; stand.wackelItems.append(name)
                } else {
                    stand.sitzen += 1
                }
            }
            if stand.gesamt == nil { stand.gesamt = items.count }
        }
        stand.wackelItems.sort()

        if let p = objekt["tagespensum"] as? [String: Any] {
            stand.tagespensum = Tagespensum(datum: p["datum"] as? String,
                                            ziel: p["ziel"] as? Int,
                                            geschafft: p["geschafft"] as? Int,
                                            treffer: p["treffer"] as? Int)
        }
        stand.zuletztGeuebt = objekt["zuletztGeoeffnet"] as? String
        return stand
    }

    /// Legt den Stand einer Seite als eigene Datei ab.
    static func sichern(_ stand: SeitenStand) {
        Orte.vorbereiten()
        let name = stand.seite.replacingOccurrences(of: "/", with: "__") + ".json"
        let ziel = Orte.fortschritt.appendingPathComponent(name)
        let kodierer = JSONEncoder()
        kodierer.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let daten = try? kodierer.encode(stand) else { return }
        try? daten.write(to: ziel, options: .atomic)
        uebersichtSchreiben()
    }

    /// Alle Stände geladen — für Sidebar, Startseite und für Claude.
    static func alleStaende() -> [String: SeitenStand] {
        let dateien = (try? FileManager.default.contentsOfDirectory(
            at: Orte.fortschritt, includingPropertiesForKeys: nil)) ?? []
        var ergebnis: [String: SeitenStand] = [:]
        for datei in dateien where datei.pathExtension == "json"
                                && datei.lastPathComponent != "uebersicht.json" {
            guard let daten = try? Data(contentsOf: datei),
                  let stand = try? JSONDecoder().decode(SeitenStand.self, from: daten)
            else { continue }
            ergebnis[stand.seite] = stand
        }
        return ergebnis
    }

    /// Eine einzelne Datei, die Claude zu Sessionbeginn liest.
    private static func uebersichtSchreiben() {
        struct Uebersicht: Codable {
            var erstellt: String
            var staende: [SeitenStand]
        }
        let u = Uebersicht(erstellt: ISO.jetzt,
                           staende: alleStaende().values
                            .sorted { ($0.zuletztGeoeffnet ?? "") > ($1.zuletztGeoeffnet ?? "") })
        let kodierer = JSONEncoder()
        kodierer.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let daten = try? kodierer.encode(u) else { return }
        try? daten.write(to: Orte.fortschritt.appendingPathComponent("uebersicht.json"),
                         options: .atomic)
    }
}

enum ISO {
    static let formatierer: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime,
                           .withDashSeparatorInDate]
        f.timeZone = TimeZone.current
        return f
    }()
    static var jetzt: String { formatierer.string(from: Date()) }
    static func datum(_ text: String?) -> Date? {
        guard let text else { return nil }
        return formatierer.date(from: text)
    }
}

// MARK: - Zustand der App (Favoriten, zuletzt geöffnet)

struct Zustand: Codable {
    var favoriten: [String] = []
    var zuletzt: [String] = []          // Seiten-IDs, neueste zuerst
    var theme: String = "dark"
    var letzteSeite: String?
    var neuigkeitGesehen: String?       // Kennung des zuletzt angesehenen Updates (ⓘ)
    var anleitungAusgeblendet: Bool?    // Kasten „Erste Schritte“ per × weggeklickt

    static var aktuell: Zustand = laden()

    static func laden() -> Zustand {
        guard let daten = try? Data(contentsOf: Orte.zustandDatei),
              let z = try? JSONDecoder().decode(Zustand.self, from: daten)
        else { return Zustand() }
        return z
    }

    func sichern() {
        Orte.vorbereiten()
        let kodierer = JSONEncoder()
        kodierer.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let daten = try? kodierer.encode(self) else { return }
        try? daten.write(to: Orte.zustandDatei, options: .atomic)
    }

    mutating func besucht(_ seitenID: String) {
        zuletzt.removeAll { $0 == seitenID }
        zuletzt.insert(seitenID, at: 0)
        if zuletzt.count > 8 { zuletzt = Array(zuletzt.prefix(8)) }
        letzteSeite = seitenID
        sichern()
    }

    mutating func favoritUmschalten(_ seitenID: String) {
        if favoriten.contains(seitenID) { favoriten.removeAll { $0 == seitenID } }
        else { favoriten.append(seitenID) }
        sichern()
    }

    func istFavorit(_ seitenID: String) -> Bool { favoriten.contains(seitenID) }
}
