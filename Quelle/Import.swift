import AppKit
import UniformTypeIdentifiers

/// Holt fremde oder neu gebaute Lernseiten in die Bibliothek: aus einer Datei
/// (Menue, Hineinziehen) oder direkt aus der Zwischenablage, wenn eine KI die
/// Seite im Chat ausgegeben hat. Die App legt die Seite selbst an die richtige
/// Stelle — niemand muss mehr in Ordnern suchen.
enum Import {

    // MARK: Einstiege

    static func dateienWaehlen(_ fenster: Fenster?) {
        let panel = NSOpenPanel()
        panel.title = "Lernseite importieren"
        panel.prompt = "Importieren"
        panel.allowedContentTypes = [.html, .zip]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        dateien(panel.urls, fenster)
    }

    /// Einzelne Seiten, ZIP-Pakete (aus „Teilen“) und ganze Ordner.
    static func dateien(_ urls: [URL], _ fenster: Fenster?) {
        var zuletzt: String?
        var gesamt = 0, uebernommen = 0
        for url in urls {
            for fund in seitenFinden(url) {
                gesamt += 1
                guard let daten = try? Data(contentsOf: fund.datei) else {
                    melden("„\(fund.datei.lastPathComponent)“ ließ sich nicht lesen.")
                    continue
                }
                let name = fund.datei.deletingPathExtension().lastPathComponent
                if let id = aufnehmen(text(daten), dateiname: name, vorgabe: fund.ort) {
                    zuletzt = id
                    uebernommen += 1
                }
            }
        }
        try? FileManager.default.removeItem(at: entpackOrt)
        if gesamt == 0 && !urls.isEmpty {
            melden("Darin steckt keine Lernseite.",
                   "Importieren lassen sich .html-Seiten und ZIP-Pakete, die mit „Teilen“ entstanden sind.")
        } else if gesamt > 1 {
            hinweisPaket(uebernommen, von: gesamt)
        }
        abschliessen(zuletzt, fenster)
    }

    /// Arbeitsordner fuers Entpacken; wird nach jedem Import geleert.
    private static let entpackOrt = FileManager.default.temporaryDirectory
        .appendingPathComponent("Lernkiste-Import")

