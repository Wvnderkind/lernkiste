//! Was mit den letzten Updates neu kam — dieselbe Datei wie auf dem Mac
//! (Ressourcen/neuigkeiten.json). Punkte mit „[mac] “ gelten nur dort und
//! fallen hier weg, „[win] “ gilt nur hier.

use crate::orte::NEUIGKEITEN;
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Deserialize)]
struct Eintrag {
    datum: String,
    punkte: Vec<String>,
}

fn alle() -> Vec<Eintrag> {
    serde_json::from_str(NEUIGKEITEN).unwrap_or_default()
}

/// Kennzeichen des neuesten Eintrags — genau wie auf dem Mac gebildet.
pub fn kennung() -> Option<String> {
    alle().first().map(|e| {
        let mut teile = vec![e.datum.clone()];
        teile.extend(e.punkte.iter().cloned());
        teile.join("|")
    })
}

fn fuer_hier(punkt: &str) -> Option<String> {
    if punkt.starts_with("[mac] ") {
        None
    } else {
        Some(punkt.strip_prefix("[win] ").unwrap_or(punkt).to_string())
    }
}

pub fn fuer_windows() -> Value {
    let liste: Vec<Value> = alle()
        .into_iter()
        .filter_map(|e| {
            let punkte: Vec<String> = e.punkte.iter().filter_map(|p| fuer_hier(p)).collect();
            (!punkte.is_empty()).then(|| json!({ "datum": e.datum, "punkte": punkte }))
        })
        .collect();
    Value::Array(liste)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn datei_ist_lesbar_und_gefiltert() {
        assert!(!alle().is_empty(), "neuigkeiten.json nicht lesbar");
        let text = fuer_windows().to_string();
        assert!(!text.contains("[mac]") && !text.contains("[win]"));
    }
}
