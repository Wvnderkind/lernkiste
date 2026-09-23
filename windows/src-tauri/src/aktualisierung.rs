//! Neue Fassungen von GitHub holen: still beim Start und alle sechs Stunden
//! nachsehen, dann den Knopf „Update verfuegbar" zeigen. Ein Klick fragt nach,
//! sichert den Fortschritt, laedt, tauscht aus und startet neu.

use crate::import::melden;
use crate::kern::Kern;
use serde_json::json;
use std::sync::atomic::Ordering;
use std::sync::{mpsc, Arc};
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager, Url};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_updater::{Update, UpdaterExt};

const QUELLE: &str = "https://github.com/Wvnderkind/lernkiste/releases/latest/download/latest.json";
const ALLE_SECHS_STUNDEN: Duration = Duration::from_secs(6 * 60 * 60);
const KNOPF_TEXT: &str = "Update verfügbar";

fn kern(app: &AppHandle) -> Arc<Kern> {
    app.state::<Arc<Kern>>().inner().clone()
}

/// Zum Testen laesst sich die Quelle umlenken (LERNKISTE_UPDATE_QUELLE=…).
fn quelle() -> String {
    std::env::var("LERNKISTE_UPDATE_QUELLE").unwrap_or_else(|_| QUELLE.to_string())
}

/// Still beim Start (kurz verzoegert) und danach alle sechs Stunden.
pub fn regelmaessig(app: &AppHandle) {
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        tokio_schlafen(Duration::from_secs(8)).await;
        loop {
            pruefen(&app, true).await;
            tokio_schlafen(ALLE_SECHS_STUNDEN).await;
        }
    });
}

async fn tokio_schlafen(dauer: Duration) {
    // Ohne eigene tokio-Abhaengigkeit: ein Faden schlaeft, die Aufgabe wartet.
    let (tx, rx) = tauri::async_runtime::channel::<()>(1);
    std::thread::spawn(move || {
        std::thread::sleep(dauer);
        let _ = tx.blocking_send(());
    });
    let mut rx = rx;
    let _ = rx.recv().await;
}

/// Aus dem Menue: nicht still — jede Antwort bekommt eine Meldung, und ein
/// gefundenes Update fuehrt direkt zur Frage.
pub fn aus_dem_menue(app: &AppHandle) {
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        pruefen(&app, false).await;
    });
}

async fn pruefen(app: &AppHandle, still: bool) {
    let kern = kern(app);
    if kern.update_laeuft.load(Ordering::SeqCst) {
        return;
    }
    let ergebnis = async {
        let url = Url::parse(&quelle()).map_err(|e| e.to_string())?;
        let pruefer = app
            .updater_builder()
            .endpoints(vec![url])
            .map_err(|e| e.to_string())?
            .timeout(Duration::from_secs(30))
            .on_before_exit(|| log::info!("Update: Installer startet, die Lernkiste beendet sich"))
            .build()
            .map_err(|e| e.to_string())?;
        pruefer.check().await.map_err(|e| e.to_string())
    }
    .await;

    match ergebnis {
        Ok(Some(update)) => {
            log::info!("Update gefunden: {} (laufend {})", update.version, update.current_version);
            if let Ok(mut u) = kern.update.lock() {
                *u = Some(update);
            }
            knopf_setzen(app, Some((KNOPF_TEXT.into(), true)));
            if !still {
                installieren(app);
            }
        }
        Ok(None) => {
            log::info!("Update: keine neue Fassung");
            if let Ok(mut u) = kern.update.lock() {
                *u = None;
            }
            knopf_setzen(app, None);
            if !still {
                hinweis(app, "Die Lernkiste ist aktuell", "Du hast bereits die neueste Fassung.");
            }
        }
        Err(fehler) => {
            log::warn!("Update-Pruefung fehlgeschlagen: {fehler}");
            if !still {
                hinweis(
                    app,
                    "Keine Verbindung zu GitHub",
                    "Ob es eine neue Fassung gibt, lässt sich gerade nicht nachsehen. \
                     Später noch einmal versuchen.",
                );
            }
        }
    }
}

fn hinweis(app: &AppHandle, titel: &str, text: &str) {
    let app = app.clone();
    let (titel, text) = (titel.to_string(), text.to_string());
    std::thread::spawn(move || {
        app.dialog()
            .message(text)
            .title(titel)
            .kind(MessageDialogKind::Info)
            .buttons(MessageDialogButtons::OkCustom("OK".into()))
            .blocking_show();
    });
}

