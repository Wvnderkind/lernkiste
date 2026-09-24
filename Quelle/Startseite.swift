import Foundation

/// Baut die Startseite als HTML. Bewusst kein AppKit-Layout: so sieht die
/// Startseite genauso aus wie die Lernseiten und nutzt dieselben Farbtokens.
enum Startseite {

    static func bauen(faecher: [Fach], staende: [String: SeitenStand],
                      plan: Tagesplan?, zustand: Zustand) -> String {

        let alle = faecher.flatMap(\.alleSeiten)
        let nachID = Dictionary(uniqueKeysWithValues: alle.map { ($0.id, $0) })

        var html = """
        <!DOCTYPE html><html lang="de" data-theme="\(zustand.theme)"><head>
        <meta charset="utf-8"><title>Lernkiste</title>
        <link rel="stylesheet" href="/res/tokens.css">
        <style>
        *{box-sizing:border-box}
        body{margin:0;background:var(--bg);color:var(--text);
             font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;
             font-size:14px;line-height:1.5}
        .huelle{max-width:840px;margin:0 auto;padding:34px 24px 60px}
        .kopf{display:flex;justify-content:space-between;align-items:baseline;
              margin-bottom:6px;gap:16px;flex-wrap:wrap}
        h1{font-size:25px;font-weight:600;margin:0;letter-spacing:-.2px}
        .datum{color:var(--text-dim);font-size:13px}
        .frist{display:inline-flex;align-items:center;gap:7px;background:var(--surface);
               border:1px solid var(--line);border-left:3px solid var(--accent);
               border-radius:0 8px 8px 0;padding:9px 13px;margin:16px 0 30px;font-size:13px}
        .frist b{color:var(--accent);font-weight:600}
        h2{font-size:12px;text-transform:uppercase;letter-spacing:1px;
           color:var(--text-dim);font-weight:600;margin:30px 0 11px}
        h2:first-of-type{margin-top:0}
        .karten{display:grid;gap:10px}
        .karte{display:block;background:var(--surface);border:1px solid var(--line);
               border-radius:10px;padding:14px 16px;text-decoration:none;color:inherit;
               transition:border-color .12s,transform .12s}
        .karte:hover{border-color:var(--accent);transform:translateY(-1px)}
        .karte .zeile{display:flex;justify-content:space-between;align-items:center;gap:12px}
        .karte .titel{font-weight:600;font-size:14.5px}
        .karte .fach{font-size:11px;color:var(--text-dim);text-transform:uppercase;
                     letter-spacing:.7px;margin-top:2px}
        .karte .hinweis{font-size:12.5px;color:var(--text-dim);margin-top:8px;line-height:1.5}
        .marke{font-size:10.5px;font-weight:600;padding:3px 8px;border-radius:20px;
               white-space:nowrap;border:1px solid}
        .m-offen{color:var(--accent);border-color:var(--accent);background:var(--accent-soft)}
        .m-fertig{color:var(--ok);border-color:var(--ok);background:transparent}
        .m-wackel{color:var(--no);border-color:var(--no);background:transparent}
        .m-ruht{color:var(--text-dim);border-color:var(--line)}
        .balken{height:4px;border-radius:2px;background:var(--surface-2);
                overflow:hidden;margin-top:11px}
        .balken i{display:block;height:100%;background:var(--accent);border-radius:2px}
        .balken i.geschafft{background:var(--ok)}
        .leer{color:var(--text-dim);font-size:13px;background:var(--surface);
              border:1px dashed var(--line);border-radius:10px;padding:16px}
        .anleitung{position:relative;background:var(--surface);border:1px solid var(--line);
              border-left:3px solid var(--accent);border-radius:0 10px 10px 0;
              padding:15px 40px 13px 18px;margin:0 0 28px;font-size:13.5px}
        .anleitung b.kopf{display:block;font-size:15px;margin-bottom:6px}
        .anleitung ol{margin:6px 0 8px;padding-left:20px}
        .anleitung li{margin:5px 0}
        .anleitung .still{color:var(--text-dim);font-size:12px}
        .anleitung code{font-size:12px}
        .anleitung a{color:var(--accent);font-weight:600;text-decoration:none}
        .anleitung a:hover{text-decoration:underline}
        .anleitung .weg{position:absolute;top:8px;right:10px;border:0;background:none;
              color:var(--text-dim);font-size:19px;line-height:1;cursor:pointer;padding:4px}
        .anleitung .weg:hover{color:var(--text)}
        .reihe{display:grid;grid-template-columns:repeat(auto-fill,minmax(215px,1fr));gap:10px}
        .klein{background:var(--surface);border:1px solid var(--line);border-radius:9px;
               padding:11px 13px;text-decoration:none;color:inherit;display:block}
        .klein:hover{border-color:var(--accent)}
        .klein .titel{font-weight:500;font-size:13px}
        .klein .fach{font-size:10.5px;color:var(--text-dim);margin-top:3px;
                     text-transform:uppercase;letter-spacing:.6px}
        .fuss{margin-top:40px;padding-top:16px;border-top:1px solid var(--line);
              color:var(--text-dim);font-size:11.5px}
        </style></head><body><div class="huelle">
        """

        // Kopf mit Datum
        let wochentag = DateFormatter()
        wochentag.locale = Locale(identifier: "de_DE")
        wochentag.dateFormat = "EEEE, d. MMMM"
        html += """
        <div class="kopf"><h1>\(begruessung())</h1>
        <span class="datum">\(esc(wochentag.string(from: Date())))</span></div>
        """

        // Countdown zur nächsten Klausur
        if let frist = naechsteFrist() {
            html += """
            <div class="frist">📌 <span><b>\(frist.tage) Tage</b> bis \(esc(frist.name))
            — \(esc(frist.datumText))</span></div>
            """
        }

        // ---- Erste Schritte: solange noch keine eigene Seite da ist ----
        if alle.isEmpty {
            html += anleitung(beispielDa: false, ausblendbar: false)
            html += """
            <div class="fuss">Noch keine Lernseiten &middot;
            Fortschritt wird automatisch gesichert</div>
            </div></body></html>
            """
            return html
        }
        if alle.allSatisfy({ $0.id == Orte.beispielID }), zustand.anleitungAusgeblendet != true {
            html += anleitung(beispielDa: true, ausblendbar: true)
        }

        // ---- Heute dran ----
        html += "<h2>Heute dran</h2>"
        if let plan, plan.fuerHeute, !plan.eintraege.isEmpty {
            html += "<div class=\"karten\">"
            for eintrag in plan.eintraege {
                guard let seite = nachID[eintrag.seite] else { continue }
                let stand = staende[seite.id]
                html += karte(seite: seite, stand: stand, hinweis: eintrag.hinweis,
                              ziel: eintrag.ziel, tagesbalken: true)
            }
            html += "</div>"
        } else {
            html += """
            <div class="leer">Für heute ist kein Plan hinterlegt.
            Claude trägt ihn am Ende jeder Lernsession ein — unten stehen so lange
            die Seiten, die am längsten nicht dran waren.</div>
            """
        }

        // ---- Wackelkandidaten ----
        let wacklig = alle.compactMap { seite -> (Seite, SeitenStand)? in
            guard let s = staende[seite.id], s.wackel > 0 else { return nil }
            return (seite, s)
        }.sorted { $0.1.wackel > $1.1.wackel }.prefix(4)

        if !wacklig.isEmpty {
            html += "<h2>Wackelkandidaten</h2><div class=\"karten\">"
            for (seite, stand) in wacklig {
                html += karte(seite: seite, stand: stand,
                              hinweis: "\(stand.wackel) \(stand.wackel == 1 ? "Item sitzt" : "Items sitzen") noch nicht.",
                              ziel: nil)
            }
            html += "</div>"
        }

        // ---- Lange nicht geübt ----
        let kalt = alle.filter { seite in
            guard !seite.fachIstArchiv(faecher) else { return false }
            guard let s = staende[seite.id], let d = ISO.datum(s.zuletztGeoeffnet)
            else { return true }
            return Datum.tageSeit(d) >= 5
        }.prefix(4)

        if !kalt.isEmpty {
            html += "<h2>Lange nicht geübt</h2><div class=\"reihe\">"
            for seite in kalt { html += kleineKarte(seite) }
            html += "</div>"
        }

        // ---- Favoriten ----
        let favoriten = zustand.favoriten.compactMap { nachID[$0] }
        if !favoriten.isEmpty {
            html += "<h2>Angepinnt</h2><div class=\"reihe\">"
            for seite in favoriten { html += kleineKarte(seite) }
            html += "</div>"
        }

        // ---- Zuletzt geöffnet ----
        let zuletzt = zustand.zuletzt.compactMap { nachID[$0] }.prefix(5)
        if !zuletzt.isEmpty {
            html += "<h2>Zuletzt geöffnet</h2><div class=\"reihe\">"
            for seite in zuletzt { html += kleineKarte(seite) }
            html += "</div>"
        }

        let anzahl = alle.count
        html += """
        <div class="fuss">\(anzahl) Lernseiten in \(faecher.count) Fächern ·
        Fortschritt wird automatisch gesichert</div>
        </div></body></html>
        """
        return html
    }

