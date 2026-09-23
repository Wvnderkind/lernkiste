//! Der gemeinsame Zustand der laufenden Lernkiste — Server, Befehle und
//! Menue greifen alle darauf zu.

use crate::bibliothek::{self, Fach, Seite};
use crate::fortschritt::Zustand;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::sync::mpsc::Sender;
use std::sync::Mutex;
use std::time::Instant;

pub const STANDARD_PORT: u16 = 47623;

/// Antwort aus dem Dialog „Wohin gehoert die Seite?": (Fach, Thema) oder Abbruch.
pub type OrtWahl = Option<(String, String)>;

pub struct Kern {
    pub port: u16,
    pub faecher: Mutex<Vec<Fach>>,
    pub zustand: Mutex<Zustand>,
    /// Wartet ein Import gerade auf die Antwort aus dem Orts-Dialog?
    pub ort_kanal: Mutex<Option<Sender<OrtWahl>>>,
    /// Wartet jemand darauf, dass die Oberflaeche den Fortschritt gesichert hat?
    pub gesichert_kanal: Mutex<Option<Sender<()>>>,
    /// Menuepunkt und Tastenkuerzel koennen beide ausloesen — nur einmal ausfuehren.
    pub menue_zuletzt: Mutex<HashMap<String, Instant>>,
    /// Gefundenes Update, bereit zum Installieren.
    pub update: Mutex<Option<tauri_plugin_updater::Update>>,
    /// Was der Update-Knopf gerade zeigt (Text, klickbar).
    pub update_knopf: Mutex<Option<(String, bool)>>,
    pub update_laeuft: AtomicBool,
    /// Die Oberflaeche hat sich gemeldet und kann Ereignisse empfangen.
    pub bereit: AtomicBool,
    /// Dateien, die vor dem Start der Oberflaeche geoeffnet werden sollten.
    pub wartende_dateien: Mutex<Vec<PathBuf>>,
    /// Einmal gesetzt, darf das Fenster wirklich zugehen.
    pub darf_schliessen: AtomicBool,
}

impl Kern {
    pub fn neu() -> Kern {
        let port = std::env::var("LERNKISTE_PORT")
            .ok()
            .and_then(|p| p.parse().ok())
            .unwrap_or(STANDARD_PORT);
        Kern {
            port,
            faecher: Mutex::new(Vec::new()),
            zustand: Mutex::new(Zustand::laden()),
            ort_kanal: Mutex::new(None),
            gesichert_kanal: Mutex::new(None),
            menue_zuletzt: Mutex::new(HashMap::new()),
            update: Mutex::new(None),
            update_knopf: Mutex::new(None),
            update_laeuft: AtomicBool::new(false),
            bereit: AtomicBool::new(false),
            wartende_dateien: Mutex::new(Vec::new()),
            darf_schliessen: AtomicBool::new(false),
        }
    }

    pub fn basis(&self) -> String {
        format!("http://127.0.0.1:{}", self.port)
    }

    pub fn neu_einlesen(&self) {
        let neu = bibliothek::einlesen();
        if let Ok(mut f) = self.faecher.lock() {
            *f = neu;
        }
    }

    /// Nur "dark" oder "light" — der Wert landet in Skripten und Attributen.
    pub fn theme(&self) -> &'static str {
        match self.zustand.lock().map(|z| z.theme == "light") {
            Ok(true) => "light",
            _ => "dark",
        }
    }

    pub fn seiten_ids(&self) -> Vec<String> {
        self.faecher
            .lock()
            .map(|f| bibliothek::alle_seiten(&f).iter().map(|s| s.id.clone()).collect())
            .unwrap_or_default()
    }

    pub fn seite(&self, id: &str) -> Option<Seite> {
        let f = self.faecher.lock().ok()?;
        bibliothek::alle_seiten(&f).into_iter().find(|s| s.id == id).cloned()
    }
}
