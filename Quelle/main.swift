import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var fenster: Fenster?

    func applicationDidFinishLaunching(_ note: Notification) {
        // Eine zweite Lernkiste koennte den Port nicht bekommen und bliebe ein
        // leeres Fenster. Also gar nicht erst starten, sondern erklaeren warum.
        if Server.laeuftSchon() {
            let hinweis = NSAlert()
            hinweis.messageText = "Lernkiste läuft bereits"
            hinweis.informativeText =
                "Es ist schon ein Lernkiste-Fenster offen — wechsle einfach dorthin.\n\n"
                + "Zwei Fenster gleichzeitig gehen nicht: beide bräuchten denselben "
                + "internen Zugang, und das zweite bliebe leer."
            hinweis.addButton(withTitle: "Verstanden")
            hinweis.runModal()
            NSApp.terminate(nil)
            return
        }

        menueBauen()
        let f = Fenster()
        f.showWindow(nil)
        f.window?.center()
        f.window?.makeKeyAndOrderFront(nil)
        fenster = f
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows sichtbar: Bool) -> Bool {
        if !sichtbar { fenster?.showWindow(nil) }
        return true
    }

    @objc func neuLaden() { fenster?.bibliothekNeuLaden() }

    @objc func sucheFokussieren() { fenster?.sucheFokussieren() }

    @objc func seitenOrdnerOeffnen() {
        NSWorkspace.shared.open(Orte.seiten)
    }

    @objc func seiteImportieren() { Import.dateienWaehlen(fenster) }

    @objc func ausZwischenablage() { Import.ausZwischenablage(fenster) }

    @objc func bauanleitungKopieren() { Import.bauanleitungKopieren() }

    /// HTML-Datei aufs Dock-Symbol gezogen oder mit „Öffnen mit“ gewaehlt.
    func application(_ app: NSApplication, open urls: [URL]) {
        Import.dateien(urls, fenster)
    }

    private func menueBauen() {
        let haupt = NSMenu()

        // App-Menü
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Über Lernkiste",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Lernkiste ausblenden",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Lernkiste beenden",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        haupt.addItem(appItem)

        // Ablage
        let dateiItem = NSMenuItem()
        let dateiMenu = NSMenu(title: "Ablage")
        let laden = NSMenuItem(title: "Seiten neu einlesen",
                               action: #selector(neuLaden), keyEquivalent: "r")
        laden.target = self
        dateiMenu.addItem(laden)
        let ordner = NSMenuItem(title: "Ordner mit den Lernseiten öffnen",
                                action: #selector(seitenOrdnerOeffnen), keyEquivalent: "")
        ordner.target = self
        dateiMenu.addItem(ordner)
        dateiMenu.addItem(.separator())
        for (titel, aktion, taste) in [
            ("Seite importieren …", #selector(seiteImportieren), "o"),
            ("Seite aus Zwischenablage einfügen", #selector(ausZwischenablage), "V"),
            ("Bauanleitung für eine KI kopieren", #selector(bauanleitungKopieren), ""),
        ] as [(String, Selector, String)] {
            let eintrag = NSMenuItem(title: titel, action: aktion, keyEquivalent: taste)
            eintrag.target = self
            dateiMenu.addItem(eintrag)
        }
        dateiMenu.addItem(.separator())
        dateiMenu.addItem(withTitle: "Fenster schließen",
                          action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        dateiItem.submenu = dateiMenu
        haupt.addItem(dateiItem)

        // Bearbeiten (damit Kopieren/Einfügen/Suchen in der Seite funktionieren)
        let bearbItem = NSMenuItem()
        let bearbMenu = NSMenu(title: "Bearbeiten")
        bearbMenu.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        bearbMenu.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "Z")
        bearbMenu.addItem(.separator())
        bearbMenu.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        bearbMenu.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        bearbMenu.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        bearbMenu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        bearbMenu.addItem(.separator())
        let suchen = NSMenuItem(title: "Seite suchen", action: #selector(sucheFokussieren), keyEquivalent: "f")
        suchen.target = self
        bearbMenu.addItem(suchen)
        bearbItem.submenu = bearbMenu
        haupt.addItem(bearbItem)

        // Fenster
        let fensterItem = NSMenuItem()
        let fensterMenu = NSMenu(title: "Fenster")
        fensterMenu.addItem(withTitle: "Im Dock ablegen",
                            action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let vollbild = fensterMenu.addItem(withTitle: "Vollbild",
                            action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        vollbild.keyEquivalentModifierMask = [.control, .command]   // cmd-F ist die Suche
        fensterItem.submenu = fensterMenu
        haupt.addItem(fensterItem)
        NSApp.windowsMenu = fensterMenu

        NSApp.mainMenu = haupt
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegat = AppDelegate()
app.delegate = delegat
app.run()
