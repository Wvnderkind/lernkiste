// Lernseiten weitergeben: Rechtsklick in der Leiste → „Exportieren …“ legt die
// Seite als .html-Datei ab, ein ganzes Thema oder Fach als ZIP-Paket mit den
// Ordnern <Paket>/<Fach>/<Thema>/ — genau so, wie es die Mac-Fassung beim
// Teilen packt. Der Lernstand bleibt immer hier: er steckt nicht in der Datei.

use crate::bibliothek::Seite;
use crate::import::melden;
use crate::kern::Kern;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tauri::{AppHandle, Manager};
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_opener::OpenerExt;

pub fn exportieren(app: &AppHandle, ids: Vec<String>, name: String) {
    let kern = app.state::<Arc<Kern>>().inner().clone();
    let seiten: Vec<Seite> = ids.iter().filter_map(|id| kern.seite(id)).collect();
    let app = app.clone();
    std::thread::spawn(move || {
        if seiten.is_empty() {
            melden(
                &app,
                "Öffne zuerst eine Seite.",
                "Ganze Themen und Fächer exportierst du mit einem Rechtsklick in der Seitenleiste.",
            );
            return;
        }
        let einzeln = seiten.len() == 1;
        let vorschlag = if einzeln {
            seiten[0].datei.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
        } else {
            format!("{} (Lernkiste).zip", dateiname(&name))
        };
        let mut frage = app
            .dialog()
            .file()
            .set_title(if einzeln { "Seite exportieren" } else { "Lernseiten exportieren" })
            .set_file_name(&vorschlag);
        frage = if einzeln {
            frage.add_filter("Lernseite", &["html", "htm"])
        } else {
            frage.add_filter("ZIP-Paket", &["zip"])
        };
        if let Ok(desktop) = app.path().desktop_dir() {
            frage = frage.set_directory(desktop);
        }
        if let Some(f) = app.get_webview_window("haupt") {
            frage = frage.set_parent(&f);
        }
        let Some(ziel) = frage.blocking_save_file().and_then(|p| p.into_path().ok()) else { return };

        let ergebnis = if einzeln {
            fs::copy(&seiten[0].datei, &ziel).map(|_| ()).map_err(|e| e.to_string())
        } else {
            paket_schreiben(&seiten, &name, &ziel)
        };
        match ergebnis {
            Ok(()) => {
                let _ = app.opener().reveal_item_in_dir(&ziel);
            }
            Err(fehler) => melden(&app, "Der Export hat nicht geklappt.", &fehler),
        }
    });
}

/// Zeigt die Seite (ebene 0), ihren Themenordner (1) oder Fachordner (2) im Explorer.
pub fn zeigen(app: &AppHandle, id: &str, ebene: u8) {
    let kern = app.state::<Arc<Kern>>();
    let Some(seite) = kern.seite(id) else { return };
    let mut pfad: &Path = &seite.datei;
    for _ in 0..ebene.min(2) {
        pfad = pfad.parent().unwrap_or(pfad);
    }
    let _ = app.opener().reveal_item_in_dir(pfad);
}

/// Packt die Seiten als <Paket>/<Fach>/<Thema>/<datei>.html. Die zip-Bibliothek
/// kennzeichnet Namen mit Umlauten selbst als UTF-8.
fn paket_schreiben(seiten: &[Seite], name: &str, ziel: &PathBuf) -> Result<(), String> {
    let paket = dateiname(&format!("{name} (Lernkiste)"));
    let datei = fs::File::create(ziel).map_err(|e| e.to_string())?;
    let mut zip = zip::ZipWriter::new(datei);
    let optionen = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);
    for s in seiten {
        let inhalt = fs::read(&s.datei).map_err(|e| e.to_string())?;
        let dateiname_html = s.datei.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let pfad = format!("{}/{}/{}/{}", paket, dateiname(&s.fach), dateiname(&s.thema), dateiname_html);
        zip.start_file(pfad, optionen).map_err(|e| e.to_string())?;
        zip.write_all(&inhalt).map_err(|e| e.to_string())?;
    }
    zip.finish().map_err(|e| e.to_string())?;
    Ok(())
}

/// Ordner- und Paketnamen ohne Zeichen, die im Dateisystem stoeren.
fn dateiname(s: &str) -> String {
    let n: String = s
        .chars()
        .map(|c| if "/\\:*?\"<>|".contains(c) || c.is_control() { '-' } else { c })
        .collect();
    let n = n.trim().trim_end_matches('.').to_string();
    if n.is_empty() { "Lernseiten".into() } else { n }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paket_mit_umlauten() {
        let ordner = std::env::temp_dir().join("lernkiste-export-test");
        let _ = fs::remove_dir_all(&ordner);
        fs::create_dir_all(&ordner).unwrap();
        let html = ordner.join("seite.html");
        fs::write(&html, "<html>x</html>").unwrap();
        let seite = Seite {
            id: "a/b/seite".into(),
            titel: "Seite".into(),
            typ: "".into(),
            version: 1,
            fach: "ZNS".into(),
            thema: "Großhirn: Rinde".into(),
            datei: html,
            relativer_pfad: "".into(),
        };
        let html2 = ordner.join("zweite.html");
        fs::write(&html2, "<html>y</html>").unwrap();
        let zweite = Seite { datei: html2, ..seite.clone() };
        let ziel = ordner.join("paket.zip");
        paket_schreiben(&[seite, zweite], "ZNS – Großhirn", &ziel).unwrap();
        let mut archiv = zip::ZipArchive::new(fs::File::open(&ziel).unwrap()).unwrap();
        assert_eq!(archiv.len(), 2);
        let eintrag = archiv.by_index(0).unwrap();
        assert_eq!(eintrag.name(), "ZNS – Großhirn (Lernkiste)/ZNS/Großhirn- Rinde/seite.html");
        drop(eintrag);
        // Bit 11 im Kopf: Namen sind UTF-8 — sonst zeigt Windows „Gro├ƒhirn“.
        let roh = fs::read(&ziel).unwrap();
        assert_eq!(u16::from_le_bytes([roh[6], roh[7]]) & 0x0800, 0x0800);
        let _ = fs::remove_dir_all(&ordner);
    }
}
