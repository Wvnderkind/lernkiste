//! Baut die Startseite als HTML — dasselbe Aussehen wie auf dem Mac,
//! mit denselben Farbtokens wie die Lernseiten. Nachbau von Startseite.swift.

use crate::bibliothek::{alle_seiten, fach_ist_archiv, Fach, Konfiguration, Seite, Tagesplan};
use crate::fortschritt::{SeitenStand, Zustand};
use crate::orte::{orte, BEISPIEL_ID};
use crate::zeit;
use std::collections::HashMap;

const KOPF: &str = r#"<meta charset="utf-8"><title>Lernkiste</title>
<link rel="stylesheet" href="/res/tokens.css">
<style>
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);
     font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;
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
"#;

pub fn bauen(
    faecher: &[Fach],
    staende: &HashMap<String, SeitenStand>,
    plan: Option<&Tagesplan>,
    zustand: &Zustand,
) -> String {
    let alle = alle_seiten(faecher);
    let nach_id: HashMap<&str, &Seite> = alle.iter().map(|s| (s.id.as_str(), *s)).collect();

    let mut html = format!(
        "<!DOCTYPE html><html lang=\"de\" data-theme=\"{}\"><head>\n{}",
        esc(&zustand.theme),
        KOPF
    );

    // Kopf mit Datum
    html += &format!(
        "<div class=\"kopf\"><h1>{}</h1>\n<span class=\"datum\">{}</span></div>\n",
        begruessung(),
        esc(&zeit::wochentag_heute())
    );

    // Countdown zur naechsten Klausur
    if let Some(termin) = Konfiguration::laden().naechster_termin {
        if let Some((tage, tag)) = zeit::tage_bis(&termin.datum) {
            if tage >= 0 {
                html += &format!(
                    "<div class=\"frist\">📌 <span><b>{} Tage</b> bis {}\n— {}</span></div>\n",
                    tage,
                    esc(&termin.name),
                    esc(&zeit::tag_monat(tag))
                );
            }
        }
    }

    // ---- Erste Schritte: solange noch keine eigene Seite da ist ----
    let nur_beispiel = alle.iter().all(|s| s.id == BEISPIEL_ID);
    if alle.is_empty() {
        html += &anleitung(false, false);
        html += "<div class=\"fuss\">Noch keine Lernseiten &middot;\nFortschritt wird automatisch gesichert</div>\n</div></body></html>\n";
        return html;
    }
    if nur_beispiel && !zustand.anleitung_ausgeblendet {
        html += &anleitung(true, true);
    }

    // ---- Heute dran ----
    html += "<h2>Heute dran</h2>";
    match plan {
        Some(plan) if plan.fuer_heute() && !plan.eintraege.is_empty() => {
            html += "<div class=\"karten\">";
            for eintrag in &plan.eintraege {
                let Some(seite) = nach_id.get(eintrag.seite.as_str()) else { continue };
                html += &karte(
                    seite,
                    staende.get(&seite.id),
                    eintrag.hinweis.as_deref(),
                    eintrag.ziel,
                    true,
                );
            }
            html += "</div>";
        }
        _ => {
            html += "<div class=\"leer\">Für heute ist kein Plan hinterlegt.\n\
                     Claude trägt ihn am Ende jeder Lernsession ein — unten stehen so lange\n\
                     die Seiten, die am längsten nicht dran waren.</div>\n";
        }
    }

    // ---- Wackelkandidaten ----
    let mut wacklig: Vec<(&Seite, &SeitenStand)> = alle
        .iter()
        .filter_map(|s| staende.get(&s.id).filter(|st| st.wackel > 0).map(|st| (*s, st)))
        .collect();
    wacklig.sort_by(|a, b| b.1.wackel.cmp(&a.1.wackel));
    if !wacklig.is_empty() {
        html += "<h2>Wackelkandidaten</h2><div class=\"karten\">";
        for (seite, stand) in wacklig.into_iter().take(4) {
            let hinweis = format!(
                "{} {} noch nicht.",
                stand.wackel,
                if stand.wackel == 1 { "Item sitzt" } else { "Items sitzen" }
            );
            html += &karte(seite, Some(stand), Some(&hinweis), None, false);
        }
        html += "</div>";
    }

    // ---- Lange nicht geuebt ----
    let kalt: Vec<&Seite> = alle
        .iter()
        .copied()
        .filter(|seite| {
            if fach_ist_archiv(faecher, &seite.fach) {
                return false;
            }
            match staende
                .get(&seite.id)
                .and_then(|s| zeit::iso_lesen(s.zuletzt_geoeffnet.as_deref()))
            {
                None => true,
                Some(d) => zeit::tage_seit(d) >= 5,
            }
        })
        .take(4)
        .collect();
    if !kalt.is_empty() {
        html += "<h2>Lange nicht geübt</h2><div class=\"reihe\">";
        for seite in kalt {
            html += &kleine_karte(seite);
        }
        html += "</div>";
    }

    // ---- Favoriten ----
    let favoriten: Vec<&Seite> =
        zustand.favoriten.iter().filter_map(|id| nach_id.get(id.as_str()).copied()).collect();
    if !favoriten.is_empty() {
        html += "<h2>Angepinnt</h2><div class=\"reihe\">";
        for seite in favoriten {
            html += &kleine_karte(seite);
        }
        html += "</div>";
    }

    // ---- Zuletzt geoeffnet ----
    let zuletzt: Vec<&Seite> = zustand
        .zuletzt
        .iter()
        .filter_map(|id| nach_id.get(id.as_str()).copied())
        .take(5)
        .collect();
    if !zuletzt.is_empty() {
        html += "<h2>Zuletzt geöffnet</h2><div class=\"reihe\">";
        for seite in zuletzt {
            html += &kleine_karte(seite);
        }
        html += "</div>";
    }

    html += &format!(
        "<div class=\"fuss\">{} Lernseiten in {} Fächern ·\nFortschritt wird automatisch gesichert</div>\n</div></body></html>",
        alle.len(),
        faecher.len()
    );
    html
}

