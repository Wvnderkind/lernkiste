import AppKit

/// Gibt Lernseiten weiter — ueber das Teilen-Menue von macOS (AirDrop,
/// Nachrichten, Mail …). Eine einzelne Seite geht als .html-Datei hinaus,
/// ein ganzes Thema oder Fach als ZIP-Paket mit den Ordnern Fach/Thema.
/// Der Lernstand bleibt immer hier: er steckt nicht in der Datei.
enum Export {

    /// Arbeitsordner fuer die Pakete. Wird vor jedem Export geleert — hier
    /// liegen nur Kopien, nie die Seiten selbst.
    private static let ablage = FileManager.default.temporaryDirectory
        .appendingPathComponent("Lernkiste-Export")

    /// - Parameters:
    ///   - seiten: was hinausgehen soll
    ///   - name:   Name des Pakets, wenn es mehr als eine Seite ist
    static func teilen(_ seiten: [Seite], name: String, von ansicht: NSView, bei rechteck: NSRect) {
        guard !seiten.isEmpty else { return }
        let datei: URL
        if seiten.count == 1 {
            datei = seiten[0].datei
        } else {
            guard let paket = paketBauen(seiten, name: name) else {
                melden("Das Paket ließ sich nicht packen.")
                return
            }
            datei = paket
        }
        let picker = NSSharingServicePicker(items: [datei])
        picker.show(relativeTo: rechteck, of: ansicht, preferredEdge: .maxY)
    }

    /// Packt die Seiten als <Paket>/<Fach>/<Thema>/<datei>.html in ein ZIP.
    /// So landen auch Seiten ohne Kennung beim Empfaenger im richtigen Fach
    /// und Thema.
    private static func paketBauen(_ seiten: [Seite], name: String) -> URL? {
        let fm = FileManager.default
        try? fm.removeItem(at: ablage)
        let paketName = dateiname("\(name) (Lernkiste)")
        var eintraege: [(pfad: String, daten: Data)] = []
        for seite in seiten {
            guard let daten = try? Data(contentsOf: seite.datei) else { return nil }
            // NFC: macOS legt Umlaute in Dateinamen oft zerlegt ab (a + ¨),
            // Windows erwartet sie als ein Zeichen.
            let pfad = [paketName, dateiname(seite.fach), dateiname(seite.thema),
                        seite.datei.lastPathComponent].joined(separator: "/")
                .precomposedStringWithCanonicalMapping
            eintraege.append((pfad, daten))
        }
        let zip = ablage.appendingPathComponent(paketName + ".zip")
        do {
            try fm.createDirectory(at: ablage, withIntermediateDirectories: true)
            try Zip.packen(eintraege).write(to: zip)
        } catch {
            return nil
        }
        return zip
    }

    /// Ordner- und Paketnamen ohne Zeichen, die im Dateisystem stoeren.
    private static func dateiname(_ s: String) -> String {
        let n = s.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Lernseiten" : n
    }

    private static func melden(_ text: String) {
        let hinweis = NSAlert()
        hinweis.messageText = text
        hinweis.addButton(withTitle: "OK")
        hinweis.runModal()
    }
}

/// Ein schlichtes ZIP ohne Kompression. Eigenbau statt ditto oder zip, weil
/// beide Umlaute in Ordnernamen nicht als UTF-8 kennzeichnen — unter Windows
/// wird aus „Großhirn“ sonst „Gro├ƒhirn“.
enum Zip {
    static func packen(_ eintraege: [(pfad: String, daten: Data)]) -> Data {
        var ausgabe = Data(), verzeichnis = Data()
        let (zeit, datum) = dosZeit(Date())
        for e in eintraege {
            let name = Data(e.pfad.utf8)
            let pruef = crc32(e.daten)
            let versatz = UInt32(ausgabe.count)
            // Lokaler Kopf
            ausgabe.le32(0x04034b50); ausgabe.le16(20); ausgabe.le16(0x0800)   // Bit 11: Namen in UTF-8
            ausgabe.le16(0); ausgabe.le16(zeit); ausgabe.le16(datum)
            ausgabe.le32(pruef); ausgabe.le32(UInt32(e.daten.count)); ausgabe.le32(UInt32(e.daten.count))
            ausgabe.le16(UInt16(name.count)); ausgabe.le16(0)
            ausgabe.append(name); ausgabe.append(e.daten)
            // Eintrag im Inhaltsverzeichnis am Ende
            verzeichnis.le32(0x02014b50); verzeichnis.le16(20); verzeichnis.le16(20)
            verzeichnis.le16(0x0800); verzeichnis.le16(0); verzeichnis.le16(zeit); verzeichnis.le16(datum)
            verzeichnis.le32(pruef); verzeichnis.le32(UInt32(e.daten.count)); verzeichnis.le32(UInt32(e.daten.count))
            verzeichnis.le16(UInt16(name.count)); verzeichnis.le16(0); verzeichnis.le16(0)
            verzeichnis.le16(0); verzeichnis.le16(0); verzeichnis.le32(0); verzeichnis.le32(versatz)
            verzeichnis.append(name)
        }
        let beginn = UInt32(ausgabe.count)
        ausgabe.append(verzeichnis)
        ausgabe.le32(0x06054b50); ausgabe.le16(0); ausgabe.le16(0)
        ausgabe.le16(UInt16(eintraege.count)); ausgabe.le16(UInt16(eintraege.count))
        ausgabe.le32(UInt32(verzeichnis.count)); ausgabe.le32(beginn); ausgabe.le16(0)
        return ausgabe
    }

    private static func dosZeit(_ d: Date) -> (UInt16, UInt16) {
        let k = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        let zeit = (k.hour! << 11) | (k.minute! << 5) | (k.second! / 2)
        let datum = ((k.year! - 1980) << 9) | (k.month! << 5) | k.day!
        return (UInt16(zeit), UInt16(datum))
    }

    private static let tabelle: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32(_ daten: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in daten { c = tabelle[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { le16(UInt16(v & 0xFFFF)); le16(UInt16(v >> 16)) }
}