    /// Alle Lernseiten hinter einer URL. Liegt eine Seite in Paket/Fach/Thema/,
    /// gilt das als Vorschlag fuer den Ort — falls sie selbst keine Kennung traegt.
    private static func seitenFinden(_ url: URL) -> [(datei: URL, ort: (fach: String, thema: String)?)] {
        let endung = url.pathExtension.lowercased()
        if ["html", "htm"].contains(endung) { return [(url, nil)] }
        var wurzel = url
        if endung == "zip" {
            let ziel = entpackOrt.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
            let entpacker = Process()
            entpacker.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            entpacker.arguments = ["-x", "-k", url.path, ziel.path]
            do { try entpacker.run() } catch { return [] }
            entpacker.waitUntilExit()
            guard entpacker.terminationStatus == 0 else {
                melden("„\(url.lastPathComponent)“ ließ sich nicht entpacken.")
                return []
            }
            wurzel = ziel
        }
        var istOrdner: ObjCBool = false
        guard FileManager.default.fileExists(atPath: wurzel.path, isDirectory: &istOrdner),
              istOrdner.boolValue,
              let alle = FileManager.default.enumerator(at: wurzel, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])
        else { return [] }
        var funde: [(URL, (fach: String, thema: String)?)] = []
        let basis = wurzel.resolvingSymlinksInPath().pathComponents.count
        for case let datei as URL in alle {
            let teile = datei.resolvingSymlinksInPath().pathComponents
            // Motor, Archiv und Mac-Beiwerk gehoeren nicht dazu.
            if teile.dropFirst(basis).contains(where: { $0.hasPrefix("_") }) { continue }
            guard ["html", "htm"].contains(datei.pathExtension.lowercased()) else { continue }
            let tiefe = teile.count - basis          // 1 = liegt direkt im Paket
            let ort = tiefe >= 3 ? (fach: ordnerSicher(teile[teile.count - 3]),
                                    thema: ordnerSicher(teile[teile.count - 2])) : nil
            funde.append((datei, ort))
        }
        return funde.sorted { $0.0.path < $1.0.path }
    }

    private static func hinweisPaket(_ n: Int, von gesamt: Int) {
        let hinweis = NSAlert()
        hinweis.messageText = n == gesamt
            ? "\(n) Seiten übernommen"
            : "\(n) von \(gesamt) Seiten übernommen"
        hinweis.informativeText = "Sie stehen jetzt in der Seitenleiste. "
            + "Seiten, die du schon hattest, blieben unverändert oder liegen in der alten Fassung im Archiv."
        hinweis.addButton(withTitle: "Gut")
        hinweis.runModal()
    }

    static func ausZwischenablage(_ fenster: Fenster?) {
        let brett = NSPasteboard.general
        let roh = brett.string(forType: .string) ?? brett.string(forType: .html) ?? ""
        guard let html = htmlHerausloesen(roh) else {
            melden("In der Zwischenablage liegt keine Lernseite.",
                   "Kopiere die komplette Seite, wie die KI sie ausgegeben hat — "
                   + "von <!DOCTYPE html> bis </html>.")
            return
        }
        abschliessen(aufnehmen(html, dateiname: nil, vorgabe: nil), fenster)
    }

    static func bauanleitungKopieren() {
        let datei = Orte.ressourcen.appendingPathComponent("ki-vorlage.md")
        guard let text = try? String(contentsOf: datei, encoding: .utf8) else {
            melden("Die Bauanleitung fehlt im Programm.")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let hinweis = NSAlert()
        hinweis.messageText = "Bauanleitung kopiert"
        hinweis.informativeText =
            "Füge sie in den Chat einer beliebigen KI ein und schreib dazu, "
            + "zu welchem Thema du eine Lernseite willst.\n\n"
            + "Die fertige Seite kopierst du, dann „Ablage → Seite aus Zwischenablage "
            + "einfügen“ — die Lernkiste sortiert sie selbst ein."
        hinweis.addButton(withTitle: "Gut")
        hinweis.runModal()
    }

    // MARK: Kern

    /// Legt die Seite ab und liefert ihre id — oder nil, wenn abgebrochen wurde.
    private static func aufnehmen(_ html: String, dateiname: String?,
                                  vorgabe: (fach: String, thema: String)?) -> String? {
        guard siehtAusWieHTML(html) else {
            melden("Das ist keine HTML-Seite.")
            return nil
        }
        let faecher = Bibliothek.einlesen()
        let metaID = Bibliothek.meta(html, "lernkiste-id")
        let titel = Bibliothek.meta(html, "lernkiste-titel") ?? titelTag(html)

        let ziel: URL
        if let metaID, let vorhanden = faecher.flatMap(\.alleSeiten).first(where: { $0.id == metaID }) {
            // Gleiche id = gleiche Seite, auch wenn die Datei anders heisst.
            ziel = vorhanden.datei
        } else if let metaID, let teile = idTeile(metaID) {
            let fach = ordnerName(teile.fach, unter: Orte.seiten)
            let thema = ordnerName(teile.thema, unter: Orte.seiten.appendingPathComponent(fach))
            ziel = Orte.seiten.appendingPathComponent(fach)
                .appendingPathComponent(thema)
                .appendingPathComponent(teile.slug + ".html")
        } else {
            // Keine Kennung in der Seite: der Ordner im Paket sagt, wohin sie
            // gehoert — sonst fragen.
            let vorschlag = vorgabe.flatMap { $0.fach.isEmpty || $0.thema.isEmpty ? nil : $0 }
            guard let ort = vorschlag ?? ortErfragen(faecher, titel: titel) else { return nil }
            let slug = sauber(Bibliothek.entschaerft(dateiname ?? titel ?? "lernseite"))
            ziel = Orte.seiten.appendingPathComponent(ort.fach)
                .appendingPathComponent(ort.thema)
                .appendingPathComponent((slug.isEmpty ? "lernseite" : slug) + ".html")
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: ziel.path) {
            let alt = (try? String(contentsOf: ziel, encoding: .utf8)) ?? ""
            if alt != html {
                guard ersetzenBestaetigt(ziel, alt: alt, neu: html) else { return nil }
                guard archivieren(ziel) else {
                    melden("Die alte Fassung ließ sich nicht archivieren — nichts verändert.")
                    return nil
                }
            }
        }
        do {
            try fm.createDirectory(at: ziel.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try html.write(to: ziel, atomically: true, encoding: .utf8)
        } catch {
            melden("Die Seite ließ sich nicht speichern.", error.localizedDescription)
            return nil
        }
        if let metaID { return metaID }
        // Ohne Kennung vergibt die Bibliothek sie aus dem Pfad.
        return Bibliothek.einlesen().flatMap(\.alleSeiten)
            .first(where: { $0.datei.standardizedFileURL == ziel.standardizedFileURL })?.id
    }

    private static func abschliessen(_ id: String?, _ fenster: Fenster?) {
        guard let fenster else { return }
        fenster.bibliothekNeuLaden()
        if let id { fenster.seiteOeffnenPerID(id) }
    }

    // MARK: Ablage

    /// "chemie/saeure-base/ph-und-titration" → Fach, Thema, Dateiname.
    /// Alles, was einen Pfad verbiegen koennte, faellt dabei heraus.
    private static func idTeile(_ id: String) -> (fach: String, thema: String, slug: String)? {
        let teile = id.split(separator: "/").map { sauber(String($0)) }
        guard teile.count >= 3, !teile[0].isEmpty, !teile[1].isEmpty, !teile.last!.isEmpty
        else { return nil }
        return (teile[0], teile[1], teile.last!)
    }

    private static func sauber(_ teil: String) -> String {
        let erlaubt = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        var s = String(teil.lowercased().unicodeScalars.filter { erlaubt.contains($0) })
        while s.hasPrefix("_") || s.hasPrefix("-") { s.removeFirst() }
        return s
    }

    /// Nimmt einen vorhandenen Ordner, wenn er zur Kennung passt
    /// ("saeure-base" findet "Saeure-Base"), sonst einen neuen mit grossen Anfaengen.
    private static func ordnerName(_ kennung: String, unter basis: URL) -> String {
        let vorhanden = (try? FileManager.default.contentsOfDirectory(atPath: basis.path)) ?? []
        if let treffer = vorhanden.first(where: {
            !$0.hasPrefix("_") && !$0.hasPrefix(".") && Bibliothek.entschaerft($0) == kennung
        }) { return treffer }
        return kennung.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: "-")
    }

    private static func archivieren(_ datei: URL) -> Bool {
        let stempel: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd-HHmmss"
            return f.string(from: Date())
        }()
        let relativ = datei.path.replacingOccurrences(of: Orte.seiten.path + "/", with: "")
        let ziel = Orte.daten.appendingPathComponent("_archiv")
            .appendingPathComponent("\(stempel)-import")
            .appendingPathComponent(relativ)
        do {
            try FileManager.default.createDirectory(at: ziel.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: datei, to: ziel)
            return true
        } catch {
            return false
        }
    }

    // MARK: Rueckfragen

    private static func ersetzenBestaetigt(_ ziel: URL, alt: String, neu: String) -> Bool {
        let altV = Int(Bibliothek.meta(alt, "lernkiste-version") ?? "1") ?? 1
        let neuV = Int(Bibliothek.meta(neu, "lernkiste-version") ?? "1") ?? 1
        let frage = NSAlert()
        frage.messageText = "Diese Seite gibt es schon"
        var text = "„\(ziel.deletingPathExtension().lastPathComponent)“ liegt bereits in der Lernkiste. "
            + "Die alte Fassung wandert ins Archiv, nichts geht verloren."
        if neuV < altV {
            text += "\n\nAchtung: Die neue Fassung hat eine ältere Versionsnummer (\(neuV) statt \(altV))."
        } else if neuV > altV {
            text += "\n\nDie Versionsnummer steigt von \(altV) auf \(neuV) — der bisherige Lernstand "
                + "dieser Seite beginnt dann von vorn."
        }
        frage.informativeText = text
        frage.addButton(withTitle: "Ersetzen")
        frage.addButton(withTitle: "Abbrechen")
        return frage.runModal() == .alertFirstButtonReturn
    }

    private static func ortErfragen(_ faecher: [Fach], titel: String?) -> (fach: String, thema: String)? {
        let helfer = OrtWahl(faecher)
        let frage = NSAlert()
        frage.messageText = "Wohin gehört die Seite?"
        frage.informativeText = (titel.map { "„\($0)“ " } ?? "Die Seite ")
            + "trägt keine Kennung. Wähle ein Fach und ein Thema — oder tippe neue Namen ein."
        frage.accessoryView = helfer.ansicht
        frage.addButton(withTitle: "Ablegen")
        frage.addButton(withTitle: "Abbrechen")
        frage.window.initialFirstResponder = helfer.fach
        guard frage.runModal() == .alertFirstButtonReturn else { return nil }
        let fach = ordnerSicher(helfer.fach.stringValue)
        let thema = ordnerSicher(helfer.thema.stringValue)
        guard !fach.isEmpty, !thema.isEmpty else {
            melden("Fach und Thema brauchen einen Namen.")
            return nil
        }
        return (fach, thema)
    }

    /// Ordnernamen duerfen Grossbuchstaben und Umlaute behalten — nur keine
    /// Schraegstriche und keinen fuehrenden Punkt oder Unterstrich.
    private static func ordnerSicher(_ name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        while s.hasPrefix(".") || s.hasPrefix("_") { s.removeFirst() }
        return s
    }

    private static func melden(_ text: String, _ detail: String = "") {
        let hinweis = NSAlert()
        hinweis.messageText = text
        hinweis.informativeText = detail
        hinweis.addButton(withTitle: "OK")
        hinweis.runModal()
    }

    // MARK: Text

    private static func text(_ daten: Data) -> String {
        String(data: daten, encoding: .utf8) ?? String(decoding: daten, as: UTF8.self)
    }

    private static func siehtAusWieHTML(_ s: String) -> Bool {
        let klein = s.prefix(4096).lowercased()
        return klein.contains("<html") || klein.contains("<!doctype html")
    }

    /// KIs verpacken Seiten gern in ```html … ``` und schreiben Saetze drumherum.
    /// Hier bleibt nur die Seite selbst uebrig.
    static func htmlHerausloesen(_ roh: String) -> String? {
        guard let anfang = roh.range(of: "<!doctype html", options: .caseInsensitive)
                ?? roh.range(of: "<html", options: .caseInsensitive),
              let ende = roh.range(of: "</html>", options: [.caseInsensitive, .backwards]),
              anfang.lowerBound < ende.upperBound
        else { return nil }
        return String(roh[anfang.lowerBound..<ende.upperBound]) + "\n"
    }

    private static func titelTag(_ html: String) -> String? {
        guard let a = html.range(of: "<title>", options: .caseInsensitive),
              let b = html.range(of: "</title>", options: .caseInsensitive, range: a.upperBound..<html.endIndex)
        else { return nil }
        let t = html[a.upperBound..<b.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// Zwei Auswahlfelder fuer Fach und Thema; die Themenliste folgt dem Fach.
private final class OrtWahl: NSObject, NSComboBoxDelegate {
    let fach = NSComboBox()
    let thema = NSComboBox()
    let ansicht: NSView
    private let themen: [String: [String]]

    init(_ faecher: [Fach]) {
        var t: [String: [String]] = [:]
        for f in faecher { t[f.name] = f.themen.map(\.name) }
        themen = t
        let raster = NSGridView(views: [
            [NSTextField(labelWithString: "Fach:"), fach],
            [NSTextField(labelWithString: "Thema:"), thema],
        ])
        raster.rowSpacing = 8
        raster.columnSpacing = 8
        raster.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
        ansicht = raster
        super.init()
        for feld in [fach, thema] {
            feld.completes = true
            feld.widthAnchor.constraint(equalToConstant: 230).isActive = true
        }
        fach.addItems(withObjectValues: faecher.map(\.name))
        fach.delegate = self
        if let erstes = faecher.first?.name {
            fach.stringValue = erstes
            themenZeigen(erstes)
        }
    }

    func comboBoxSelectionDidChange(_ note: Notification) {
        guard note.object as? NSComboBox === fach,
              let gewaehlt = fach.objectValueOfSelectedItem as? String else { return }
        themenZeigen(gewaehlt)
    }

    private func themenZeigen(_ fachName: String) {
        thema.removeAllItems()
        let liste = themen[fachName] ?? []
        thema.addItems(withObjectValues: liste)
        thema.stringValue = liste.first ?? ""
    }
}