// MARK: - Bausteine

/// `tagesbalken`: unter „Heute dran" zeigt der Balken das Tagespensum,
/// sonst den Gesamtstand.
fn karte(
    seite: &Seite,
    stand: Option<&SeitenStand>,
    hinweis: Option<&str>,
    ziel: Option<i64>,
    tagesbalken: bool,
) -> String {
    let mut marke = "<span class=\"marke m-ruht\">neu</span>".to_string();
    let mut balken = String::new();
    let heute = zeit::heute();

    if let Some(stand) = stand {
        let pensum_heute = stand.tagespensum.as_ref().and_then(|p| {
            match (p.datum.as_deref(), p.geschafft, p.ziel) {
                (Some(d), Some(g), Some(z)) if d == heute && z > 0 => Some((g, z)),
                _ => None,
            }
        });
        if stand.tagespensum.as_ref().is_some_and(|p| p.erledigt()) {
            marke = "<span class=\"marke m-fertig\">heute geschafft</span>".into();
        } else if let Some((g, z)) = pensum_heute {
            marke = format!("<span class=\"marke m-offen\">{g} / {z} heute</span>");
        } else if let Some(z) = ziel {
            marke = format!("<span class=\"marke m-offen\">{z} geplant</span>");
        } else if stand.wackel > 0 {
            marke = format!("<span class=\"marke m-wackel\">{} wacklig</span>", stand.wackel);
        } else if stand.geuebt > 0 {
            marke = "<span class=\"marke m-fertig\">sitzt</span>".into();
        }
        if tagesbalken {
            balken = tages_balken(Some(stand), ziel);
        } else if stand.gesamt.is_some_and(|g| g > 0) {
            let anteil = (stand.anteil_sitzen() * 100.0) as i64;
            balken = format!("<div class=\"balken\"><i style=\"width:{anteil}%\"></i></div>");
        }
    } else if let Some(z) = ziel {
        marke = format!("<span class=\"marke m-offen\">{z} geplant</span>");
        if tagesbalken {
            balken = tages_balken(None, Some(z));
        }
    }

    let text = hinweis
        .map(|h| format!("<div class=\"hinweis\">{}</div>", esc(h)))
        .unwrap_or_default();
    format!(
        "<a class=\"karte\" href=\"#\" onclick=\"oeffne('{}');return false\">\n  <div class=\"zeile\"><div>\n    <div class=\"titel\">{}</div>\n    <div class=\"fach\">{} · {}</div>\n  </div>{}</div>{}{}\n</a>\n",
        esc(&seite.id),
        esc(&seite.titel),
        esc(&seite.fach),
        esc(&seite.thema),
        marke,
        text,
        balken
    )
}

