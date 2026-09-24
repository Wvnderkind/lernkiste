fn main() {
    // Motor, Beispielseite und STAND liegen ausserhalb dieses Ordners und
    // werden per include_str! eingebunden — bei jeder Aenderung dort neu bauen.
    for datei in [
        "../../STAND",
        "../../Ressourcen",
        "../../Beispiel",
        "../ui",
    ] {
        println!("cargo:rerun-if-changed={datei}");
    }
    // Die Oberflaeche kommt ueber http://127.0.0.1 — fuer solche Seiten gibt
    // Tauri nur Befehle frei, die in der Capability ausdruecklich stehen.
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(
        tauri_build::AppManifest::new().commands(&[
            "bibliothek",
            "neu_einlesen",
            "seite_besucht",
            "sichern",
            "thema_setzen",
            "favorit_umschalten",
            "extern_oeffnen",
            "menue_aktion",
            "ort_antwort",
            "gesichert",
            "beenden",
            "update_installieren",
            "bereit",
            "protokoll",
            "exportieren",
            "im_explorer_zeigen",
            "neuigkeiten",
            "neuigkeiten_gelesen",
            "anleitung_ausblenden",
            "sichern_mix",
            "melden",
        ]),
    ))
    .expect("tauri-build")
}
