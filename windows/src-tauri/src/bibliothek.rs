//! Liest den Lernseiten-Ordner ein und baut daraus den Baum Fach → Thema → Seite.
//! Nachbau von Modell.swift.

use crate::orte::orte;
use crate::zeit;
use regex::RegexBuilder;
use serde::Serialize;
use serde_json::Value;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Seite {
    pub id: String,
    pub titel: String,
    pub typ: String,
    pub version: i64,
    pub fach: String,
    pub thema: String,
    #[serde(skip)]
    pub datei: PathBuf,
    pub relativer_pfad: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct Thema {
    pub name: String,
    pub seiten: Vec<Seite>,
}

#[derive(Clone, Debug, Serialize)]
pub struct Fach {
    pub name: String,
    pub themen: Vec<Thema>,
    pub archiv: bool,
}

impl Fach {
    pub fn alle_seiten(&self) -> impl Iterator<Item = &Seite> {
        self.themen.iter().flat_map(|t| t.seiten.iter())
    }
}

pub fn alle_seiten(faecher: &[Fach]) -> Vec<&Seite> {
    faecher.iter().flat_map(|f| f.alle_seiten()).collect()
}

pub fn fach_ist_archiv(faecher: &[Fach], fach: &str) -> bool {
    faecher.iter().find(|f| f.name == fach).map(|f| f.archiv).unwrap_or(false)
}

/// Unterordner eines Ordners, sortiert; versteckte und solche mit fuehrendem _
/// (Werkstatt, z. B. _motor) fallen heraus.
fn unterordner(ordner: &Path) -> Vec<(String, PathBuf)> {
    let mut liste: Vec<(String, PathBuf)> = fs::read_dir(ordner)
        .map(|e| {
            e.flatten()
                .filter(|e| e.path().is_dir())
                .map(|e| (e.file_name().to_string_lossy().into_owned(), e.path()))
                .filter(|(n, _)| !n.starts_with('.') && !n.starts_with('_'))
                .collect()
        })
        .unwrap_or_default();
    liste.sort_by(|a, b| a.0.cmp(&b.0));
    liste
}

pub fn einlesen() -> Vec<Fach> {
    let konfig = Konfiguration::laden();
    let mut faecher = Vec::new();

    for (fach_name, fach_pfad) in unterordner(&orte().seiten) {
        let mut themen = Vec::new();
        for (thema_name, thema_pfad) in unterordner(&fach_pfad) {
            let mut seiten: Vec<Seite> = fs::read_dir(&thema_pfad)
                .map(|e| {
                    e.flatten()
                        .map(|e| e.path())
                        .filter(|p| p.is_file())
                        .filter(|p| {
                            let name = p.file_name().unwrap_or_default().to_string_lossy();
                            // Dateien mit fuehrendem _ sind Hilfs-/Testdateien.
                            !name.starts_with('_')
                                && !name.starts_with('.')
                                && endung(p) == "html"
                        })
                        .map(|p| seite_lesen(&p, &fach_name, &thema_name))
                        .collect()
                })
                .unwrap_or_default();
            if seiten.is_empty() {
                continue;
            }
            seiten.sort_by_key(|s| s.titel.to_lowercase());
            themen.push(Thema { name: thema_name, seiten });
        }
        if themen.is_empty() {
            continue;
        }
        let archiv = konfig.archiv_faecher.contains(&fach_name);
        faecher.push(Fach { name: fach_name, themen, archiv });
    }

    // Aktive Faecher zuerst, danach das Archiv — jeweils alphabetisch.
    faecher.sort_by(|a, b| {
        a.archiv
            .cmp(&b.archiv)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    faecher
}

pub fn endung(p: &Path) -> String {
    p.extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default()
}

fn seite_lesen(datei: &Path, fach: &str, thema: &str) -> Seite {
    let kopf = kopf_lesen(datei);
    let slug = datei
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let dateiname = datei
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let id = meta(&kopf, "lernkiste-id").unwrap_or_else(|| {
        format!("{}/{}/{}", entschaerft(fach), entschaerft(thema), entschaerft(&slug))
    });
    let titel = meta(&kopf, "lernkiste-titel")
        .or_else(|| titel_tag(&kopf))
        .unwrap_or_else(|| slug.clone());
    Seite {
        id,
        titel,
        typ: meta(&kopf, "lernkiste-typ").unwrap_or_else(|| "seite".into()),
        version: version_aus(&kopf),
        fach: fach.into(),
        thema: thema.into(),
        datei: datei.to_path_buf(),
        relativer_pfad: format!("{fach}/{thema}/{dateiname}"),
    }
}

pub fn version_aus(html: &str) -> i64 {
    meta(html, "lernkiste-version")
        .and_then(|v| v.parse().ok())
        .unwrap_or(1)
}

/// Nur die ersten Kilobytes, nicht die ganze Datei.
fn kopf_lesen(datei: &Path) -> String {
    let mut puffer = Vec::with_capacity(16_384);
    if let Ok(f) = fs::File::open(datei) {
        let _ = f.take(16_384).read_to_end(&mut puffer);
    }
    String::from_utf8_lossy(&puffer).into_owned()
}

pub fn meta(html: &str, name: &str) -> Option<String> {
    let muster = format!(
        r#"<meta\s+name=["']{}["']\s+content=["']([^"']*)["']"#,
        regex::escape(name)
    );
    erste_gruppe(html, &muster)
}

pub fn titel_tag(html: &str) -> Option<String> {
    erste_gruppe(html, r"<title>([^<]*)</title>").map(|t| t.trim().to_string())
}

fn erste_gruppe(text: &str, muster: &str) -> Option<String> {
    let re = RegexBuilder::new(muster).case_insensitive(true).build().ok()?;
    re.captures(text)?.get(1).map(|m| m.as_str().to_string())
}

/// "Kopf-Hals" → "kopf-hals", "Hirnhäute-Liquor" → "hirnhaeute-liquor"
pub fn entschaerft(text: &str) -> String {
    text.to_lowercase()
        .replace('ä', "ae")
        .replace('ö', "oe")
        .replace('ü', "ue")
        .replace('ß', "ss")
        .replace(' ', "-")
}

// MARK: - Konfiguration

pub struct Termin {
    pub name: String,
    pub datum: String,
}

#[derive(Default)]
pub struct Konfiguration {
    pub archiv_faecher: Vec<String>,
    pub naechster_termin: Option<Termin>,
}

impl Konfiguration {
    /// Tolerant: eine unvollstaendige Datei verwirft nicht die ganze Konfiguration.
    pub fn laden() -> Konfiguration {
        let Some(wert) = json_lesen(&orte().konfig) else {
            return Konfiguration::default();
        };
        let archiv_faecher = wert
            .get("archivFaecher")
            .and_then(Value::as_array)
            .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
            .unwrap_or_default();
        let naechster_termin = wert.get("naechsterTermin").and_then(|t| {
            Some(Termin {
                name: t.get("name")?.as_str()?.to_string(),
                datum: t.get("datum")?.as_str()?.to_string(),
            })
        });
        Konfiguration { archiv_faecher, naechster_termin }
    }
}

pub fn json_lesen(pfad: &Path) -> Option<Value> {
    let text = fs::read(pfad).ok()?;
    serde_json::from_slice(&text).ok()
}

// MARK: - Tagesplan

pub struct Eintrag {
    pub seite: String,
    pub ziel: Option<i64>,
    pub hinweis: Option<String>,
}

pub struct Tagesplan {
    pub datum: String,
    pub eintraege: Vec<Eintrag>,
}

impl Tagesplan {
    pub fn laden() -> Option<Tagesplan> {
        let wert = json_lesen(&orte().tagesplan)?;
        let eintraege = wert
            .get("eintraege")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(|e| {
                        Some(Eintrag {
                            seite: e.get("seite")?.as_str()?.to_string(),
                            ziel: e.get("ziel").and_then(ganzzahl),
                            hinweis: e.get("hinweis").and_then(Value::as_str).map(String::from),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        Some(Tagesplan {
            datum: wert.get("datum").and_then(Value::as_str).unwrap_or("").to_string(),
            eintraege,
        })
    }

    pub fn fuer_heute(&self) -> bool {
        self.datum == zeit::heute()
    }

    /// Die Eintraege unveraendert als JSON-Text — so kommen auch Felder bei der
    /// Seite an, die die App gar nicht kennt (umfang, modus, kategorien …).
    pub fn roh_eintraege_json() -> String {
        json_lesen(&orte().tagesplan)
            .filter(|w| w.get("datum").and_then(Value::as_str) == Some(zeit::heute().as_str()))
            .and_then(|w| w.get("eintraege").filter(|e| e.is_array()).cloned())
            .map(|e| e.to_string())
            .unwrap_or_else(|| "[]".into())
    }
}

/// Zahl aus JSON, auch wenn sie als 3.0 kommt.
pub fn ganzzahl(v: &Value) -> Option<i64> {
    v.as_i64().or_else(|| {
        v.as_f64()
            .filter(|f| f.fract() == 0.0 && f.abs() < 9e15)
            .map(|f| f as i64)
    })
}