/// Ein geschafftes Pensum bleibt voll und gruen, auch wenn danach weitergeuebt wurde.
fn tages_balken(stand: Option<&SeitenStand>, ziel: Option<i64>) -> String {
    let heute = zeit::heute();
    let pensum = stand.and_then(|s| s.tagespensum.as_ref());
    let (anteil, fertig) = if pensum.is_some_and(|p| p.erledigt()) {
        (100, true)
    } else if let Some((g, z)) = pensum.and_then(|p| match (p.datum.as_deref(), p.geschafft, p.ziel) {
        (Some(d), Some(g), Some(z)) if d == heute && z > 0 => Some((g, z)),
        _ => None,
    }) {
        (100.min((g as f64 / z as f64 * 100.0) as i64), g >= z)
    } else if ziel.is_none() {
        return String::new(); // ohne Tagesziel gibt es nichts anzuzeigen
    } else {
        (0, false)
    };
    let klasse = if fertig { " class=\"geschafft\"" } else { "" };
    format!("<div class=\"balken\"><i{klasse} style=\"width:{anteil}%\"></i></div>")
}

fn kleine_karte(seite: &Seite) -> String {
    format!(
        "<a class=\"klein\" href=\"#\" onclick=\"oeffne('{}');return false\">\n  <div class=\"titel\">{}</div>\n  <div class=\"fach\">{}</div></a>\n",
        esc(&seite.id),
        esc(&seite.titel),
        esc(&seite.fach)
    )
}

fn begruessung() -> &'static str {
    match zeit::stunde() {
        5..=10 => "Guten Morgen",
        11..=13 => "Mahlzeit",
        14..=17 => "Guten Nachmittag",
        18..=22 => "Guten Abend",
        _ => "Noch wach?",
    }
}

/// Der Kasten „Erste Schritte“. Er verschwindet von selbst, sobald eine
/// eigene Seite neben der Beispielseite liegt; per × auch schon vorher.
fn anleitung(beispiel_da: bool, ausblendbar: bool) -> String {
    let ordner = orte().seiten.display().to_string();
    let mut h = String::from("<div class=\"anleitung\">\n");
    if ausblendbar {
        h += "<button class=\"weg\" title=\"Ausblenden\" onclick=\"parent.postMessage({art:'anleitungWeg'},location.origin)\">&times;</button>\n";
    }
    h += "<b class=\"kopf\">Erste Schritte</b>\n<ol>\n";
    if beispiel_da {
        h += &format!(
            "<li><b>Ausprobieren:</b> <a href=\"#\" onclick=\"oeffne('{}');return false\">Beispielseite \
             &ouml;ffnen</a> &mdash; so sieht eine Lernseite aus. Dein Fortschritt wird von selbst gesichert.</li>\n",
            BEISPIEL_ID
        );
    }
    h += "<li><b>Eigene Seite bauen lassen:</b> <b>Datei &rarr; Bauanleitung f&uuml;r eine KI \
          kopieren</b>, in den Chat mit einer KI einf&uuml;gen und dazuschreiben, was du &uuml;ben willst.</li>\n\
          <li><b>Hinzuf&uuml;gen:</b> Die fertige Seite kopieren und <b>Datei &rarr; Seite aus \
          Zwischenablage einf&uuml;gen</b> (Strg+Umschalt+V) &mdash; oder eine .html-Datei bzw. ein \
          ZIP-Paket ins Fenster ziehen. Die Lernkiste sortiert sie selbst ins richtige Fach.</li>\n\
          <li><b>Weitergeben:</b> Rechtsklick auf eine Seite, ein Thema oder ein Fach &rarr; \
          <b>Exportieren &hellip;</b></li>\n</ol>\n";
    h += &format!(
        "<div class=\"still\">Dieser Kasten verschwindet, sobald deine erste eigene Seite da ist. \
         Alle Seiten liegen in <code>{}</code>.</div>\n</div>\n",
        esc(&ordner)
    );
    h
}

pub fn esc(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}
