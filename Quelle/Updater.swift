import AppKit

/// Holt neue Fassungen der Lernkiste von GitHub und spielt sie ein.
///
/// Nur in der öffentlichen Fassung eingeschaltet: deren bauen.sh schreibt
/// `LernkisteUpdates` und `LernkisteStand` in die Info.plist. Die eigene App
/// hat beides nicht und bleibt damit unberührt — ein Update würde sie sonst
/// durch die neutrale Fassung ersetzen.
///
/// Ablauf: `STAND` im Repo mit dem eigenen Stand vergleichen → Knopf zeigen →
/// auf Klick das Repo als ZIP laden, entpacken, prüfen → alte App in den
/// Papierkorb, neue an ihre Stelle → neu starten. Lernseiten und Fortschritt
/// liegen in Dokumente/Lernkiste und werden dabei nicht angefasst.
final class Updater: NSObject {
    static let shared = Updater()

    // Zum Testen laesst sich die Quelle umlenken (LERNKISTE_UPDATE_QUELLE=http://…/),
    // dort muessen dann STAND und main.zip liegen.
    private static let testQuelle = ProcessInfo.processInfo.environment["LERNKISTE_UPDATE_QUELLE"]
    private let standURL = testQuelle.map { $0 + "STAND" }
        ?? "https://raw.githubusercontent.com/Wvnderkind/lernkiste/main/STAND"
    private let paketURL = testQuelle.map { $0 + "main.zip" }
        ?? "https://github.com/Wvnderkind/lernkiste/archive/refs/heads/main.zip"
    private let protokoll = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Lernkiste-Update.log")

    /// Zeigt den Knopf im Fensterkopf: Text (nil = ausblenden) und ob er klickbar ist.
    var anzeige: ((String?, Bool) -> Void)?
    /// Sichert den Fortschritt der offenen Seite und ruft danach den Block auf.
    var vorDemNeustart: ((@escaping () -> Void) -> Void)?

    private var neuerStand: Int?
    private var laeuft = false
    private var beobachter: NSKeyValueObservation?
    private var uhr: Timer?

    static var aktiv: Bool {
        Bundle.main.object(forInfoDictionaryKey: "LernkisteUpdates") as? Bool == true
    }

