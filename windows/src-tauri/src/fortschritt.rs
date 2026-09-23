//! Was eine Seite ueber ihren Stand verraet — ausgewertet und als Datei abgelegt.
//! Nachbau von Fortschritt.swift; die Dateien sind mit denen vom Mac austauschbar.

use crate::bibliothek::{ganzzahl, json_lesen, Seite};
use crate::orte::{atomar_schreiben, json_schoen, orte, vorbereiten};
use crate::zeit;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::{BTreeMap, HashMap};
use std::fs;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Tagespensum {
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub datum: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub ziel: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub geschafft: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub treffer: Option<i64>,
}

impl Tagespensum {
    pub fn erledigt(&self) -> bool {
        match (self.ziel, self.geschafft) {
            (Some(z), Some(g)) if z > 0 => g >= z && self.datum.as_deref() == Some(&zeit::heute()),
            _ => false,
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SeitenStand {
    pub seite: String,
    #[serde(default)]
    pub titel: String,
    #[serde(default)]
    pub fach: String,
    #[serde(default)]
    pub thema: String,
    #[serde(default)]
    pub typ: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub gesamt: Option<i64>,
    #[serde(default)]
    pub sitzen: i64,
    #[serde(default)]
    pub wackel: i64,
    #[serde(default)]
    pub geuebt: i64,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub tagespensum: Option<Tagespensum>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub zuletzt_geoeffnet: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub zuletzt_geuebt: Option<String>,
    #[serde(default)]
    pub wackel_items: Vec<String>,
    #[serde(default)]
    pub roh: BTreeMap<String, String>,
}

impl SeitenStand {
    pub fn anteil_sitzen(&self) -> f64 {
        match self.gesamt {
            Some(g) if g > 0 => self.sitzen as f64 / g as f64,
            _ => 0.0,
        }
    }
}

/// Wertet den rohen localStorage einer Seite aus.
/// `roh` enthaelt alle Schluessel, die mit "lern:" anfangen.
pub fn auswerten(roh: &HashMap<String, String>, seite: &Seite) -> SeitenStand {
    let praefix = format!("lern:{}@", seite.id);
    let mut stand = SeitenStand {
        seite: seite.id.clone(),
        titel: seite.titel.clone(),
        fach: seite.fach.clone(),
        thema: seite.thema.clone(),
        typ: seite.typ.clone(),
        // Alle Seiten teilen sich einen localStorage — nur behalten, was zu
        // dieser Seite gehoert.
        roh: roh
            .iter()
            .filter(|(k, _)| k.starts_with(&praefix))
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect(),
        zuletzt_geoeffnet: Some(zeit::jetzt_iso()),
        ..Default::default()
    };

    let hauptschluessel = format!("lern:{}@v{}", seite.id, seite.version);
    let Some(objekt) = roh
        .get(&hauptschluessel)
        .and_then(|t| serde_json::from_str::<Value>(t).ok())
        .and_then(|v| v.as_object().cloned())
    else {
        // Seite erfuellt den Vertrag nicht — wir wissen nur, dass sie offen war.
        return stand;
    };

    stand.gesamt = objekt.get("gesamt").and_then(ganzzahl);

    if let Some(items) = objekt.get("items").and_then(Value::as_object) {
        for (name, wert) in items {
            let Some(wert) = wert.as_object() else { continue };
            let sass = wert.get("sass").and_then(ganzzahl).unwrap_or(0);
            let sass_nicht = wert.get("sassNicht").and_then(ganzzahl).unwrap_or(0);
            if sass + sass_nicht <= 0 {
                continue;
            }
            stand.geuebt += 1;
            let wacklig = match wert.get("letzter").and_then(Value::as_str) {
                Some(letzter) => letzter != "sass",
                None => sass_nicht >= sass,
            };
            if wacklig {
                stand.wackel += 1;
                stand.wackel_items.push(name.clone());
            } else {
                stand.sitzen += 1;
            }
        }
        if stand.gesamt.is_none() {
            stand.gesamt = Some(items.len() as i64);
        }
    }
    stand.wackel_items.sort();

    if let Some(p) = objekt.get("tagespensum").and_then(Value::as_object) {
        stand.tagespensum = Some(Tagespensum {
            datum: p.get("datum").and_then(Value::as_str).map(String::from),
            ziel: p.get("ziel").and_then(ganzzahl),
            geschafft: p.get("geschafft").and_then(ganzzahl),
            treffer: p.get("treffer").and_then(ganzzahl),
        });
    }
    stand.zuletzt_geuebt = objekt
        .get("zuletztGeoeffnet")
        .and_then(Value::as_str)
        .map(String::from);
    stand
}

/// Legt den Stand einer Seite als eigene Datei ab.
pub fn sichern(stand: &SeitenStand) {
    vorbereiten();
    let name = format!("{}.json", stand.seite.replace('/', "__"));
    let Ok(wert) = serde_json::to_value(stand) else { return };
    let _ = atomar_schreiben(&orte().fortschritt.join(name), &json_schoen(&wert));
    uebersicht_schreiben();
}

/// Alle Staende — fuer Seitenleiste, Startseite und fuer Claude.
pub fn alle_staende() -> HashMap<String, SeitenStand> {
    let mut ergebnis = HashMap::new();
    let Ok(eintraege) = fs::read_dir(&orte().fortschritt) else { return ergebnis };
    for e in eintraege.flatten() {
        let pfad = e.path();
        let name = e.file_name().to_string_lossy().into_owned();
        if !name.ends_with(".json") || name == "uebersicht.json" {
            continue;
        }
        let Some(stand) = json_lesen(&pfad).and_then(|v| serde_json::from_value::<SeitenStand>(v).ok())
        else {
            continue;
        };
        ergebnis.insert(stand.seite.clone(), stand);
    }
    ergebnis
}

/// Eine einzelne Datei, die Claude zu Sessionbeginn liest.
fn uebersicht_schreiben() {
    let mut staende: Vec<SeitenStand> = alle_staende().into_values().collect();
    staende.sort_by(|a, b| {
        b.zuletzt_geoeffnet
            .as_deref()
            .unwrap_or("")
            .cmp(a.zuletzt_geoeffnet.as_deref().unwrap_or(""))
    });
    let mut u = Map::new();
    u.insert("erstellt".into(), Value::String(zeit::jetzt_iso()));
    u.insert(
        "staende".into(),
        serde_json::to_value(staende).unwrap_or(Value::Array(vec![])),
    );
    let _ = atomar_schreiben(
        &orte().fortschritt.join("uebersicht.json"),
        &json_schoen(&Value::Object(u)),
    );
}

// MARK: - Zustand der App (Favoriten, zuletzt geoeffnet, Hell/Dunkel)

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Zustand {
    #[serde(default)]
    pub favoriten: Vec<String>,
    /// Seiten-IDs, neueste zuerst.
    #[serde(default)]
    pub zuletzt: Vec<String>,
    #[serde(default = "dunkel")]
    pub theme: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub letzte_seite: Option<String>,
}

fn dunkel() -> String {
    "dark".into()
}

impl Default for Zustand {
    fn default() -> Self {
        Zustand { favoriten: vec![], zuletzt: vec![], theme: dunkel(), letzte_seite: None }
    }
}

impl Zustand {
    pub fn laden() -> Zustand {
        json_lesen(&orte().zustand)
            .and_then(|v| serde_json::from_value(v).ok())
            .unwrap_or_default()
    }

    pub fn sichern(&self) {
        vorbereiten();
        if let Ok(wert) = serde_json::to_value(self) {
            let _ = atomar_schreiben(&orte().zustand, &json_schoen(&wert));
        }
    }

    pub fn besucht(&mut self, id: &str) {
        self.zuletzt.retain(|z| z != id);
        self.zuletzt.insert(0, id.to_string());
        self.zuletzt.truncate(8);
        self.letzte_seite = Some(id.to_string());
        self.sichern();
    }

    pub fn favorit_umschalten(&mut self, id: &str) {
        if self.favoriten.iter().any(|f| f == id) {
            self.favoriten.retain(|f| f != id);
        } else {
            self.favoriten.push(id.to_string());
        }
        self.sichern();
    }
}
