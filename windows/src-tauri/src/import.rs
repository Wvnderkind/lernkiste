//! Holt fremde oder neu gebaute Lernseiten in die Bibliothek: aus einer Datei
//! (Menue, Hineinziehen, „Oeffnen mit") oder direkt aus der Zwischenablage,
//! wenn eine KI die Seite im Chat ausgegeben hat. Nachbau von Import.swift.
//!
//! Alles hier blockiert (Rueckfragen warten auf eine Antwort) und laeuft deshalb
//! in einem eigenen Faden, nie auf dem Hauptfaden des Fensters.

use crate::bibliothek::{self, entschaerft, meta, version_aus};
use crate::kern::{Kern, OrtWahl};
use crate::orte::{orte, KI_VORLAGE};
use crate::zeit;
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};

/// Immer nur ein Import auf einmal — wie die modalen Fragen auf dem Mac.
static SPERRE: Mutex<()> = Mutex::new(());

fn kern(app: &AppHandle) -> Arc<Kern> {
    app.state::<Arc<Kern>>().inner().clone()
}

// MARK: - Einstiege

pub fn dateien_waehlen(app: &AppHandle) {
    let app = app.clone();
    std::thread::spawn(move || {
        let mut frage = app
            .dialog()
            .file()
            .set_title("Lernseite importieren")
            .add_filter("Lernseite", &["html", "htm"]);
        if let Some(f) = app.get_webview_window("haupt") {
            frage = frage.set_parent(&f);
        }
        let Some(gewaehlt) = frage.blocking_pick_files() else { return };
        let pfade: Vec<PathBuf> = gewaehlt.into_iter().filter_map(|p| p.into_path().ok()).collect();
        dateien_jetzt(&app, pfade);
    });
}

pub fn dateien(app: &AppHandle, pfade: Vec<PathBuf>) {
    let app = app.clone();
    std::thread::spawn(move || dateien_jetzt(&app, pfade));
}

fn dateien_jetzt(app: &AppHandle, pfade: Vec<PathBuf>) {
    let _sperre = SPERRE.lock().unwrap_or_else(|e| e.into_inner());
    let mut zuletzt = None;
    for pfad in pfade {
        if !matches!(bibliothek::endung(&pfad).as_str(), "html" | "htm") {
            continue;
        }
        let name = pfad
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        let Ok(daten) = fs::read(&pfad) else {
            melden(app, &format!("„{name}“ ließ sich nicht lesen."), "");
            continue;
        };
        let stamm = pfad
            .file_stem()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        if let Some(id) = aufnehmen(app, &String::from_utf8_lossy(&daten), Some(&stamm)) {
            zuletzt = Some(id);
        }
    }
    abschliessen(app, zuletzt);
}

pub fn aus_zwischenablage(app: &AppHandle) {
    let app = app.clone();
    std::thread::spawn(move || {
        let _sperre = SPERRE.lock().unwrap_or_else(|e| e.into_inner());
        let roh = app.clipboard().read_text().unwrap_or_default();
        let Some(html) = html_herausloesen(&roh) else {
            melden(
                &app,
                "In der Zwischenablage liegt keine Lernseite.",
                "Kopiere die komplette Seite, wie die KI sie ausgegeben hat — \
                 von <!DOCTYPE html> bis </html>.",
            );
            return;
        };
        let id = aufnehmen(&app, &html, None);
        abschliessen(&app, id);
    });
}

pub fn bauanleitung_kopieren(app: &AppHandle) {
    let app = app.clone();
    std::thread::spawn(move || {
        if let Err(e) = app.clipboard().write_text(KI_VORLAGE.to_string()) {
            melden(&app, "Die Bauanleitung ließ sich nicht kopieren.", &e.to_string());
            return;
        }
        app.dialog()
            .message(
                "Füge sie in den Chat einer beliebigen KI ein und schreib dazu, \
                 zu welchem Thema du eine Lernseite willst.\n\n\
                 Die fertige Seite kopierst du, dann „Datei → Seite aus Zwischenablage \
                 einfügen“ — die Lernkiste sortiert sie selbst ein.",
            )
            .title("Bauanleitung kopiert")
            .kind(MessageDialogKind::Info)
            .buttons(MessageDialogButtons::OkCustom("Gut".into()))
            .blocking_show();
    });
}