    // MARK: - Bausteine

    /// `tagesbalken`: unter „Heute dran" zeigt der Balken das Tagespensum
    /// (passend zur Marke rechts), sonst den Gesamtstand der Kategorie.
    private static func karte(seite: Seite, stand: SeitenStand?,
                              hinweis: String?, ziel: Int?,
                              tagesbalken: Bool = false) -> String {
        var marke = "<span class=\"marke m-ruht\">neu</span>"
        var balken = ""

        if let stand {
            if let p = stand.tagespensum, p.erledigt {
                marke = "<span class=\"marke m-fertig\">heute geschafft</span>"
            } else if let p = stand.tagespensum, p.datum == Datum.heute,
                      let g = p.geschafft, let z = p.ziel, z > 0 {
                marke = "<span class=\"marke m-offen\">\(g) / \(z) heute</span>"
            } else if let z = ziel {
                marke = "<span class=\"marke m-offen\">\(z) geplant</span>"
            } else if stand.wackel > 0 {
                marke = "<span class=\"marke m-wackel\">\(stand.wackel) wacklig</span>"
            } else if stand.geuebt > 0 {
                marke = "<span class=\"marke m-fertig\">sitzt</span>"
            }
            if tagesbalken {
                balken = tagesBalken(stand: stand, ziel: ziel)
            } else if let gesamt = stand.gesamt, gesamt > 0 {
                let anteil = Int(stand.anteilSitzen * 100)
                balken = "<div class=\"balken\"><i style=\"width:\(anteil)%\"></i></div>"
            }
        } else if let z = ziel {
            marke = "<span class=\"marke m-offen\">\(z) geplant</span>"
            if tagesbalken { balken = tagesBalken(stand: nil, ziel: z) }
        }

        let text = hinweis.map { "<div class=\"hinweis\">\(esc($0))</div>" } ?? ""
        return """
        <a class="karte" href="#" onclick="oeffne('\(esc(seite.id))');return false">
          <div class="zeile"><div>
            <div class="titel">\(esc(seite.titel))</div>
            <div class="fach">\(esc(seite.fach)) · \(esc(seite.thema))</div>
          </div>\(marke)</div>\(text)\(balken)
        </a>
        """
    }