/// Merkt sich den Zustand des Knopfs und schickt ihn an die Oberflaeche.
pub fn knopf_setzen(app: &AppHandle, zustand: Option<(String, bool)>) {
    if let Ok(mut k) = kern(app).update_knopf.lock() {
        *k = zustand.clone();
    }
    let wert = match zustand {
        Some((text, klickbar)) => json!({ "text": text, "klickbar": klickbar }),
        None => json!({ "text": null, "klickbar": false }),
    };
    let _ = app.emit_to("haupt", "update", wert);
}

/// Klick auf den Knopf (oder Menue mit gefundenem Update): fragen, sichern,
/// laden, austauschen, neu starten. Alles in einem eigenen Faden.
pub fn installieren(app: &AppHandle) {
    let kern = kern(app);
    let Some(update) = kern.update.lock().ok().and_then(|u| u.clone()) else { return };
    if kern.update_laeuft.swap(true, Ordering::SeqCst) {
        return;
    }
    let app = app.clone();
    std::thread::spawn(move || {
        let ja = app
            .dialog()
            .message(
                "Die Lernkiste lädt die neue Fassung herunter, tauscht sich aus und startet neu. \
                 Das dauert meist unter einer Minute.\n\n\
                 Deine Lernseiten und dein Fortschritt bleiben, wie sie sind.",
            )
            .title("Neue Fassung installieren?")
            .kind(MessageDialogKind::Info)
            .buttons(MessageDialogButtons::OkCancelCustom(
                "Jetzt aktualisieren".into(),
                "Später".into(),
            ))
            .blocking_show();
        if !ja {
            kern.update_laeuft.store(false, Ordering::SeqCst);
            return;
        }
        fortschritt_sichern(&app, &kern);
        knopf_setzen(&app, Some(("Lädt … 0 %".into(), false)));
        let ergebnis = tauri::async_runtime::block_on(laden_und_installieren(&app, &update));
        match ergebnis {
            Ok(()) => {
                // Unter Windows beendet sich die App schon im Installer-Start
                // (der Installer startet sie danach selbst). Sonst hier neu starten.
                log::info!("Update installiert, Neustart");
                kern.darf_schliessen.store(true, Ordering::SeqCst);
                app.restart();
            }
            Err(fehler) => {
                log::error!("Update fehlgeschlagen: {fehler}");
                kern.update_laeuft.store(false, Ordering::SeqCst);
                knopf_setzen(&app, Some((KNOPF_TEXT.into(), true)));
                melden(
                    &app,
                    "Update hat nicht geklappt",
                    &format!(
                        "{fehler}\n\nDie bisherige Fassung läuft unverändert weiter. \
                         Du kannst es später noch einmal versuchen."
                    ),
                );
            }
        }
    });
}

async fn laden_und_installieren(app: &AppHandle, update: &Update) -> Result<(), String> {
    let mut geladen: u64 = 0;
    let mut zuletzt: i64 = -1;
    let app_fortschritt = app.clone();
    let app_fertig = app.clone();
    update
        .download_and_install(
            move |stueck, gesamt| {
                geladen += stueck as u64;
                if let Some(gesamt) = gesamt.filter(|g| *g > 0) {
                    let prozent = ((geladen * 100) / gesamt).min(100) as i64;
                    if prozent != zuletzt {
                        zuletzt = prozent;
                        knopf_setzen(&app_fortschritt, Some((format!("Lädt … {prozent} %"), false)));
                    }
                }
            },
            move || knopf_setzen(&app_fertig, Some(("Startet neu …".into(), false))),
        )
        .await
        .map_err(|e| e.to_string())
}

/// Bittet die Oberflaeche, den Lernstand der offenen Seite abzulegen, und
/// wartet hoechstens drei Sekunden darauf.
pub fn fortschritt_sichern(app: &AppHandle, kern: &Kern) {
    let (tx, rx) = mpsc::channel();
    if let Ok(mut k) = kern.gesichert_kanal.lock() {
        *k = Some(tx);
    }
    if app.emit_to("haupt", "sichern_bitte", ()).is_ok() {
        let _ = rx.recv_timeout(Duration::from_secs(3));
    }
    if let Ok(mut k) = kern.gesichert_kanal.lock() {
        *k = None;
    }
}
