//! Winziger HTTP-Server, der nur auf 127.0.0.1 lauscht und ausschliesslich
//! Dateien unterhalb des Lernkiste-Ordners ausliefert. Nachbau von Server.swift.
//!
//! Warum ein Server? Unter http://127.0.0.1:<fester Port> ist der Ursprung
//! stabil, und localStorage — also der Lernstand — bleibt zuverlaessig erhalten.

use crate::bibliothek::{self, Tagesplan};
use crate::fortschritt;
use crate::kern::Kern;
use crate::orte::{self, orte};
use crate::startseite;
use crate::zeit;
use percent_encoding::percent_decode_str;
use serde_json::{json, Map, Value};
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, Mutex};
use tiny_http::{Header, Method, Request, Response};

const UI_HTML: &str = include_str!("../../ui/index.html");
const UI_CSS: &str = include_str!("../../ui/app.css");
const UI_JS: &str = include_str!("../../ui/app.js");

/// Lernseiten duerfen nichts aus dem Netz laden und nichts dorthin schicken.
const SCHUTZ: &str = "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; \
style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' data: blob:; \
font-src 'self' data:; connect-src 'self'; frame-src 'self' data: blob:; object-src 'none'; \
form-action 'none'; base-uri 'self'";

/// Die App-Oberflaeche selbst: zusaetzlich der Draht zum Programm (ipc:), und
/// im Rahmen duerfen nur Seiten von hier erscheinen — nie etwas aus dem Netz.
const SCHUTZ_APP: &str = "default-src 'self'; script-src 'self' 'unsafe-inline'; \
style-src 'self' 'unsafe-inline'; img-src 'self' data:; \
connect-src 'self' ipc: http://ipc.localhost; frame-src 'self' data: blob:; \
object-src 'none'; form-action 'none'; base-uri 'self'";

pub fn starten(kern: Arc<Kern>) -> Result<(), String> {
    let server = tiny_http::Server::http(("127.0.0.1", kern.port)).map_err(|e| e.to_string())?;
    let server = Arc::new(server);
    let gif_nutzung = Arc::new(Mutex::new(
        bibliothek::json_lesen(&orte().gif_nutzung)
            .and_then(|v| v.as_object().cloned())
            .unwrap_or_default(),
    ));
    // Ein paar Arbeiter, damit eine lange Antwort die anderen nicht aufhaelt.
    for _ in 0..4 {
        let server = server.clone();
        let kern = kern.clone();
        let gif_nutzung = gif_nutzung.clone();
        std::thread::spawn(move || {
            for anfrage in server.incoming_requests() {
                bedienen(anfrage, &kern, &gif_nutzung);
            }
        });
    }
    Ok(())
}

struct Antwort {
    code: u16,
    typ: String,
    koerper: Vec<u8>,
    schutz: Option<&'static str>,
}

fn bedienen(anfrage: Request, kern: &Kern, gif_nutzung: &Mutex<Map<String, Value>>) {
    let antwort = antwort_fuer(&anfrage, kern, gif_nutzung);
    let mut r = Response::from_data(antwort.koerper).with_status_code(antwort.code);
    let mut kopf = vec![
        ("Content-Type", antwort.typ.as_str()),
        ("Cache-Control", "no-store"),
    ];
    if let Some(schutz) = antwort.schutz {
        kopf.push(("Content-Security-Policy", schutz));
    }
    for (k, v) in kopf {
        if let Ok(h) = Header::from_bytes(k.as_bytes(), v.as_bytes()) {
            r = r.with_header(h);
        }
    }
    let _ = anfrage.respond(r);
}

