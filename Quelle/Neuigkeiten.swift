import AppKit

/// Was mit den letzten Updates neu kam. Steht in Ressourcen/neuigkeiten.json,
/// neuestes Update zuerst. Das ⓘ oben rechts bekommt einen Punkt, solange der
/// neueste Eintrag noch nicht angesehen wurde. Punkte mit „[mac] “ oder
/// „[win] “ erscheinen nur in der jeweiligen Fassung.
struct Neuigkeit: Decodable {
    let datum: String       // JJJJ-MM-TT
    let punkte: [String]
}

enum Neuigkeiten {

    static let alle: [Neuigkeit] = {
        guard let url = Bundle.main.url(forResource: "neuigkeiten", withExtension: "json"),
              let daten = try? Data(contentsOf: url),
              let liste = try? JSONDecoder().decode([Neuigkeit].self, from: daten)
        else { return [] }
        return liste
    }()

    /// Kennzeichen des neuesten Eintrags. Ändert sich auch, wenn am selben Tag
    /// noch ein Punkt dazukommt.
    private static var kennung: String? {
        alle.first.map { ([$0.datum] + $0.punkte).joined(separator: "|") }
    }

    static var ungelesen: Bool {
        guard let kennung else { return false }
        return Zustand.aktuell.neuigkeitGesehen != kennung
    }

    static func gelesen() {
        guard let kennung, Zustand.aktuell.neuigkeitGesehen != kennung else { return }
        Zustand.aktuell.neuigkeitGesehen = kennung
        Zustand.aktuell.sichern()
    }

    /// Inhalt des Aufklappfensters: je Update das Datum, darunter die Punkte.
    static func ansicht() -> NSViewController {
        let breite: CGFloat = 360
        let text = NSMutableAttributedString()
        let absatz = NSMutableParagraphStyle()
        absatz.paragraphSpacing = 5
        absatz.headIndent = 14
        absatz.firstLineHeadIndent = 0
        absatz.tabStops = [NSTextTab(textAlignment: .left, location: 14)]
        let kopf = NSMutableParagraphStyle()
        kopf.paragraphSpacingBefore = 8
        kopf.paragraphSpacing = 4

        text.append(NSAttributedString(string: "Neu in der Lernkiste\n", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor]))
        if alle.isEmpty {
            text.append(NSAttributedString(string: "Hier steht nach dem nächsten Update, was sich geändert hat.", attributes: [
                .font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        for eintrag in alle {
            let punkte = eintrag.punkte.compactMap(fuerDenMac)
            if punkte.isEmpty { continue }
            text.append(NSAttributedString(string: datumLesbar(eintrag.datum) + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: kopf]))
            for punkt in punkte {
                text.append(NSAttributedString(string: "•\t" + punkt + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 12.5),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: absatz]))
            }
        }

        let feld = NSTextView(frame: NSRect(x: 0, y: 0, width: breite, height: 10))
        feld.textStorage?.setAttributedString(text)
        feld.isEditable = false
        feld.drawsBackground = false
        feld.textContainerInset = NSSize(width: 14, height: 12)
        feld.isVerticallyResizable = true
        feld.textContainer?.widthTracksTextView = true
        feld.layoutManager?.ensureLayout(for: feld.textContainer!)
        let hoehe = (feld.layoutManager?.usedRect(for: feld.textContainer!).height ?? 200) + 26

        let rolle = NSScrollView(frame: NSRect(x: 0, y: 0, width: breite, height: min(hoehe, 460)))
        rolle.documentView = feld
        rolle.hasVerticalScroller = hoehe > 460
        rolle.drawsBackground = false
        feld.frame.size.height = hoehe

        let c = NSViewController()
        c.view = rolle
        return c
    }

    /// „[win] …“ gilt nur fuer Windows, „[mac] …“ nur hier.
    private static func fuerDenMac(_ punkt: String) -> String? {
        if punkt.hasPrefix("[win] ") { return nil }
        return punkt.hasPrefix("[mac] ") ? String(punkt.dropFirst(6)) : punkt
    }

    private static func datumLesbar(_ iso: String) -> String {
        let ein = DateFormatter()
        ein.locale = Locale(identifier: "en_US_POSIX")
        ein.dateFormat = "yyyy-MM-dd"
        guard let d = ein.date(from: iso) else { return iso }
        let aus = DateFormatter()
        aus.locale = Locale(identifier: "de_DE")
        aus.dateFormat = "d. MMMM yyyy"
        return aus.string(from: d)
    }
}
