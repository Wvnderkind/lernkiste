import Foundation

// MARK: - Orte

enum Orte {
    static let heim = FileManager.default.homeDirectoryForCurrentUser

    /// Wo die App ihre eigenen Daten ablegt — hier liest Claude den Fortschritt.
    /// Seit 21.09.2026 liegt alles gebuendelt in einem eigenen Ordner.
    static let daten = heim
        .appendingPathComponent("Documents/Lernkiste")

    /// Wo die Lernseiten liegen — als Unterordner direkt daneben.
    static let seiten = daten.appendingPathComponent("Seiten")

    static let fortschritt   = daten.appendingPathComponent("fortschritt")

    /// Glueckwunsch-GIFs, nach Anlass in Unterordner sortiert:
    /// fertig/ (Tagespensum geschafft), meilenstein/ (Serie, Wackler sitzt),
    /// durchhaenger/ (etwas will einfach nicht sitzen).
    static let gifs          = daten.appendingPathComponent("gifs")
    static let gifAnlaesse   = ["fertig", "meilenstein", "durchhaenger"]
    /// Strichliste der ausgelieferten GIFs, damit sich alle zwei Wochen sehen
    /// laesst, welche laufen und welche ausgetauscht gehoeren.
    static let gifNutzung    = gifs.appendingPathComponent("nutzung.json")
    static let tagesplanDatei = daten.appendingPathComponent("tagesplan.json")
    static let konfigDatei   = daten.appendingPathComponent("konfiguration.json")
    static let zustandDatei  = daten.appendingPathComponent("zustand.json")

    static func vorbereiten() {
        for ordner in [daten, seiten, fortschritt, gifs]
                        + gifAnlaesse.map({ gifs.appendingPathComponent($0) }) {
            try? FileManager.default.createDirectory(at: ordner,
                                                     withIntermediateDirectories: true)
        }
    }
}

// MARK: - Bibliothek

struct Seite: Identifiable, Hashable {
    let id: String              // "chemie/redox/oxidationszahlen"
    let titel: String
    let typ: String             // schema | tabelle | drill | mechanismus | zuordnung | kompendium
    let version: Int
    let fach: String            // Anzeigename, z. B. "Chemie"
    let thema: String           // Anzeigename, z. B. "Redox"
    let datei: URL
    let relativerPfad: String   // "Chemie/Redox/oxidationszahlen.html"
    let spec: Bool              // erfüllt den Lernkiste-Vertrag (hat Meta-Block)
    let geaendert: Date
}

struct Thema: Identifiable, Hashable {
    let id: String
    let name: String
    var seiten: [Seite]
}

struct Fach: Identifiable, Hashable {
    let id: String
    let name: String
    var themen: [Thema]
    var archiv: Bool            // abgeschlossenes Fach → Bereich "Fürs Physikum"

    var alleSeiten: [Seite] { themen.flatMap(\.seiten) }
}

/// Liest den Lernseiten-Ordner ein und baut daraus den Baum Fach → Thema → Seite.
enum Bibliothek {

    static func einlesen() -> [Fach] {
        let fm = FileManager.default
        let konfig = Konfiguration.laden()
        var faecher: [Fach] = []

        let fachOrdner = (try? fm.contentsOfDirectory(at: Orte.seiten,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles])) ?? []

        for fachURL in fachOrdner.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard istOrdner(fachURL) else { continue }
            let fachName = fachURL.lastPathComponent
            var themen: [Thema] = []