// MARK: - Kern

/// Legt die Seite ab und liefert ihre id — oder None, wenn abgebrochen wurde.
fn aufnehmen(app: &AppHandle, html: &str, dateiname: Option<&str>) -> Option<String> {
    if !sieht_aus_wie_html(html) {
        melden(app, "Das ist keine HTML-Seite.", "");
        return None;
    }
    let seiten = &orte().seiten;
    let faecher = bibliothek::einlesen();
    let meta_id = meta(html, "lernkiste-id");
    let titel = meta(html, "lernkiste-titel").or_else(|| titel_tag(html));

    let vorhanden = meta_id.as_ref().and_then(|id| {
        bibliothek::alle_seiten(&faecher)
            .into_iter()
            .find(|s| &s.id == id)
            .map(|s| s.datei.clone())
    });
    let ziel: PathBuf = if let Some(datei) = vorhanden {
        // Gleiche id = gleiche Seite, auch wenn die Datei anders heisst.
        datei
    } else if let Some((fach, thema, slug)) = meta_id.as_deref().and_then(id_teile) {
        let fach = ordner_name(&fach, seiten);
        let thema = ordner_name(&thema, &seiten.join(&fach));
        seiten.join(fach).join(thema).join(format!("{slug}.html"))
    } else {
        // Keine Kennung in der Seite: dann fragen, wohin sie gehoert.
        let (fach, thema) = ort_erfragen(app, &faecher, titel.as_deref())?;
        let grundlage = dateiname.or(titel.as_deref()).unwrap_or("lernseite");
        let mut slug = sauber(&entschaerft(grundlage));
        if slug.is_empty() {
            slug = "lernseite".into();
        }
        seiten.join(fach).join(thema).join(format!("{slug}.html"))
    };

    if ziel.exists() {
        let alt = fs::read(&ziel)
            .map(|d| String::from_utf8_lossy(&d).into_owned())
            .unwrap_or_default();
        if alt != html {
            if !ersetzen_bestaetigt(app, &ziel, &alt, html) {
                return None;
            }
            if !archivieren(&ziel) {
                melden(app, "Die alte Fassung ließ sich nicht archivieren — nichts verändert.", "");
                return None;
            }
        }
    }
    let geschrieben = ziel
        .parent()
        .map(fs::create_dir_all)
        .unwrap_or(Ok(()))
        .and_then(|_| crate::orte::atomar_schreiben(&ziel, html.as_bytes()));
    if let Err(e) = geschrieben {
        melden(app, "Die Seite ließ sich nicht speichern.", &e.to_string());
        return None;
    }
    log::info!("Seite importiert: {}", ziel.display());
    if meta_id.is_some() {
        return meta_id;
    }
    // Ohne Kennung vergibt die Bibliothek sie aus dem Pfad.
    let neu = bibliothek::einlesen();
    let id = bibliothek::alle_seiten(&neu)
        .into_iter()
        .find(|s| s.datei == ziel)
        .map(|s| s.id.clone());
    id
}

/// Bibliothek neu einlesen und die zuletzt importierte Seite zeigen.
fn abschliessen(app: &AppHandle, id: Option<String>) {
    kern(app).neu_einlesen();
    let _ = app.emit_to("haupt", "neu_laden", json!({ "oeffnen": id }));
}

// MARK: - Ablage

