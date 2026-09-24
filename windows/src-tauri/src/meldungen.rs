//! Gemeldete Aufgaben („⚑ Melden“): eine schlichte Sammelliste in
//! Dokumente\Lernkiste\meldungen.json. Nachbau von `enum Meldungen` in Modell.swift.

use crate::bibliothek;
use crate::orte::{self, orte};
use crate::zeit;
use serde_json::Value;

pub fn alle() -> Vec<Value> {
    bibliothek::json_lesen(&orte().meldungen)
        .and_then(|v| v.as_array().cloned())
        .unwrap_or_default()
}

/// Wie viele Meldungen noch nicht als erledigt markiert sind.
pub fn offen() -> usize {
    alle()
        .iter()
        .filter(|m| !m.get("erledigt").and_then(Value::as_bool).unwrap_or(false))
        .count()
}

pub fn anhaengen(eintrag: Value) {
    let Value::Object(mut e) = eintrag else { return };
    orte::vorbereiten();
    e.insert("erledigt".into(), Value::Bool(false));
    if !e.contains_key("datum") {
        e.insert("datum".into(), Value::String(zeit::jetzt_iso()));
    }
    let mut liste = alle();
    liste.push(Value::Object(e));
    let _ = orte::atomar_schreiben(&orte().meldungen, &orte::json_schoen(&Value::Array(liste)));
}