            let themaOrdner = (try? fm.contentsOfDirectory(at: fachURL,
                                                          includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles])) ?? []

            for themaURL in themaOrdner.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard istOrdner(themaURL) else { continue }
                let themaName = themaURL.lastPathComponent

                let dateien = (try? fm.contentsOfDirectory(at: themaURL,
                                                           includingPropertiesForKeys: [.contentModificationDateKey],
                                                           options: [.skipsHiddenFiles])) ?? []
                var seiten: [Seite] = []
                // Dateien mit führendem _ sind Hilfs-/Testdateien und keine Lernseiten.
                for datei in dateien where datei.pathExtension.lowercased() == "html"
                    && !datei.lastPathComponent.hasPrefix("_") {
                    if let seite = seiteLesen(datei: datei, fach: fachName, thema: themaName) {
                        seiten.append(seite)
                    }
                }
                guard !seiten.isEmpty else { continue }
                seiten.sort { $0.titel.localizedCaseInsensitiveCompare($1.titel) == .orderedAscending }
                themen.append(Thema(id: "\(fachName)/\(themaName)", name: themaName, seiten: seiten))
            }

            guard !themen.isEmpty else { continue }
            faecher.append(Fach(id: fachName,
                                name: fachName,
                                themen: themen,
                                archiv: konfig.archivFaecher.contains(fachName)))
        }

        // Aktive Fächer zuerst, danach das Archiv — jeweils alphabetisch.
        return faecher.sorted {
            if $0.archiv != $1.archiv { return !$0.archiv }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func istOrdner(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Liest Kopfdaten aus der HTML-Datei. Seiten ohne Meta-Block werden trotzdem
    /// aufgenommen — sie funktionieren, zeigen aber weniger Fortschrittsdetails.
    private static func seiteLesen(datei: URL, fach: String, thema: String) -> Seite? {
        let kopf = kopfLesen(datei)   // nur die ersten Kilobytes, nicht die ganze Datei
        let geaendert = (try? datei.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? Date.distantPast

        let metaID  = meta(kopf, "lernkiste-id")
        let spec    = metaID != nil
        let slug    = datei.deletingPathExtension().lastPathComponent
        let id      = metaID ?? "\(entschaerft(fach))/\(entschaerft(thema))/\(entschaerft(slug))"
        let titel   = meta(kopf, "lernkiste-titel") ?? titelTag(kopf) ?? slug
        let typ     = meta(kopf, "lernkiste-typ") ?? "seite"
        let version = Int(meta(kopf, "lernkiste-version") ?? "1") ?? 1

        return Seite(id: id, titel: titel, typ: typ, version: version,
                     fach: fach, thema: thema, datei: datei,
                     relativerPfad: "\(fach)/\(thema)/\(datei.lastPathComponent)",
                     spec: spec, geaendert: geaendert)
    }

    private static func kopfLesen(_ datei: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: datei) else { return "" }
        defer { try? handle.close() }
        let daten = (try? handle.read(upToCount: 16_384)) ?? Data()
        return String(data: daten, encoding: .utf8)
            ?? String(decoding: daten, as: UTF8.self)
    }

    private static func meta(_ html: String, _ name: String) -> String? {
        let muster = "<meta\\s+name=[\"']\(name)[\"']\\s+content=[\"']([^\"']*)[\"']"
        return ersteGruppe(html, muster)
    }

    private static func titelTag(_ html: String) -> String? {
        ersteGruppe(html, "<title>([^<]*)</title>")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ersteGruppe(_ text: String, _ muster: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: muster, options: [.caseInsensitive]),
              let treffer = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              treffer.numberOfRanges > 1,
              let bereich = Range(treffer.range(at: 1), in: text)
        else { return nil }
        return String(text[bereich])
    }

    /// "Kopf-Hals" → "kopf-hals", "Hirnhäute-Liquor" → "hirnhaeute-liquor"
    static func entschaerft(_ text: String) -> String {
        var s = text.lowercased()
        for (von, nach) in [("ä","ae"), ("ö","oe"), ("ü","ue"), ("ß","ss"), (" ","-")] {
            s = s.replacingOccurrences(of: von, with: nach)
        }
        return s
    }
}

// MARK: - Konfiguration (pflege ich, Claude)

struct Termin: Codable {
    var name: String            // z. B. "Biochemie"
    var datum: String           // "JJJJ-MM-TT"
}

struct Konfiguration: Codable {
    var archivFaecher: [String] = []
    /// Optionaler Countdown auf der Startseite. Eintragen in konfiguration.json:
    /// { "naechsterTermin": { "name": "Biochemie", "datum": "2027-02-14" } }
    var naechsterTermin: Termin? = nil

    init() {}

    /// Von Hand entschluesselt, damit eine unvollstaendige Datei nicht die ganze
    /// Konfiguration verwirft — wer nur einen Termin eintraegt, soll das duerfen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        archivFaecher   = (try? c.decode([String].self, forKey: .archivFaecher)) ?? []
        naechsterTermin =  try? c.decode(Termin.self,   forKey: .naechsterTermin)
    }

    static func laden() -> Konfiguration {
        guard let daten = try? Data(contentsOf: Orte.konfigDatei),
              let k = try? JSONDecoder().decode(Konfiguration.self, from: daten)
        else { return Konfiguration() }
        return k
    }
}

// MARK: - Tagesplan (pflege ich, Claude)

struct Tagesplan: Codable {
    struct Eintrag: Codable {
        var seite: String            // Seiten-ID
        var ziel: Int?
        var schwerpunkt: String?
        var hinweis: String?
    }
    var datum: String = ""
    var ueberschrift: String?
    var eintraege: [Eintrag] = []

    static func laden() -> Tagesplan? {
        guard let daten = try? Data(contentsOf: Orte.tagesplanDatei),
              let p = try? JSONDecoder().decode(Tagesplan.self, from: daten)
        else { return nil }
        return p
    }

    /// Nur gültig, wenn der Plan für heute geschrieben wurde.
    var fuerHeute: Bool { datum == Datum.heute }

    /// Die Einträge unverändert als JSON-Text — so kommen auch Felder bei der Seite an,
    /// die dieser Typ hier gar nicht kennt (z. B. umfang, modus, kategorien).
    /// Der Weg über den Codable-Typ würde sie stillschweigend wegwerfen.
    static func rohEintraegeJSON() -> String? {
        guard let daten = try? Data(contentsOf: Orte.tagesplanDatei),
              let objekt = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              (objekt["datum"] as? String) == Datum.heute,
              let eintraege = objekt["eintraege"] as? [[String: Any]],
              let roh = try? JSONSerialization.data(withJSONObject: eintraege),
              let text = String(data: roh, encoding: .utf8)
        else { return nil }
        return text
    }

    func eintrag(fuer seitenID: String) -> Eintrag? {
        eintraege.first { $0.seite == seitenID }
    }
}

enum Datum {
    static let formatierer: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    static var heute: String { formatierer.string(from: Date()) }

    static func tageSeit(_ datum: Date) -> Int {
        Calendar.current.dateComponents([.day], from: datum, to: Date()).day ?? 0
    }
}