/// "chemie/saeure-base/ph-und-titration" → Fach, Thema, Dateiname.
/// Alles, was einen Pfad verbiegen koennte, faellt dabei heraus.
fn id_teile(id: &str) -> Option<(String, String, String)> {
    let teile: Vec<String> = id.split('/').map(sauber).collect();
    if teile.len() < 3 || teile[0].is_empty() || teile[1].is_empty() || teile[teile.len() - 1].is_empty() {
        return None;
    }
    Some((teile[0].clone(), teile[1].clone(), teile[teile.len() - 1].clone()))
}

fn sauber(teil: &str) -> String {
    let s: String = teil
        .to_lowercase()
        .chars()
        .filter(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == '-' || *c == '_')
        .collect();
    s.trim_start_matches(['_', '-']).to_string()
}

/// Nimmt einen vorhandenen Ordner, wenn er zur Kennung passt
/// ("saeure-base" findet "Saeure-Base"), sonst einen neuen mit grossen Anfaengen.
fn ordner_name(kennung: &str, basis: &Path) -> String {
    if let Ok(eintraege) = fs::read_dir(basis) {
        for e in eintraege.flatten() {
            let name = e.file_name().to_string_lossy().into_owned();
            if !name.starts_with(['_', '.']) && entschaerft(&name) == kennung {
                return name;
            }
        }
    }
    kennung
        .split('-')
        .filter(|t| !t.is_empty())
        .map(|t| {
            let mut z = t.chars();
            match z.next() {
                Some(erster) => erster.to_uppercase().collect::<String>() + z.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join("-")
}

/// Die alte Fassung wandert nach _archiv\<Zeitstempel>-import\…, nichts geht verloren.
fn archivieren(datei: &Path) -> bool {
    let o = orte();
    let relativ = datei
        .strip_prefix(&o.seiten)
        .map(Path::to_path_buf)
        .unwrap_or_else(|_| PathBuf::from(datei.file_name().unwrap_or_default()));
    let ziel = o.archiv.join(format!("{}-import", zeit::stempel())).join(relativ);
    let Some(ordner) = ziel.parent() else { return false };
    fs::create_dir_all(ordner).is_ok() && fs::rename(datei, &ziel).is_ok()
}

// MARK: - Rueckfragen

fn ersetzen_bestaetigt(app: &AppHandle, ziel: &Path, alt: &str, neu: &str) -> bool {
    let alt_v = version_aus(alt);
    let neu_v = version_aus(neu);
    let stamm = ziel
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let mut text = format!(
        "„{stamm}“ liegt bereits in der Lernkiste. \
         Die alte Fassung wandert ins Archiv, nichts geht verloren."
    );
    if neu_v < alt_v {
        text += &format!(
            "\n\nAchtung: Die neue Fassung hat eine ältere Versionsnummer ({neu_v} statt {alt_v})."
        );
    } else if neu_v > alt_v {
        text += &format!(
            "\n\nDie Versionsnummer steigt von {alt_v} auf {neu_v} — der bisherige Lernstand \
             dieser Seite beginnt dann von vorn."
        );
    }
    app.dialog()
        .message(text)
        .title("Diese Seite gibt es schon")
        .kind(MessageDialogKind::Warning)
        .buttons(MessageDialogButtons::OkCancelCustom("Ersetzen".into(), "Abbrechen".into()))
        .blocking_show()
}

/// Fragt in der Oberflaeche nach Fach und Thema (zwei Felder mit Vorschlaegen —
/// das kann ein nativer Windows-Dialog nicht) und wartet auf die Antwort.
fn ort_erfragen(
    app: &AppHandle,
    faecher: &[bibliothek::Fach],
    titel: Option<&str>,
) -> Option<(String, String)> {
    let kern = kern(app);
    let (tx, rx) = mpsc::channel::<OrtWahl>();
    if let Ok(mut k) = kern.ort_kanal.lock() {
        *k = Some(tx);
    }
    let text = match titel {
        Some(t) => format!("„{t}“ "),
        None => "Die Seite ".into(),
    } + "trägt keine Kennung. Wähle ein Fach und ein Thema — oder tippe neue Namen ein.";
    let liste: Vec<_> = faecher
        .iter()
        .map(|f| json!({ "name": f.name, "themen": f.themen.iter().map(|t| &t.name).collect::<Vec<_>>() }))
        .collect();
    let _ = app.emit_to("haupt", "ort_fragen", json!({ "text": text, "faecher": liste }));

    let antwort = rx.recv_timeout(Duration::from_secs(600)).ok().flatten();
    if let Ok(mut k) = kern.ort_kanal.lock() {
        *k = None;
    }
    let (fach, thema) = antwort?;
    let fach = ordner_sicher(&fach);
    let thema = ordner_sicher(&thema);
    if fach.is_empty() || thema.is_empty() {
        melden(app, "Fach und Thema brauchen einen Namen.", "");
        return None;
    }
    Some((fach, thema))
}

/// Ordnernamen duerfen Grossbuchstaben und Umlaute behalten — nur nichts, was
/// Windows in Namen verbietet, und keinen fuehrenden Punkt oder Unterstrich.
fn ordner_sicher(name: &str) -> String {
    let s: String = name
        .trim()
        .chars()
        .map(|c| if "/\\:*?\"<>|".contains(c) || c.is_control() { '-' } else { c })
        .collect();
    s.trim_start_matches(['.', '_'])
        .trim_end_matches(['.', ' '])
        .to_string()
}

pub fn melden(app: &AppHandle, text: &str, detail: &str) {
    let inhalt = if detail.is_empty() { text.to_string() } else { format!("{text}\n\n{detail}") };
    app.dialog()
        .message(inhalt)
        .title("Lernkiste")
        .kind(MessageDialogKind::Info)
        .buttons(MessageDialogButtons::OkCustom("OK".into()))
        .blocking_show();
}

// MARK: - Text

fn sieht_aus_wie_html(s: &str) -> bool {
    let kopf: String = s.chars().take(4096).collect::<String>().to_lowercase();
    kopf.contains("<html") || kopf.contains("<!doctype html")
}

/// KIs verpacken Seiten gern in ```html … ``` und schreiben Saetze drumherum.
/// Hier bleibt nur die Seite selbst uebrig.
pub fn html_herausloesen(roh: &str) -> Option<String> {
    // Nur ASCII klein machen — so bleiben die Byte-Positionen gleich.
    let klein = roh.to_ascii_lowercase();
    let anfang = klein.find("<!doctype html").or_else(|| klein.find("<html"))?;
    let ende = klein.rfind("</html>")? + "</html>".len();
    if anfang >= ende {
        return None;
    }
    Some(format!("{}\n", &roh[anfang..ende]))
}

fn titel_tag(html: &str) -> Option<String> {
    bibliothek::titel_tag(html).filter(|t| !t.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn herausloesen() {
        let roh = "Hier ist die Seite:\n```html\n<!DOCTYPE html><html><body>ä</body></html>\n```\nViel Spaß";
        assert_eq!(
            html_herausloesen(roh).unwrap(),
            "<!DOCTYPE html><html><body>ä</body></html>\n"
        );
        assert!(html_herausloesen("nur Text").is_none());
    }

    #[test]
    fn teile_und_namen() {
        assert_eq!(
            id_teile("chemie/saeure-base/ph-und-titration"),
            Some(("chemie".into(), "saeure-base".into(), "ph-und-titration".into()))
        );
        assert_eq!(id_teile("../x"), None);
        assert_eq!(id_teile("a/../../b"), None);
        assert_eq!(sauber("_-Hallo Welt!"), "hallowelt");
        assert_eq!(ordner_name("saeure-base", Path::new("/gibt/es/nicht")), "Saeure-Base");
        assert_eq!(ordner_sicher("  ._Bio:Chemie?  "), "Bio-Chemie-");
    }
}
