//! Lernkiste fuer Windows: ein Fenster mit Seitenleiste und Lernseite, dahinter
//! ein kleiner Server auf 127.0.0.1, der Seiten, Startseite und Motor ausliefert.
//! Gleiches Verhalten wie die Mac-App, gleiche Dateien im Dokumente-Ordner.

// Im fertigen Programm kein schwarzes Konsolenfenster.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod aktualisierung;
mod bibliothek;
mod fortschritt;
mod import;
mod kern;
mod orte;
mod server;
mod startseite;
mod zeit;

use kern::Kern;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::webview::{NewWindowResponse, PageLoadEvent};
use tauri::{
    AppHandle, DragDropEvent, Emitter, Manager, State, Theme, Url, WebviewUrl, WebviewWindow,
    WebviewWindowBuilder, WindowEvent,
};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_opener::OpenerExt;

type KernZ<'a> = State<'a, Arc<Kern>>;

fn main() {
    let kern = Arc::new(Kern::neu());

    tauri::Builder::default()
        // Muss als erstes Plugin kommen: ein zweiter Start gibt nur seine
        // Dateien an das laufende Programm weiter und beendet sich dann.
        .plugin(tauri_plugin_single_instance::init(|app, argv, _cwd| {
            fenster_nach_vorn(app);
            let pfade = html_aus_argumenten(argv.iter().skip(1).cloned());
            if !pfade.is_empty() {
                dateien_annehmen(app, pfade);
            }
        }))
        .plugin(
            tauri_plugin_log::Builder::new()
                .clear_targets()
                .target(tauri_plugin_log::Target::new(tauri_plugin_log::TargetKind::LogDir {
                    file_name: Some("Lernkiste".into()),
                }))
                .target(tauri_plugin_log::Target::new(tauri_plugin_log::TargetKind::Stdout))
                .level(log::LevelFilter::Info)
                .max_file_size(2_000_000)
                .rotation_strategy(tauri_plugin_log::RotationStrategy::KeepOne)
                .build(),
        )
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(kern.clone())
        .menu(menue_bauen)
        .on_menu_event(|app, ereignis| menue_ausfuehren(app, ereignis.id().as_ref()))
        .invoke_handler(tauri::generate_handler![
            bibliothek,
            neu_einlesen,
            seite_besucht,
            sichern,
            thema_setzen,
            favorit_umschalten,
            extern_oeffnen,
            menue_aktion,
            ort_antwort,
            gesichert,
            beenden,
            update_installieren,
            bereit,
            protokoll,
        ])
        .setup(move |app| {
            log::info!("Lernkiste {} startet (Stand {})", app.package_info().version, orte::stand());
            orte::vorbereiten();
            orte::beispiel_einlegen();
            kern.neu_einlesen();

            // Beim ersten Start per Doppelklick auf eine .html-Datei.
            let pfade = html_aus_argumenten(std::env::args().skip(1));
            if let Ok(mut w) = kern.wartende_dateien.lock() {
                w.extend(pfade);
            }

            if let Err(fehler) = server::starten(kern.clone()) {
                log::error!("Server startet nicht: {fehler}");
                start_fehlgeschlagen(app.handle(), kern.port, &fehler);
                return Ok(());
            }
            let fenster = fenster_bauen(app.handle(), &kern)?;
            aktualisierung::regelmaessig(app.handle());
            #[cfg(debug_assertions)]
            selbsttest(fenster);
            #[cfg(not(debug_assertions))]
            let _ = fenster;
            Ok(())
        })
        .on_window_event(|fenster, ereignis| match ereignis {
            WindowEvent::CloseRequested { api, .. } => {
                let app = fenster.app_handle();
                let kern = app.state::<Arc<Kern>>();
                if !kern.darf_schliessen.load(Ordering::SeqCst) {
                    api.prevent_close();
                    schliessen_einleiten(app);
                }
            }
            WindowEvent::DragDrop(DragDropEvent::Drop { paths, .. }) => {
                let pfade: Vec<PathBuf> = paths
                    .iter()
                    .filter(|p| {
                        p.is_dir() || matches!(bibliothek::endung(p).as_str(), "html" | "htm" | "zip")
                    })
                    .cloned()
                    .collect();
                if !pfade.is_empty() {
                    import::dateien(fenster.app_handle(), pfade);
                }
            }
            _ => {}
        })
        .run(tauri::generate_context!())
        .expect("Lernkiste konnte nicht starten");
}