fn antwort_fuer(anfrage: &Request, kern: &Kern, gif_nutzung: &Mutex<Map<String, Value>>) -> Antwort {
    if *anfrage.method() != Method::Get {
        return fehler(405, "Nur GET");
    }
    // Schutz gegen Zugriffe von aussen (DNS-Rebinding): der Host-Kopf muss
    // wirklich auf unseren lokalen Port zeigen.
    let host = anfrage
        .headers()
        .iter()
        .find(|h| h.field.equiv("Host"))
        .map(|h| h.value.as_str().trim().to_string())
        .unwrap_or_default();
    if host != format!("127.0.0.1:{}", kern.port) && host != format!("localhost:{}", kern.port) {
        return fehler(403, "Fremder Host");
    }

    let url = anfrage.url();
    let pfad = url.split('?').next().unwrap_or("");
    let pfad = percent_decode_str(pfad).decode_utf8_lossy().into_owned();

    if pfad == "/" || pfad == "/start" {
        return html(mit_bruecke(&kern.startseite_html(), kern));
    }
    if let Some(rel) = pfad.strip_prefix("/seite/") {
        let a = datei(rel, &orte().seiten);
        if a.code == 200 && a.typ.starts_with("text/html") {
            let text = String::from_utf8_lossy(&a.koerper).into_owned();
            return html(mit_bruecke(&text, kern));
        }
        return a;
    }
    if let Some(rel) = pfad.strip_prefix("/gif/") {
        let a = datei(rel, &orte().gifs);
        if a.code == 200 {
            gif_gezaehlt(rel, gif_nutzung);
        }
        return a;
    }
    if let Some(rel) = pfad.strip_prefix("/res/") {
        return match rel {
            "tokens.css" => ok(orte::TOKENS_CSS.as_bytes().to_vec(), "css"),
            "lernkiste.css" => ok(orte::MOTOR_CSS.as_bytes().to_vec(), "css"),
            "lernkiste.js" => ok(orte::MOTOR_JS.as_bytes().to_vec(), "js"),
            _ => fehler(404, "Nicht gefunden"),
        };
    }
    match pfad.as_str() {
        "/app" | "/app/" | "/app/index.html" => {
            let mut a = ok(UI_HTML.as_bytes().to_vec(), "html");
            a.schutz = Some(SCHUTZ_APP);
            a
        }
        "/app/app.css" => ok(UI_CSS.as_bytes().to_vec(), "css"),
        "/app/app.js" => ok(UI_JS.as_bytes().to_vec(), "js"),
        _ => fehler(404, "Nicht gefunden"),
    }
}

// MARK: - Bruecke

/// Setzt das Brueckenskript ganz an den Anfang der Seite, damit es vor allen
/// Skripten der Seite laeuft — so findet der Motor window.Lernkiste schon vor.
fn mit_bruecke(html: &str, kern: &Kern) -> String {
    let skript = format!("<script>{}</script>", bruecke_js(kern));
    let stelle = oeffnendes_tag_ende(html, "<head")
        .or_else(|| oeffnendes_tag_ende(html, "<html"))
        .or_else(|| oeffnendes_tag_ende(html, "<!doctype"))
        .unwrap_or(0);
    let mut ergebnis = String::with_capacity(html.len() + skript.len());
    ergebnis.push_str(&html[..stelle]);
    ergebnis.push_str(&skript);
    ergebnis.push_str(&html[stelle..]);
    ergebnis
}

/// Position direkt hinter dem ersten Tag `name` (ohne Beachtung der
/// Gross-/Kleinschreibung); "<header" zaehlt nicht als "<head".
fn oeffnendes_tag_ende(html: &str, name: &str) -> Option<usize> {
    let klein = html.to_ascii_lowercase();
    let mut ab = 0;
    while let Some(pos) = klein[ab..].find(name) {
        let start = ab + pos;
        let danach = klein.as_bytes().get(start + name.len()).copied();
        match danach {
            Some(b'>') | Some(b' ') | Some(b'\t') | Some(b'\n') | Some(b'\r') | Some(b'/') => {
                let ende = klein[start..].find('>')?;
                return Some(start + ende + 1);
            }
            _ => ab = start + name.len(),
        }
    }
    None
}

/// JSON so, dass es gefahrlos in einem <script> stehen kann.
fn skript_json(text: &str) -> String {
    text.replace("</", "<\\/")
        .replace('\u{2028}', "\\u2028")
        .replace('\u{2029}', "\\u2029")
}