    /// Wie viel vom heutigen Pensum steht schon. Ein geschafftes Pensum bleibt
    /// voll und gruen, auch wenn er danach noch weitergeuebt hat.
    private static func tagesBalken(stand: SeitenStand?, ziel: Int?) -> String {
        var anteil = 0
        var fertig = false
        if let p = stand?.tagespensum, p.erledigt {
            anteil = 100
            fertig = true
        } else if let p = stand?.tagespensum, p.datum == Datum.heute,
                  let g = p.geschafft, let z = p.ziel, z > 0 {
            anteil = min(100, Int(Double(g) / Double(z) * 100))
            fertig = g >= z
        } else if ziel == nil {
            return ""      // ohne Tagesziel gibt es nichts anzuzeigen
        }
        let klasse = fertig ? " class=\"geschafft\"" : ""
        return "<div class=\"balken\"><i\(klasse) style=\"width:\(anteil)%\"></i></div>"
    }

    private static func kleineKarte(_ seite: Seite) -> String {
        """
        <a class="klein" href="#" onclick="oeffne('\(esc(seite.id))');return false">
          <div class="titel">\(esc(seite.titel))</div>
          <div class="fach">\(esc(seite.fach))</div></a>
        """
    }

    private static func begruessung() -> String {
        let stunde = Calendar.current.component(.hour, from: Date())
        switch stunde {
        case 5..<11:  return "Guten Morgen"
        case 11..<14: return "Mahlzeit"
        case 14..<18: return "Guten Nachmittag"
        case 18..<23: return "Guten Abend"
        default:      return "Noch wach?"
        }
    }