// MARK: - Fenster

fn fenster_bauen(app: &AppHandle, kern: &Kern) -> tauri::Result<WebviewWindow> {
    let port = kern.port;
    let dunkel = kern.theme() == "dark";
    let adresse: Url = format!("{}/app/", kern.basis()).parse().expect("feste Adresse");
    let app_nav = app.clone();
    let app_neu = app.clone();

    WebviewWindowBuilder::new(app, "haupt", WebviewUrl::External(adresse))
        .title("Lernkiste")
        .inner_size(1180.0, 780.0)
        .min_inner_size(820.0, 520.0)
        .center()
        .theme(Some(if dunkel { Theme::Dark } else { Theme::Light }))
        .background_color(if dunkel {
            tauri::window::Color(0x0f, 0x10, 0x11, 0xff)
        } else {
            tauri::window::Color(0xf7, 0xf7, 0xfb, 0xff)
        })
        .on_navigation(move |url| navigation_erlaubt(&app_nav, port, url))
        .on_new_window(move |url, _| {
            // Kein zweites Fenster: externe Adressen gehen nach Rueckfrage in
            // den Browser, alles andere bleibt zu.
            if matches!(url.scheme(), "http" | "https" | "mailto") && !eigene_adresse(&url, port) {
                extern_fragen(&app_neu, url.to_string());
            }
            NewWindowResponse::Deny
        })
        .on_download(|_, _| false)
        .on_page_load(|fenster, nutzlast| {
            if nutzlast.event() == PageLoadEvent::Finished {
                log::debug!("geladen: {}", nutzlast.url());
                let _ = fenster;
            }
        })
        .build()
}

fn eigene_adresse(url: &Url, port: u16) -> bool {
    url.scheme() == "http"
        && matches!(url.host_str(), Some("127.0.0.1") | Some("localhost"))
        && url.port() == Some(port)
}

/// Das Hauptfenster bleibt auf dem eigenen Server. Eine hineingezogene
/// .html-Datei (file:) wird importiert, externe Links gehen nach Rueckfrage
/// in den Browser.
fn navigation_erlaubt(app: &AppHandle, port: u16, url: &Url) -> bool {
    if eigene_adresse(url, port) {
        return true;
    }
    match url.scheme() {
        "about" | "data" | "blob" | "tauri" | "ipc" => true,
        "http" | "https" if matches!(url.host_str(), Some("ipc.localhost") | Some("tauri.localhost")) => true,
        "file" => {
            if let Ok(pfad) = url.to_file_path() {
                if matches!(bibliothek::endung(&pfad).as_str(), "html" | "htm") {
                    import::dateien(app, vec![pfad]);
                }
            }
            false
        }
        "http" | "https" | "mailto" => {
            extern_fragen(app, url.to_string());
            false
        }
        _ => false,
    }
}

fn fenster_nach_vorn(app: &AppHandle) {
    if let Some(f) = app.get_webview_window("haupt") {
        let _ = f.unminimize();
        let _ = f.show();
        let _ = f.set_focus();
    }
}

/// Der Port ist belegt (oder der Server scheitert anders): klar sagen, was los
/// ist, und dann beenden. Die Frage laeuft in einem eigenen Faden, damit die
/// Ereignisschleife weiterlaufen kann.
fn start_fehlgeschlagen(app: &AppHandle, port: u16, fehler: &str) {
    let app = app.clone();
    let text = format!(
        "Die Lernkiste braucht den Anschluss {port} auf diesem Rechner, aber ein anderes \
         Programm benutzt ihn gerade.\n\nStarte den Rechner neu und öffne die Lernkiste \
         danach noch einmal.\n\n({fehler})"
    );
    std::thread::spawn(move || {
        app.dialog()
            .message(text)
            .title("Die Lernkiste kann nicht starten")
            .kind(MessageDialogKind::Error)
            .buttons(MessageDialogButtons::OkCustom("Beenden".into()))
            .blocking_show();
        app.exit(1);
    });
}

fn schliessen_einleiten(app: &AppHandle) {
    let _ = app.emit_to("haupt", "schliessen", ());
    // Rueckfall, falls die Oberflaeche nicht antwortet.
    let app = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(2));
        app.state::<Arc<Kern>>().darf_schliessen.store(true, Ordering::SeqCst);
        app.exit(0);
    });
}

