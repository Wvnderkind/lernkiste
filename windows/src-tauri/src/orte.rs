//! Wo die Lernkiste ihre Daten ablegt — derselbe Aufbau wie auf dem Mac,
//! nur im Windows-Dokumente-Ordner: Dokumente\Lernkiste\.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

/// Der gemeinsame Motor aller Lernseiten, fest ins Programm eingebaut.
/// Quelle ist ausschliesslich Ressourcen/ im Repo — hier gibt es keine Kopie.
pub const MOTOR_JS: &str = include_str!("../../../Ressourcen/lernkiste.js");
pub const MOTOR_CSS: &str = include_str!("../../../Ressourcen/lernkiste.css");
pub const TOKENS_CSS: &str = include_str!("../../../Ressourcen/tokens.css");
pub const KI_VORLAGE: &str = include_str!("../../../Ressourcen/ki-vorlage.md");
pub const BEISPIEL: &str =
    include_str!("../../../Beispiel/Biochemie/Aminosaeuren/aminosaeuren-grundlagen.html");
/// Kennung der Beispielseite — solange nur sie da ist, zeigt die Startseite
/// die Anleitung „Erste Schritte“.
pub const BEISPIEL_ID: &str = "biochemie/aminosaeuren/aminosaeuren-grundlagen";
/// Was mit den letzten Updates neu kam (gemeinsam mit dem Mac).
pub const NEUIGKEITEN: &str = include_str!("../../../Ressourcen/neuigkeiten.json");
/// Gemeinsame Fassungsnummer mit dem Mac, z. B. "202609231244".
pub const STAND: &str = include_str!("../../../STAND");

pub const GIF_ANLAESSE: [&str; 3] = ["fertig", "meilenstein", "durchhaenger"];

pub struct Orte {
    pub daten: PathBuf,
    pub seiten: PathBuf,
    pub fortschritt: PathBuf,
    pub gifs: PathBuf,
    pub gif_nutzung: PathBuf,
    pub tagesplan: PathBuf,
    pub konfig: PathBuf,
    pub zustand: PathBuf,
    pub motor: PathBuf,
    pub archiv: PathBuf,
}

static ORTE: OnceLock<Orte> = OnceLock::new();

/// Zum Testen laesst sich der Datenordner umlenken (LERNKISTE_DATEN=…).
pub fn orte() -> &'static Orte {
    ORTE.get_or_init(|| {
        let daten = std::env::var_os("LERNKISTE_DATEN")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                dirs::document_dir()
                    .or_else(|| dirs::home_dir().map(|h| h.join("Documents")))
                    .unwrap_or_else(|| PathBuf::from("."))
                    .join("Lernkiste")
            });
        let seiten = daten.join("Seiten");
        let gifs = daten.join("gifs");
        Orte {
            fortschritt: daten.join("fortschritt"),
            gif_nutzung: gifs.join("nutzung.json"),
            tagesplan: daten.join("tagesplan.json"),
            konfig: daten.join("konfiguration.json"),
            zustand: daten.join("zustand.json"),
            motor: seiten.join("_motor"),
            archiv: daten.join("_archiv"),
            seiten,
            gifs,
            daten,
        }
    })
}

pub fn stand() -> &'static str {
    STAND.trim()
}

/// Legt alle Ordner an und spiegelt den Motor nach Seiten\_motor, damit jede
/// Seite ihn ueber ../../_motor/ laden kann — auch beim Doppelklick im Browser.
pub fn vorbereiten() {
    let o = orte();
    let mut ordner = vec![&o.daten, &o.seiten, &o.fortschritt, &o.gifs, &o.motor];
    let anlaesse: Vec<PathBuf> = GIF_ANLAESSE.iter().map(|a| o.gifs.join(a)).collect();
    ordner.extend(anlaesse.iter());
    for pfad in ordner {
        let _ = fs::create_dir_all(pfad);
    }
    for (name, inhalt) in [("lernkiste.js", MOTOR_JS), ("lernkiste.css", MOTOR_CSS)] {
        let ziel = o.motor.join(name);
        // Nur schreiben, wenn sich wirklich etwas geaendert hat.
        if fs::read(&ziel).map(|alt| alt == inhalt.as_bytes()).unwrap_or(false) {
            continue;
        }
        let _ = fs::write(&ziel, inhalt);
    }
}

/// Beim allerersten Start ist Seiten\ leer: dann die Beispielseite einlegen,
/// damit man sofort etwas zum Ausprobieren hat.
pub fn beispiel_einlegen() {
    let o = orte();
    let leer = fs::read_dir(&o.seiten)
        .map(|eintraege| {
            eintraege
                .flatten()
                .all(|e| e.file_name().to_string_lossy().starts_with(['_', '.']))
        })
        .unwrap_or(true);
    if !leer {
        return;
    }
    let ziel = o.seiten.join("Biochemie").join("Aminosaeuren");
    if fs::create_dir_all(&ziel).is_ok() {
        let _ = fs::write(ziel.join("aminosaeuren-grundlagen.html"), BEISPIEL);
    }
}

/// Atomar schreiben: erst in eine Nachbardatei, dann umbenennen.
pub fn atomar_schreiben(ziel: &Path, inhalt: &[u8]) -> std::io::Result<()> {
    let mut temp = ziel.as_os_str().to_owned();
    temp.push(".neu");
    let temp = PathBuf::from(temp);
    fs::write(&temp, inhalt)?;
    fs::rename(&temp, ziel)
}

/// JSON wie auf dem Mac: eingerueckt und mit sortierten Schluesseln
/// (serde_json::Map ist ohne preserve_order ohnehin sortiert).
pub fn json_schoen(wert: &serde_json::Value) -> Vec<u8> {
    serde_json::to_vec_pretty(wert).unwrap_or_default()
}