    static var eigenerStand: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "LernkisteStand") as? String ?? "") ?? 0
    }

    // MARK: Nachsehen

    /// Beim Start und danach alle sechs Stunden still nachsehen.
    func starten() {
        guard Updater.aktiv else { return }
        nachsehen(still: true)
        uhr = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.nachsehen(still: true)
        }
    }

    /// `still` = beim Start: kein Hinweis, wenn nichts Neues da ist oder das Netz fehlt.
    func nachsehen(still: Bool) {
        guard Updater.aktiv, !laeuft else { return }
        // Der Zeitstempel umgeht den Zwischenspeicher von GitHub.
        let adresse = "\(standURL)?t=\(Int(Date().timeIntervalSince1970))"
        guard let url = URL(string: adresse) else { return }
        var anfrage = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 10)
        anfrage.httpMethod = "GET"
        URLSession.shared.dataTask(with: anfrage) { [weak self] daten, antwort, fehler in
            let code = (antwort as? HTTPURLResponse)?.statusCode ?? 0
            let text = daten.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stand = code == 200 ? Int(text) : nil
            DispatchQueue.main.async {
                self?.ergebnis(stand: stand, still: still, fehler: fehler)
            }
        }.resume()
    }

    private func ergebnis(stand: Int?, still: Bool, fehler: Error?) {
        guard let stand else {
            if !still {
                hinweis("Keine Verbindung zu GitHub",
                        "Ob es eine neue Fassung gibt, lässt sich gerade nicht nachsehen. "
                        + "Später noch einmal versuchen.")
            }
            return
        }
        if stand > Updater.eigenerStand {
            neuerStand = stand
            anzeige?("Update verfügbar", true)
            if !still { installierenFragen() }
        } else if !still {
            hinweis("Die Lernkiste ist aktuell", "Du hast bereits die neueste Fassung.")
        }
    }

    // MARK: Einspielen

    /// Klick auf den Knopf im Fensterkopf.
    @objc func installierenFragen() {
        guard !laeuft, neuerStand != nil else { return }
        if let fehler = ortPruefen() {
            hinweis("Update hier nicht möglich", fehler)
            return
        }
        let frage = NSAlert()
        frage.messageText = "Neue Fassung installieren?"
        frage.informativeText =
            "Die Lernkiste lädt die neue Fassung herunter, tauscht sich aus und startet neu. "
            + "Das dauert meist unter einer Minute.\n\n"
            + "Deine Lernseiten und dein Fortschritt bleiben, wie sie sind. "
            + "Die alte Fassung landet im Papierkorb."
        frage.addButton(withTitle: "Jetzt aktualisieren")
        frage.addButton(withTitle: "Später")
        guard frage.runModal() == .alertFirstButtonReturn else { return }
        laden()
    }

    /// Kann die App an ihrem Ort überhaupt ersetzt werden?
    private func ortPruefen() -> String? {
        let pfad = Bundle.main.bundlePath
        // Direkt aus dem Download-Ordner gestartet: macOS führt die App dann
        // aus einer schreibgeschützten Kopie aus.
        if pfad.contains("/AppTranslocation/") {
            return "Die Lernkiste läuft gerade nicht aus dem Programme-Ordner. "
                + "Bitte einmal über „Installieren.command“ installieren — danach klappen Updates von selbst."
        }
        let ordner = (pfad as NSString).deletingLastPathComponent
        if !FileManager.default.isWritableFile(atPath: ordner) {
            return "Im Ordner „\(ordner)“ darf die Lernkiste nichts ändern. "
                + "Bitte die neue Fassung von Hand installieren (ZIP von GitHub, dann „Installieren.command“)."
        }
        return nil
    }

    private func laden() {
        guard let url = URL(string: paketURL) else { return }
        laeuft = true
        anzeige?("Lädt …", false)
        notiz("Update auf Stand \(neuerStand ?? 0) beginnt (bisher \(Updater.eigenerStand))")

        let aufgabe = URLSession.shared.downloadTask(with: url) { [weak self] datei, antwort, fehler in
            guard let self else { return }
            let code = (antwort as? HTTPURLResponse)?.statusCode ?? 0
            guard let datei, code == 200 else {
                self.scheitern("Der Download ist gescheitert"
                               + (fehler.map { ": \($0.localizedDescription)" } ?? " (Antwort \(code))."))
                return
            }
            // Die Datei verschwindet, sobald dieser Block endet — also sofort sichern.
            let arbeit = FileManager.default.temporaryDirectory
                .appendingPathComponent("Lernkiste-Update-\(UUID().uuidString)")
            let zip = arbeit.appendingPathComponent("lernkiste.zip")
            do {
                try FileManager.default.createDirectory(at: arbeit, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: datei, to: zip)
            } catch {
                self.scheitern("Die heruntergeladene Datei ließ sich nicht ablegen: \(error.localizedDescription)")
                return
            }
            self.auspacken(zip, in: arbeit)
        }
        // GitHub nennt die Größe nicht immer — dann zählen wir Megabyte statt Prozent.
        beobachter = aufgabe.progress.observe(\.completedUnitCount) { [weak self, weak aufgabe] _, _ in
            guard let aufgabe else { return }
            let gesamt = aufgabe.countOfBytesExpectedToReceive
            let da = aufgabe.countOfBytesReceived
            let text = gesamt > 0
                ? "Lädt … \(Int(Double(da) / Double(gesamt) * 100)) %"
                : String(format: "Lädt … %.1f MB", Double(da) / 1_000_000)
            DispatchQueue.main.async { self?.anzeige?(text, false) }
        }
        aufgabe.resume()
    }

    /// Läuft im Hintergrund: entpacken, neue App finden, prüfen.
    private func auspacken(_ zip: URL, in arbeit: URL) {
        DispatchQueue.main.async { self.anzeige?("Entpackt …", false) }
        let ziel = arbeit.appendingPathComponent("inhalt")
        guard ausfuehren("/usr/bin/ditto", ["-x", "-k", zip.path, ziel.path]) else {
            scheitern("Das Paket ließ sich nicht entpacken.")
            return
        }
        // GitHub legt alles in einen Ordner „lernkiste-main“.
        let ordner = (try? FileManager.default.contentsOfDirectory(at: ziel, includingPropertiesForKeys: nil)) ?? []
        guard let neu = ordner.map({ $0.appendingPathComponent("Lernkiste.app") })
                .first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/MacOS/Lernkiste").path) })
        else {
            scheitern("Im Paket fehlt die App.")
            return
        }
        let info = NSDictionary(contentsOf: neu.appendingPathComponent("Contents/Info.plist"))
        let stand = Int(info?["LernkisteStand"] as? String ?? "") ?? 0
        guard stand > Updater.eigenerStand else {
            scheitern("Das Paket ist nicht neuer als die installierte Fassung (Stand \(stand)).")
            return
        }
        guard ausfuehren("/usr/bin/codesign", ["--verify", "--deep", "--strict", neu.path]) else {
            scheitern("Die neue App ist beschädigt (Signatur ungültig).")
            return
        }
        _ = ausfuehren("/usr/bin/xattr", ["-dr", "com.apple.quarantine", neu.path])
        notiz("Paket geprüft: Stand \(stand)")
        DispatchQueue.main.async { self.austauschen(neu) }
    }

    /// Erst den Fortschritt sichern, dann die App tauschen und neu starten.
    private func austauschen(_ neu: URL) {
        anzeige?("Startet neu …", false)
        let weiter: () -> Void = { [weak self] in self?.tauschen(neu) }
        if let vorDemNeustart { vorDemNeustart(weiter) } else { weiter() }
    }

    private func tauschen(_ neu: URL) {
        let fm = FileManager.default
        let alt = Bundle.main.bundleURL
        var imPapierkorb: NSURL?
        do {
            // Die laufende App darf verschoben werden — sie läuft aus dem
            // Speicher weiter, bis sie sich gleich selbst beendet.
            try fm.trashItem(at: alt, resultingItemURL: &imPapierkorb)
        } catch {
            scheitern("Die alte Fassung ließ sich nicht in den Papierkorb legen: \(error.localizedDescription)")
            return
        }
        guard ausfuehren("/usr/bin/ditto", [neu.path, alt.path]) else {
            // Zurück wie vorher, damit keine halbe App stehen bleibt.
            if let zurueck = imPapierkorb as URL? {
                try? fm.removeItem(at: alt)
                try? fm.moveItem(at: zurueck, to: alt)
            }
            scheitern("Die neue Fassung ließ sich nicht an ihren Platz kopieren. Die alte bleibt.")
            return
        }
        notiz("Ausgetauscht — Neustart")

        // Ein kleiner Helfer wartet, bis diese App zu ist, und öffnet dann die neue.
        // Vorher ginge nicht: die neue würde sonst „läuft bereits“ melden.
        let helfer = Process()
        helfer.executableURL = URL(fileURLWithPath: "/bin/bash")
        helfer.arguments = ["-c",
            "for i in $(seq 1 150); do kill -0 \"$1\" 2>/dev/null || break; sleep 0.2; done; "
            + "sleep 0.5; /usr/bin/open \"$2\"",
            "lernkiste-neustart", String(ProcessInfo.processInfo.processIdentifier), alt.path]
        helfer.standardInput = FileHandle.nullDevice
        helfer.standardOutput = FileHandle.nullDevice
        helfer.standardError = FileHandle.nullDevice
        do {
            try helfer.run()
        } catch {
            hinweis("Fast fertig", "Die neue Fassung ist installiert. Bitte die Lernkiste einmal von Hand neu öffnen.")
        }
        NSApp.terminate(nil)
    }

    // MARK: Hilfen

    private func scheitern(_ grund: String) {
        notiz("FEHLGESCHLAGEN: \(grund)")
        DispatchQueue.main.async {
            self.laeuft = false
            self.beobachter = nil
            self.anzeige?("Update verfügbar", true)
            self.hinweis("Update hat nicht geklappt",
                         grund + "\n\nDie bisherige Fassung läuft unverändert weiter. "
                         + "Du kannst es später noch einmal versuchen.")
        }
    }

    private func hinweis(_ titel: String, _ text: String) {
        let a = NSAlert()
        a.messageText = titel
        a.informativeText = text
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    @discardableResult
    private func ausfuehren(_ programm: String, _ argumente: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: programm)
        p.arguments = argumente
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private func notiz(_ text: String) {
        let zeile = "[\(Date())] \(text)\n"
        guard let daten = zeile.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: protokoll) {
            h.seekToEndOfFile(); h.write(daten); try? h.close()
        } else {
            try? daten.write(to: protokoll)
        }
    }
}