// MARK: - Dateien von aussen

fn html_aus_argumenten(argumente: impl Iterator<Item = String>) -> Vec<PathBuf> {
    argumente
        .map(PathBuf::from)
        .filter(|p| p.is_file() && matches!(bibliothek::endung(p).as_str(), "html" | "htm"))
        .collect()
}

/// Solange die Oberflaeche noch nicht bereit ist, warten die Dateien.
fn dateien_annehmen(app: &AppHandle, pfade: Vec<PathBuf>) {
    let kern = app.state::<Arc<Kern>>();
    if kern.bereit.load(Ordering::SeqCst) {
        import::dateien(app, pfade);
    } else if let Ok(mut w) = kern.wartende_dateien.lock() {
        w.extend(pfade);
    }
}

// MARK: - Menue

fn menue_bauen(app: &AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
    let eintrag = |id: &str, text: &str, kuerzel: Option<&str>| {
        MenuItem::with_id(app, id, text, true, kuerzel)
    };
    let datei = Submenu::with_items(
        app,
        "Datei",
        true,
        &[
            &eintrag("neu_einlesen", "Seiten neu einlesen", Some("CmdOrCtrl+R"))?,
            &eintrag("ordner_oeffnen", "Ordner mit den Lernseiten öffnen", None)?,
            &PredefinedMenuItem::separator(app)?,
            &eintrag("importieren", "Seite importieren …", Some("CmdOrCtrl+O"))?,
            &eintrag("zwischenablage", "Seite aus Zwischenablage einfügen", Some("CmdOrCtrl+Shift+V"))?,
            &eintrag("bauanleitung", "Bauanleitung für eine KI kopieren", None)?,
            &PredefinedMenuItem::separator(app)?,
            &eintrag("beenden", "Beenden", None)?,
        ],
    )?;

    let suchen = eintrag("suchen", "Seite suchen", Some("CmdOrCtrl+F"))?;
    // Unter Windows stoeren vorgefertigte Kopieren/Einsetzen-Eintraege die
    // Zwischenablage im WebView — dort reicht die Suche.
    #[cfg(target_os = "macos")]
    let bearbeiten = Submenu::with_items(
        app,
        "Bearbeiten",
        true,
        &[
            &PredefinedMenuItem::undo(app, None)?,
            &PredefinedMenuItem::redo(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::cut(app, None)?,
            &PredefinedMenuItem::copy(app, None)?,
            &PredefinedMenuItem::paste(app, None)?,
            &PredefinedMenuItem::select_all(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &suchen,
        ],
    )?;
    #[cfg(not(target_os = "macos"))]
    let bearbeiten = Submenu::with_items(app, "Bearbeiten", true, &[&suchen])?;

    let hilfe = Submenu::with_items(
        app,
        "Hilfe",
        true,
        &[
            &eintrag("updates", "Nach Updates suchen …", None)?,
            &PredefinedMenuItem::separator(app)?,
            &eintrag("ueber", "Über Lernkiste", None)?,
        ],
    )?;

    #[cfg(target_os = "macos")]
    {
        let programm = Submenu::with_items(
            app,
            "Lernkiste",
            true,
            &[&PredefinedMenuItem::hide(app, None)?, &PredefinedMenuItem::quit(app, None)?],
        )?;
        return Menu::with_items(app, &[&programm, &datei, &bearbeiten, &hilfe]);
    }
    #[cfg(not(target_os = "macos"))]
    Menu::with_items(app, &[&datei, &bearbeiten, &hilfe])
}

/// Menuepunkt und Tastenkuerzel (aus der Seite gemeldet) koennen beide
/// ausloesen — innerhalb von 400 ms zaehlt nur das erste.
fn menue_ausfuehren(app: &AppHandle, name: &str) {
    let kern = app.state::<Arc<Kern>>();
    if let Ok(mut zuletzt) = kern.menue_zuletzt.lock() {
        let jetzt = Instant::now();
        if let Some(vorher) = zuletzt.get(name) {
            if jetzt.duration_since(*vorher) < Duration::from_millis(400) {
                return;
            }
        }
        zuletzt.insert(name.to_string(), jetzt);
    }
    match name {
        "neu_einlesen" => {
            kern.neu_einlesen();
            let _ = app.emit_to("haupt", "neu_laden", json!({ "oeffnen": null }));
        }
        "ordner_oeffnen" => {
            orte::vorbereiten();
            let _ = app
                .opener()
                .open_path(orte::orte().seiten.to_string_lossy(), None::<&str>);
        }
        "importieren" => import::dateien_waehlen(app),
        "zwischenablage" => import::aus_zwischenablage(app),
        "bauanleitung" => import::bauanleitung_kopieren(app),
        "beenden" => schliessen_einleiten(app),
        "suchen" => {
            fenster_nach_vorn(app);
            let _ = app.emit_to("haupt", "suche_fokus", ());
        }
        "updates" => {
            let hat_update = kern.update.lock().map(|u| u.is_some()).unwrap_or(false);
            if hat_update {
                aktualisierung::installieren(app);
            } else {
                aktualisierung::aus_dem_menue(app);
            }
        }
        "ueber" => {
            let app = app.clone();
            std::thread::spawn(move || {
                let text = format!(
                    "Lernkiste für Windows\nFassung {} (Stand {})\n\nDeine Lernseiten liegen in\n{}",
                    app.package_info().version,
                    orte::stand(),
                    orte::orte().seiten.display()
                );
                app.dialog()
                    .message(text)
                    .title("Über Lernkiste")
                    .kind(MessageDialogKind::Info)
                    .buttons(MessageDialogButtons::OkCustom("OK".into()))
                    .blocking_show();
            });
        }
        _ => {}
    }
}

// MARK: - Externe Links

fn extern_fragen(app: &AppHandle, adresse: String) {
    let Ok(url) = Url::parse(&adresse) else { return };
    if !matches!(url.scheme(), "http" | "https" | "mailto") {
        return;
    }
    let ziel = if url.scheme() == "mailto" {
        url.path().to_string()
    } else {
        url.host_str().unwrap_or("").to_string()
    };
    let app = app.clone();
    std::thread::spawn(move || {
        let ja = app
            .dialog()
            .message(format!("Der Link führt aus der Lernkiste hinaus zu:\n\n{ziel}"))
            .title("Seite im Browser öffnen?")
            .kind(MessageDialogKind::Info)
            .buttons(MessageDialogButtons::OkCancelCustom(
                "Im Browser öffnen".into(),
                "Abbrechen".into(),
            ))
            .blocking_show();
        if ja {
            let _ = app.opener().open_url(url.as_str(), None::<&str>);
        }
    });
}

// MARK: - Befehle fuer die Oberflaeche

fn bibliothek_wert(app: &AppHandle, kern: &Kern) -> Value {
    let faecher = kern.faecher.lock().map(|f| f.clone()).unwrap_or_default();
    let erledigt: Vec<String> = fortschritt::alle_staende()
        .into_values()
        .filter(|s| s.tagespensum.as_ref().map(|t| t.erledigt()).unwrap_or(false))
        .map(|s| s.seite)
        .collect();
    let zustand = kern.zustand.lock().map(|z| z.clone()).unwrap_or_default();
    json!({
        "faecher": faecher,
        "erledigt": erledigt,
        "favoriten": zustand.favoriten,
        "zuletzt": zustand.zuletzt,
        "letzteSeite": zustand.letzte_seite,
        "theme": kern.theme(),
        "stand": orte::stand(),
        "version": app.package_info().version.to_string(),
    })
}

#[tauri::command]
fn bibliothek(app: AppHandle, kern: KernZ) -> Value {
    bibliothek_wert(&app, &kern)
}

#[tauri::command]
fn neu_einlesen(app: AppHandle, kern: KernZ) -> Value {
    kern.neu_einlesen();
    bibliothek_wert(&app, &kern)
}

#[tauri::command]
fn seite_besucht(kern: KernZ, id: String) {
    if kern.seite(&id).is_none() {
        return;
    }
    if let Ok(mut z) = kern.zustand.lock() {
        z.besucht(&id);
    }
}

/// Die Oberflaeche liefert alle "lern:"-Eintraege aus dem localStorage;
/// Rueckgabe: ist das Tagespensum dieser Seite erledigt?
#[tauri::command]
fn sichern(kern: KernZ, id: String, roh: HashMap<String, String>) -> bool {
    let Some(seite) = kern.seite(&id) else { return false };
    let stand = fortschritt::auswerten(&roh, &seite);
    fortschritt::sichern(&stand);
    stand.tagespensum.as_ref().map(|t| t.erledigt()).unwrap_or(false)
}

#[tauri::command]
fn thema_setzen(app: AppHandle, kern: KernZ, theme: String) -> String {
    let theme = if theme == "light" { "light" } else { "dark" };
    if let Ok(mut z) = kern.zustand.lock() {
        z.theme = theme.into();
        z.sichern();
    }
    if let Some(f) = app.get_webview_window("haupt") {
        let _ = f.set_theme(Some(if theme == "light" { Theme::Light } else { Theme::Dark }));
    }
    theme.into()
}

#[tauri::command]
fn favorit_umschalten(kern: KernZ, id: String) -> Vec<String> {
    if kern.seite(&id).is_none() {
        return kern.zustand.lock().map(|z| z.favoriten.clone()).unwrap_or_default();
    }
    kern.zustand
        .lock()
        .map(|mut z| {
            z.favorit_umschalten(&id);
            z.favoriten.clone()
        })
        .unwrap_or_default()
}

#[tauri::command]
fn extern_oeffnen(app: AppHandle, url: String) {
    extern_fragen(&app, url);
}

#[tauri::command]
fn menue_aktion(app: AppHandle, name: String) {
    menue_ausfuehren(&app, &name);
}

#[tauri::command]
fn ort_antwort(kern: KernZ, fach: Option<String>, thema: Option<String>) {
    let antwort = match (fach, thema) {
        (Some(f), Some(t)) => Some((f, t)),
        _ => None,
    };
    if let Some(tx) = kern.ort_kanal.lock().ok().and_then(|mut k| k.take()) {
        let _ = tx.send(antwort);
    }
}

#[tauri::command]
fn gesichert(kern: KernZ) {
    if let Some(tx) = kern.gesichert_kanal.lock().ok().and_then(|mut k| k.take()) {
        let _ = tx.send(());
    }
}

#[tauri::command]
fn beenden(app: AppHandle, kern: KernZ) {
    kern.darf_schliessen.store(true, Ordering::SeqCst);
    app.exit(0);
}

#[tauri::command]
fn update_installieren(app: AppHandle) {
    aktualisierung::installieren(&app);
}

/// Die Oberflaeche ist geladen: aktuellen Update-Knopf liefern und Dateien
/// importieren, die schon vor dem Start geoeffnet werden sollten.
#[tauri::command]
fn bereit(app: AppHandle, kern: KernZ) -> Value {
    log::info!("Oberfläche bereit");
    kern.bereit.store(true, Ordering::SeqCst);
    let wartend: Vec<PathBuf> = kern
        .wartende_dateien
        .lock()
        .map(|mut w| std::mem::take(&mut *w))
        .unwrap_or_default();
    if !wartend.is_empty() {
        import::dateien(&app, wartend);
    }
    match kern.update_knopf.lock().ok().and_then(|k| k.clone()) {
        Some((text, klickbar)) => json!({ "text": text, "klickbar": klickbar }),
        None => json!({ "text": null, "klickbar": false }),
    }
}

/// Fehler aus der Oberflaeche landen im Log — das hilft bei Fehlermeldungen.
#[tauri::command]
fn protokoll(text: String) {
    let kurz: String = text.chars().take(2000).collect();
    log::warn!("Oberfläche: {kurz}");
}

/// Nur im Testbau: LERNKISTE_SELBSTTEST=<datei.js> spielt ein Skript in der
/// Oberflaeche ab (Klicks nachstellen, Ergebnisse per protokoll ins Log).
/// Schritte sind durch Zeilen "//---" getrennt und laufen im Abstand von
/// zweieinhalb Sekunden — so haengt der Test nicht an Zeitgebern der Seite.
#[cfg(debug_assertions)]
fn selbsttest(fenster: WebviewWindow) {
    let Ok(datei) = std::env::var("LERNKISTE_SELBSTTEST") else { return };
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_secs(3));
        let js = match std::fs::read_to_string(&datei) {
            Ok(js) => js,
            Err(e) => return log::warn!("Selbsttest nicht lesbar: {e}"),
        };
        log::info!("Selbsttest startet: {datei}");
        for schritt in js.split("\n//---") {
            let _ = fenster.eval(schritt);
            std::thread::sleep(std::time::Duration::from_millis(2500));
        }
    });
}