    /// Countdown auf der Startseite. Kommt ausschliesslich aus konfiguration.json:
    ///   { "naechsterTermin": { "name": "Biochemie", "datum": "2027-02-14" } }
    /// Ohne Eintrag zeigt die Startseite keinen Termin an.
    private static func naechsteFrist() -> (name: String, tage: Int, datumText: String)? {
        guard let termin = Konfiguration.laden().naechsterTermin else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let tag = f.date(from: termin.datum) else { return nil }
        let tage = Calendar.current.dateComponents([.day], from: Date(), to: tag).day ?? 0
        guard tage >= 0 else { return nil }
        let anzeige = DateFormatter()
        anzeige.locale = Locale(identifier: "de_DE")
        anzeige.dateFormat = "d. MMMM"
        return (termin.name, tage, anzeige.string(from: tag))
    }

    /// Der Kasten „Erste Schritte“. Er verschwindet von selbst, sobald eine
    /// eigene Seite neben der Beispielseite liegt; per × auch schon vorher.
    private static func anleitung(beispielDa: Bool, ausblendbar: Bool) -> String {
        let ordner = Orte.seiten.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        var h = "<div class=\"anleitung\">\n"
        if ausblendbar {
            h += """
            <button class="weg" title="Ausblenden" onclick="try{webkit.messageHandlers.lernkiste.postMessage({art:'anleitungWeg'})}catch(e){}">&times;</button>
            """
        }
        h += "<b class=\"kopf\">Erste Schritte</b>\n<ol>\n"
        if beispielDa {
            h += """
            <li><b>Ausprobieren:</b> <a href="#" onclick="oeffne('\(esc(Orte.beispielID))');return false">Beispielseite
            &ouml;ffnen</a> &mdash; so sieht eine Lernseite aus. Dein Fortschritt wird von selbst gesichert.</li>
            """
        }
        h += """
        <li><b>Eigene Seite bauen lassen:</b> <b>Ablage &rarr; Bauanleitung f&uuml;r eine KI
        kopieren</b>, in den Chat mit einer KI einf&uuml;gen und dazuschreiben, was du &uuml;ben willst.
        Mit Claude Code geht es noch bequemer &mdash; siehe <code>Fuer-Claude/START-HIER.md</code>
        im heruntergeladenen Ordner.</li>
        <li><b>Hinzuf&uuml;gen:</b> Die fertige Seite kopieren und <b>Ablage &rarr; Seite aus
        Zwischenablage einf&uuml;gen</b> (&#8679;&#8984;V) &mdash; oder eine .html-Datei bzw. ein
        ZIP-Paket in die Leiste ziehen. Die Lernkiste sortiert sie selbst ins richtige Fach.</li>
        <li><b>Weitergeben:</b> Rechtsklick auf eine Seite, ein Thema oder ein Fach &rarr;
        <b>teilen</b> (AirDrop, Nachrichten, Mail &hellip;).</li>
        </ol>
        <div class="still">Dieser Kasten verschwindet, sobald deine erste eigene Seite da ist.
        Alle Seiten liegen in <code>\(esc(ordner))</code>.</div>
        </div>

        """
        return h
    }

    static func esc(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

extension Seite {
    func fachIstArchiv(_ faecher: [Fach]) -> Bool {
        faecher.first { $0.name == fach }?.archiv ?? false
    }
}