fn bruecke_js(kern: &Kern) -> String {
    let theme = kern.theme();
    let eintraege = skript_json(&Tagesplan::roh_eintraege_json());
    let gifs = skript_json(&gifs_json(kern));
    format!(
        r#"(function(){{
  var eintraege = {eintraege};
  var gifs = {gifs};
  function sende(n){{ try {{ if (window.parent !== window) window.parent.postMessage(n, location.origin); }} catch(e){{}} }}
  window.Lernkiste = {{
    version: 1,
    theme: "{theme}",
    tagesplan: function(id){{
      for (var i=0;i<eintraege.length;i++){{
        if (eintraege[i] && eintraege[i].seite === id) return eintraege[i];
      }}
      return null;
    }},
    gif: function(id, anlass){{
      var a = anlass || 'fertig', name = null;
      if (a === 'fertig') name = (gifs.fertig || {{}})[id];
      else {{
        var liste = gifs[a] || [];
        if (liste.length) name = liste[Math.floor(Math.random()*liste.length)];
      }}
      return name ? '/gif/' + a + '/' + encodeURIComponent(name) : null;
    }},
    fertig: function(ergebnis){{ sende({{art:"fertig", ergebnis: ergebnis||null}}); }},
    oeffne: function(id){{ sende({{art:"oeffnen", id:id}}); }}
  }};
  window.oeffne = window.Lernkiste.oeffne;
  document.documentElement.dataset.theme = window.Lernkiste.theme;

  var s = document.createElement('style');
  s.textContent =
      'html,body{{-webkit-user-select:none;user-select:none}}'
    + 'input,textarea,[contenteditable="true"]{{-webkit-user-select:text;user-select:text}}'
    + '::selection{{background:rgba(255,255,255,.16)}}'
    + ':root[data-theme="light"] ::selection{{background:rgba(0,0,0,.12)}}';
  document.documentElement.appendChild(s);

  var obenZuletzt = null;
  function melden(){{
    var oben = (window.scrollY || document.documentElement.scrollTop || 0) <= 2;
    if (oben === obenZuletzt) return;
    obenZuletzt = oben;
    sende({{art:'scroll', oben:oben}});
  }}
  window.addEventListener('scroll', melden, {{passive:true}});
  window.addEventListener('load', melden);
  document.addEventListener('DOMContentLoaded', melden);

  function nachAussen(href){{
    try {{
      var u = new URL(href, location.href);
      if (u.protocol === 'mailto:') return u.href;
      if ((u.protocol === 'http:' || u.protocol === 'https:') && u.origin !== location.origin) return u.href;
    }} catch(e){{}}
    return null;
  }}
  document.addEventListener('click', function(e){{
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var ziel = nachAussen(a.getAttribute('href'));
    if (!ziel) return;
    e.preventDefault();
    sende({{art:'extern', url: ziel}});
  }}, true);
  var altesOpen = window.open;
  window.open = function(href){{
    var ziel = href ? nachAussen(String(href)) : null;
    if (ziel) {{ sende({{art:'extern', url: ziel}}); return null; }}
    return altesOpen ? altesOpen.apply(window, arguments) : null;
  }};

  document.addEventListener('keydown', function(e){{
    if (!e.ctrlKey || e.altKey || e.metaKey) return;
    var k = (e.key || '').toLowerCase(), aktion = null;
    if (k === 'r' && !e.shiftKey) aktion = 'neu_einlesen';
    else if (k === 'f' && !e.shiftKey) aktion = 'suchen';
    else if (k === 'o' && !e.shiftKey) aktion = 'importieren';
    else if (k === 'v' && e.shiftKey) aktion = 'zwischenablage';
    if (!aktion) return;
    e.preventDefault(); e.stopPropagation();
    sende({{art:'taste', aktion: aktion}});
  }}, true);
}})();"#
    )
}

