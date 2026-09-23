//! Datum und Uhrzeit in denselben Formaten wie die Mac-App.

use chrono::{DateTime, Datelike, Local, NaiveDate, NaiveDateTime, TimeZone};

/// "2026-09-23"
pub fn heute() -> String {
    Local::now().format("%Y-%m-%d").to_string()
}

/// "2026-09-23T12:44:00" — Ortszeit, ohne Zeitzone (wie ISO8601 auf dem Mac).
pub fn jetzt_iso() -> String {
    Local::now().format("%Y-%m-%dT%H:%M:%S").to_string()
}

pub fn iso_lesen(text: Option<&str>) -> Option<DateTime<Local>> {
    let text = text?;
    let naiv = NaiveDateTime::parse_from_str(text, "%Y-%m-%dT%H:%M:%S").ok()?;
    Local.from_local_datetime(&naiv).earliest()
}

/// Ganze Tage seit einem Zeitpunkt, zur Null hin abgeschnitten.
pub fn tage_seit(datum: DateTime<Local>) -> i64 {
    (Local::now() - datum).num_days()
}

/// Ganze Tage bis Mitternacht eines Datums "JJJJ-MM-TT".
pub fn tage_bis(datum: &str) -> Option<(i64, NaiveDate)> {
    let tag = NaiveDate::parse_from_str(datum, "%Y-%m-%d").ok()?;
    let mitternacht = Local.from_local_datetime(&tag.and_hms_opt(0, 0, 0)?).earliest()?;
    Some(((mitternacht - Local::now()).num_days(), tag))
}

const WOCHENTAGE: [&str; 7] = [
    "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag",
];
const MONATE: [&str; 12] = [
    "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September",
    "Oktober", "November", "Dezember",
];

/// "23. September"
pub fn tag_monat(tag: NaiveDate) -> String {
    format!("{}. {}", tag.day(), MONATE[tag.month0() as usize])
}

/// "Mittwoch, 23. September"
pub fn wochentag_heute() -> String {
    let jetzt = Local::now().date_naive();
    format!(
        "{}, {}",
        WOCHENTAGE[jetzt.weekday().num_days_from_monday() as usize],
        tag_monat(jetzt)
    )
}

/// "2026-09-23-124400" — Stempel fuer Archivordner.
pub fn stempel() -> String {
    Local::now().format("%Y-%m-%d-%H%M%S").to_string()
}

pub fn stunde() -> u32 {
    use chrono::Timelike;
    Local::now().hour()
}