/// Welche GIFs heute welcher Seite gehoeren. „fertig" wird fest zugeteilt und
/// dreht sich jeden Tag um eins weiter; die anderen Anlaesse zieht die Seite selbst.
fn gifs_json(kern: &Kern) -> String {
    fn dateien(anlass: &str) -> Vec<String> {
        let mut liste: Vec<String> = fs::read_dir(orte().gifs.join(anlass))
            .map(|e| {
                e.flatten()
                    .map(|e| e.file_name().to_string_lossy().into_owned())
                    .filter(|n| !n.starts_with('.'))
                    .collect()
            })
            .unwrap_or_default();
        liste.sort();
        liste
    }
    let tag = (chrono::Utc::now().timestamp() / 86_400) as usize;
    let mut ids: Vec<String> = kern.seiten_ids();
    ids.sort();
    let vorrat = dateien("fertig");
    let mut fertig = Map::new();
    if !vorrat.is_empty() {
        for (i, id) in ids.into_iter().enumerate() {
            fertig.insert(id, Value::String(vorrat[(i + tag) % vorrat.len()].clone()));
        }
    }
    json!({
        "fertig": fertig,
        "meilenstein": dateien("meilenstein"),
        "durchhaenger": dateien("durchhaenger"),
    })
    .to_string()
}

/// Strichliste, welches GIF wie oft wirklich auf dem Bildschirm war.
fn gif_gezaehlt(relativ: &str, nutzung: &Mutex<Map<String, Value>>) {
    let Ok(mut liste) = nutzung.lock() else { return };
    let eintrag = liste
        .entry(relativ.to_string())
        .or_insert_with(|| Value::Object(Map::new()));
    if !eintrag.is_object() {
        *eintrag = Value::Object(Map::new());
    }
    let obj = eintrag.as_object_mut().expect("Objekt");
    let n = obj.get("n").and_then(bibliothek::ganzzahl).unwrap_or(0) + 1;
    obj.insert("n".into(), json!(n));
    obj.insert("zuletzt".into(), json!(zeit::heute()));
    let _ = fs::write(&orte().gif_nutzung, orte::json_schoen(&Value::Object(liste.clone())));
}

// MARK: - Dateien

fn datei(relativ: &str, basis: &Path) -> Antwort {
    // Pfad-Ausbruch verhindern: nur einfache Namen, kein "..", keine Laufwerke.
    if relativ.contains("..") {
        return fehler(403, "Verboten");
    }
    let rel = PathBuf::from(relativ.replace('\\', "/"));
    if relativ.is_empty() || rel.components().any(|c| !matches!(c, Component::Normal(_))) {
        return fehler(403, "Verboten");
    }
    let ziel = basis.join(&rel);
    if !ziel.starts_with(basis) {
        return fehler(403, "Verboten");
    }
    match fs::read(&ziel) {
        Ok(inhalt) if ziel.is_file() => ok(inhalt, &bibliothek::endung(&ziel)),
        _ => fehler(404, "Nicht gefunden"),
    }
}

pub fn typ_fuer(endung: &str) -> &'static str {
    match endung.to_ascii_lowercase().as_str() {
        "html" | "htm" => "text/html; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "js" => "text/javascript; charset=utf-8",
        "json" => "application/json; charset=utf-8",
        "svg" => "image/svg+xml",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "pdf" => "application/pdf",
        "woff2" => "font/woff2",
        _ => "application/octet-stream",
    }
}

fn ok(koerper: Vec<u8>, endung: &str) -> Antwort {
    let typ = typ_fuer(endung).to_string();
    let schutz = typ.starts_with("text/html").then_some(SCHUTZ);
    Antwort { code: 200, typ, koerper, schutz }
}

fn html(text: String) -> Antwort {
    ok(text.into_bytes(), "html")
}

fn fehler(code: u16, text: &str) -> Antwort {
    Antwort {
        code,
        typ: "text/html; charset=utf-8".into(),
        koerper: format!("<!DOCTYPE html><meta charset=utf-8><p>{text}").into_bytes(),
        schutz: Some(SCHUTZ),
    }
}

// Damit die Startseite den aktuellen Stand kennt.
impl Kern {
    pub fn startseite_html(&self) -> String {
        let faecher = self.faecher.lock().map(|f| f.clone()).unwrap_or_default();
        let zustand = self.zustand.lock().map(|z| z.clone()).unwrap_or_default();
        startseite::bauen(
            &faecher,
            &fortschritt::alle_staende(),
            Tagesplan::laden().as_ref(),
            &zustand,
        )
    }
}
