import AppKit
import WebKit

// MARK: - Knoten der Seitenleiste

final class Knoten: NSObject {
    enum Art { case bereich, fach, thema, seite }
    let art: Art
    let name: String
    let seite: Seite?
    var kinder: [Knoten]
    weak var eltern: Knoten?

    init(art: Art, name: String, seite: Seite? = nil, kinder: [Knoten] = []) {
        self.art = art; self.name = name; self.seite = seite; self.kinder = kinder
        super.init()
        kinder.forEach { $0.eltern = self }
    }
    var istGruppe: Bool { art == .bereich }

    /// Fester Name fuer den Klappzustand, z. B. "Aktuell/Chemie/Periodensystem".
    /// Haengt nur an den Namen, nicht am Objekt — die Knoten entstehen bei
    /// jedem Einlesen neu.
    var schluessel: String { (eltern.map { $0.schluessel + "/" } ?? "") + name }
}

/// Die Farben der Seitenleiste — dieselben Werte wie auf den Lernseiten
/// (Ressourcen/tokens.css: --surface im Dunkeln, --surface-2 im Hellen).
enum Farben {
    static let seitenleiste = NSColor(name: "seitenleiste") { erscheinung in
        erscheinung.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.098, green: 0.106, blue: 0.110, alpha: 1)   // #191b1c
            : NSColor(srgbRed: 0.933, green: 0.941, blue: 0.969, alpha: 1)   // #eef0f7
    }

    /// Hintergrund der rechten Haelfte — dieselbe Farbe wie die Lernseiten
    /// (tokens.css, --bg), damit Kopf und Seite ineinander uebergehen.
    static let seite = NSColor(name: "seite") { erscheinung in
        erscheinung.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.059, green: 0.063, blue: 0.067, alpha: 1)   // #0f1011
            : NSColor(srgbRed: 0.969, green: 0.969, blue: 0.984, alpha: 1)   // #f7f7fb
    }

    /// Schriftfarben der Seitenleiste. Bewusst feste Werte statt labelColor:
    /// macOS 26 stellt fuer die ausgewaehlte Sidebar-Zeile ein eigenes
    /// Erscheinungsbild ein, in dem labelColor als Akzentblau herauskommt.
    static let schrift = NSColor(name: "schrift") { erscheinung in
        erscheinung.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.910, green: 0.918, blue: 0.918, alpha: 1)   // #e8eaea
            : NSColor(srgbRed: 0.102, green: 0.102, blue: 0.180, alpha: 1)   // #1a1a2e
    }

    static let schriftLeise = NSColor(name: "schriftLeise") { erscheinung in
        erscheinung.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.580, green: 0.604, blue: 0.612, alpha: 1)   // #949a9c
            : NSColor(srgbRed: 0.353, green: 0.373, blue: 0.478, alpha: 1)   // #5a5f7a
    }

    /// Markierung der offenen Seite: bewusst kein System-Blau, sondern eine
    /// leise Aufhellung bzw. Abdunklung der Seitenleiste.
    static let markierung = NSColor(name: "markierung") { erscheinung in
        erscheinung.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.085)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.075)
    }
}

/// Hintergrund der Seitenleiste. Bewusst kein durchscheinendes System-Material:
/// das faerbt sich nach dem Schreibtischbild und wird dann z. B. blau. Hier gelten
/// dieselben Farben wie auf den Lernseiten (tokens.css, --surface / --surface-2).
final class SeitenleistenHintergrund: NSView {
    override var allowsVibrancy: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        Farben.seitenleiste.setFill()
        dirtyRect.fill()
    }
}

/// Zeile der Seitenleiste. Die Auswahl wird selbst gezeichnet: macOS wuerde sie
/// blau ausfuellen und blass schalten, sobald die Tastatur woanders liegt — und die
/// liegt hier immer bei der Lernseite. Stattdessen eine ruhige graue Pille, die
/// durchgehend zeigt, wo man gerade ist.
final class BetonteZeile: NSTableRowView {
    /// Haelt die Schriftfarbe normal — sonst faerbt AppKit den Text der
    /// ausgewaehlten Zeile um (weiss bzw. akzentblau).
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    /// Die Pille haengt am Hintergrund, nicht an drawSelection: die Liste laeuft
    /// mit selectionHighlightStyle == .none, damit AppKit gar nichts einfaerbt.
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isSelected else { return }
        Farben.markierung.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1),
                     xRadius: 6, yRadius: 6).fill()
    }

    override var isSelected: Bool {
        didSet { needsDisplay = true }
    }

    /// Nie "betont": eine betonte Auswahl faerbt macOS 26 in der Akzentfarbe ein —
    /// Hintergrund wie Schrift. Gezeichnet wird ohnehin oben selbst.
    override var isEmphasized: Bool {
        get { false }
        set { }
    }
}

/// Zelle der Seitenleiste. macOS 26 faerbt den Text einer ausgewaehlten
/// Sidebar-Zeile von sich aus in der Akzentfarbe ein. Hier soll die Schrift
/// aber ruhig bleiben, deshalb wird die gewuenschte Farbe nach jedem
/// Layout-Durchgang wieder durchgesetzt.
final class ZeilenZelle: NSTableCellView {
    var eigeneFarbe: NSColor = Farben.schrift {
        didSet { textField?.textColor = eigeneFarbe }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { textField?.textColor = eigeneFarbe }
    }

    override func layout() {
        super.layout()
        if textField?.textColor != eigeneFarbe { textField?.textColor = eigeneFarbe }
    }
}

/// Flaeche rechts: Kopfzeile und Lernseite auf demselben Grund, sonst setzt sich
/// die Kopfzeile als hellerer Balken ab.
final class SeitenHintergrund: NSView {
    override var allowsVibrancy: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        Farben.seite.setFill()
        dirtyRect.fill()
    }
}

// MARK: - Hauptfenster

final class Fenster: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate,
                     WKNavigationDelegate, WKScriptMessageHandler, NSSearchFieldDelegate,
                     NSMenuDelegate {

    private var faecher: [Fach] = []
    private var staende: [String: SeitenStand] = [:]
    private var plan: Tagesplan?
    private var wurzel: [Knoten] = []
    private var suchtext = ""
    private var aktuelleSeite: Seite?

    /// Was er in der Leiste selbst auf- oder zugeklappt hat (true = offen).
    /// Liegt in den Einstellungen der App und ueberlebt so den Neustart.
    private var klappzustand = UserDefaults.standard
        .dictionary(forKey: "LeisteKlappzustand") as? [String: Bool] ?? [:]
    /// Waehrend die App selbst klappt, sind die Meldungen kein Wunsch von ihm.
    private var klapptSelbst = false

    private let server = Server()
    private var uhr: Timer?

    private var liste: NSOutlineView!
    private var suchfeld: NSSearchField!
    private var web: WKWebView!
    private var titelLabel: NSTextField!
    private var unterLabel: NSTextField!
    private var sternKnopf: NSButton!
    private var updateKnopf: NSButton!
    private var infoKnopf: NSButton!
    private var infoPunkt: NSView!
    private var auffrischUhr: Timer?
    /// Was die Leiste und die Startseite zuletzt gezeigt haben — beim Auffrischen
    /// wird nur neu gezeichnet, wenn sich daran etwas geaendert hat.
    private var leistenAbdruck = ""
    private var gezeigteStartseite: String?
    private var startKnopf: NSButton!
    private var startPille: NSView!
    private var seitenleisteHG: SeitenleistenHintergrund!
    private var trenner: NSBox!
    private var kopfOben: NSLayoutConstraint!

    // MARK: Aufbau

    convenience init() {
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        fenster.title = "Lernkiste"
        fenster.titlebarAppearsTransparent = true
        // Der Fenstertitel wuerde sonst ueber der Seitenleiste stehen — die
        // Kopfzeile rechts sagt ohnehin, wo man gerade ist.
        fenster.titleVisibility = .hidden
        // Der Kopf sitzt jetzt in der Titelleiste — das Fenster muss sich dort
        // trotzdem verschieben lassen.
        fenster.isMovableByWindowBackground = true
        fenster.minSize = NSSize(width: 820, height: 520)
        fenster.setFrameAutosaveName("LernkisteHauptfenster")
        self.init(window: fenster)
        aufbauen()
    }

    private func aufbauen() {
        Orte.vorbereiten()
        Orte.beispielEinlegen()
        try? server.starten()
        server.startseiteHTML = { [weak self] in self?.startseiteBauen() ?? "" }

        neuEinlesen()
        oberflaecheBauen()
        themaAnwenden()

        // Beim Start immer die Startseite — dort steht, was heute dran ist.
        startseiteZeigen()

        // Regelmäßig sichern, damit auch ohne Seitenwechsel nichts verloren geht.
        uhr = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.fortschrittSichern()
        }

        // Von selbst auffrischen: neue Seiten, Gruß, Haken vom Vortag.
        auffrischUhr = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.auffrischen()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(auffrischen),
            name: .NSCalendarDayChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(auffrischen),
            name: NSApplication.didBecomeActiveNotification, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(fensterSchliesst),
            name: NSApplication.willTerminateNotification, object: nil)
    }

    private func oberflaecheBauen() {
        guard let fenster = window else { return }

        // --- Seitenleiste ---
        suchfeld = NSSearchField()
        suchfeld.placeholderString = "Seite suchen"
        suchfeld.delegate = self
        suchfeld.translatesAutoresizingMaskIntoConstraints = false

        liste = NSOutlineView()
        liste.headerView = nil
        liste.rowSizeStyle = .default
        liste.floatsGroupRows = false
        liste.indentationPerLevel = 13
        liste.style = .sourceList
        liste.selectionHighlightStyle = .none   // Markierung zeichnet BetonteZeile selbst
        // Deckende eigene Farbe: der Seitenlisten-Stil legt sonst ein durchscheinendes
        // Material hinter die Liste, das sich nach dem Schreibtischbild faerbt.
        liste.backgroundColor = Farben.seitenleiste
        liste.dataSource = self
        liste.delegate = self
        // Lernseiten lassen sich direkt in die Leiste ziehen.
        liste.registerForDraggedTypes([.fileURL])
        liste.setDraggingSourceOperationMask(.copy, forLocal: false)
        // Rechtsklick: Seite, Thema oder Fach weitergeben.
        let kontext = NSMenu()
        kontext.delegate = self
        liste.menu = kontext
        liste.doubleAction = #selector(zeileGeklickt)
        liste.target = self
        liste.action = #selector(zeileGeklickt)
        let spalte = NSTableColumn(identifier: .init("haupt"))
        spalte.resizingMask = .autoresizingMask
        liste.addTableColumn(spalte)
        liste.outlineTableColumn = spalte

        let rollen = NSScrollView()
        rollen.documentView = liste
        rollen.hasVerticalScroller = true
        rollen.drawsBackground = false
        rollen.translatesAutoresizingMaskIntoConstraints = false

        startKnopf = NSButton(title: "  Startseite", target: self,
                              action: #selector(startseiteZeigen))
        startKnopf.image = NSImage(systemSymbolName: "house", accessibilityDescription: nil)
        startKnopf.imagePosition = .imageLeading
        startKnopf.bezelStyle = .inline
        startKnopf.isBordered = false
        startKnopf.alignment = .left
        startKnopf.translatesAutoresizingMaskIntoConstraints = false

        // Die Markierung liegt in einer eigenen Flaeche, damit das Haus weiter
        // innen sitzen kann als der Rand der grauen Pille.
        startPille = NSView()
        startPille.translatesAutoresizingMaskIntoConstraints = false
        startPille.wantsLayer = true
        startPille.layer?.cornerRadius = 6
        startPille.addSubview(startKnopf)

        let links = NSView()
        links.translatesAutoresizingMaskIntoConstraints = false
        [suchfeld, startPille, rollen].forEach { links.addSubview($0) }
        let wunschbreite = links.widthAnchor.constraint(equalToConstant: 258)
        wunschbreite.priority = .defaultLow
        NSLayoutConstraint.activate([
            wunschbreite,
            suchfeld.topAnchor.constraint(equalTo: links.safeAreaLayoutGuide.topAnchor, constant: 8),
            suchfeld.leadingAnchor.constraint(equalTo: links.leadingAnchor, constant: 10),
            suchfeld.trailingAnchor.constraint(equalTo: links.trailingAnchor, constant: -10),
            startPille.topAnchor.constraint(equalTo: suchfeld.bottomAnchor, constant: 8),
            startPille.leadingAnchor.constraint(equalTo: links.leadingAnchor, constant: 9),
            startPille.trailingAnchor.constraint(equalTo: links.trailingAnchor, constant: -9),
            startPille.heightAnchor.constraint(equalToConstant: 24),
            startKnopf.leadingAnchor.constraint(equalTo: startPille.leadingAnchor, constant: 7),
            startKnopf.trailingAnchor.constraint(equalTo: startPille.trailingAnchor),
            startKnopf.topAnchor.constraint(equalTo: startPille.topAnchor),
            startKnopf.bottomAnchor.constraint(equalTo: startPille.bottomAnchor),
            rollen.topAnchor.constraint(equalTo: startPille.bottomAnchor, constant: 6),
            rollen.leadingAnchor.constraint(equalTo: links.leadingAnchor),
            rollen.trailingAnchor.constraint(equalTo: links.trailingAnchor),
            rollen.bottomAnchor.constraint(equalTo: links.bottomAnchor),
        ])

        // --- Rechte Seite: Kopfzeile + WebView ---
        let konfig = WKWebViewConfiguration()
        konfig.websiteDataStore = .default()
        konfig.userContentController.add(self, name: "lernkiste")
        konfig.userContentController.addUserScript(
            WKUserScript(source: bruecke(), injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))
        konfig.userContentController.addUserScript(
            WKUserScript(source: markierungsStil(), injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))

        web = WKWebView(frame: .zero, configuration: konfig)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.translatesAutoresizingMaskIntoConstraints = false
        web.allowsBackForwardNavigationGestures = false

        titelLabel = NSTextField(labelWithString: "Lernkiste")
        titelLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titelLabel.lineBreakMode = .byTruncatingTail
        unterLabel = NSTextField(labelWithString: "")
        unterLabel.font = .systemFont(ofSize: 11)
        unterLabel.textColor = .secondaryLabelColor

        let texte = NSStackView(views: [titelLabel, unterLabel])
        texte.orientation = .vertical
        texte.alignment = .leading
        texte.spacing = 1

        sternKnopf = NSButton(image: NSImage(systemSymbolName: "star",
                                             accessibilityDescription: "Anpinnen")!,
                              target: self, action: #selector(favoritUmschalten))
        sternKnopf.isBordered = false
        sternKnopf.toolTip = "Seite anpinnen"

        let themaKnopf = NSButton(image: NSImage(systemSymbolName: "circle.lefthalf.filled",
                                                 accessibilityDescription: "Hell/Dunkel")!,
                                  target: self, action: #selector(themaUmschalten))
        themaKnopf.isBordered = false
        themaKnopf.toolTip = "Hell / Dunkel"

        infoKnopf = NSButton(image: NSImage(systemSymbolName: "info.circle",
                                            accessibilityDescription: "Neuigkeiten")!,
                             target: self, action: #selector(neuigkeitenZeigen))
        infoKnopf.isBordered = false
        infoKnopf.toolTip = "Was ist neu?"
        // Kleiner Punkt oben rechts am ⓘ, solange ein Update ungelesen ist.
        infoPunkt = NSView()
        infoPunkt.wantsLayer = true
        infoPunkt.layer?.backgroundColor = NSColor.systemRed.cgColor
        infoPunkt.layer?.cornerRadius = 3.5
        infoPunkt.translatesAutoresizingMaskIntoConstraints = false
        infoKnopf.addSubview(infoPunkt)
        NSLayoutConstraint.activate([
            infoPunkt.widthAnchor.constraint(equalToConstant: 7),
            infoPunkt.heightAnchor.constraint(equalToConstant: 7),
            infoPunkt.topAnchor.constraint(equalTo: infoKnopf.topAnchor, constant: -2),
            infoPunkt.trailingAnchor.constraint(equalTo: infoKnopf.trailingAnchor, constant: 2),
        ])
        infoPunkt.isHidden = !Neuigkeiten.ungelesen

        // Nur sichtbar, wenn die öffentliche Fassung eine neuere auf GitHub findet.
        updateKnopf = NSButton(title: "Update verfügbar", target: Updater.shared,
                               action: #selector(Updater.installierenFragen))
        updateKnopf.bezelStyle = .rounded
        updateKnopf.controlSize = .small
        updateKnopf.bezelColor = .controlAccentColor
        updateKnopf.toolTip = "Neue Fassung der Lernkiste installieren"
        updateKnopf.isHidden = true

        let kopf = NSStackView(views: [texte, NSView(), updateKnopf, sternKnopf, infoKnopf, themaKnopf])
        kopf.orientation = .horizontal
        kopf.spacing = 10
        kopf.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 10, right: 14)
        kopf.translatesAutoresizingMaskIntoConstraints = false

        trenner = NSBox()
        trenner.boxType = .separator
        trenner.translatesAutoresizingMaskIntoConstraints = false
        // Wie in macOS-Apps: erst sichtbar, wenn die Seite darunter wegscrollt.
        trenner.alphaValue = 0

        let rechts = SeitenHintergrund()
        rechts.translatesAutoresizingMaskIntoConstraints = false
        [kopf, trenner, web].forEach { rechts.addSubview($0) }
        // Der Kopf sitzt auf Hoehe der Ampelknoepfe, also am oberen Fensterrand.
        // Im Vollbild kommt der Abstand der sicheren Flaeche (Notch) dazu.
        kopfOben = kopf.topAnchor.constraint(equalTo: rechts.topAnchor, constant: 12)
        NSLayoutConstraint.activate([
            kopfOben,
            kopf.leadingAnchor.constraint(equalTo: rechts.leadingAnchor),
            kopf.trailingAnchor.constraint(equalTo: rechts.trailingAnchor),
            trenner.topAnchor.constraint(equalTo: kopf.bottomAnchor),
            trenner.leadingAnchor.constraint(equalTo: rechts.leadingAnchor),
            trenner.trailingAnchor.constraint(equalTo: rechts.trailingAnchor),
            web.topAnchor.constraint(equalTo: trenner.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: rechts.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: rechts.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: rechts.bottomAnchor),
        ])

        let teiler = NSSplitViewController()
        // Bewusst KEIN sidebarWithViewController: macOS zeichnet die Seitenleiste dann als
        // eingerueckten, abgerundeten Kasten — mit Luecke links und oben. Wir wollen sie
        // buendig, also ein normales Teil-Element mit eigenem Seitenleisten-Hintergrund.
        let linksItem = NSSplitViewItem(viewController: huelleMitHintergrund(links))
        linksItem.minimumThickness = 230
        linksItem.maximumThickness = 340
        linksItem.canCollapse = true
        // Haelt die Breite fest, wenn das Fenster groesser wird — der Inhalt waechst.
        linksItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)
        let rechtsItem = NSSplitViewItem(viewController: huelle(rechts))
        teiler.addSplitViewItem(linksItem)
        teiler.addSplitViewItem(rechtsItem)

        fenster.contentViewController = teiler
        // Bewusst NICHT das Suchfeld: der Schreibcursor soll beim Start nicht dort
        // stehen. Die Tastatur gehoert der angezeigten Seite; ins Suchfeld kommt
        // man mit Cmd-F oder einem Klick.
        fenster.initialFirstResponder = web

        // Im Vollbild gibt es keine Titelleiste; dort zaehlt nur die sichere Flaeche
        // (z. B. die Kamera-Aussparung).
        for name in [NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(kopfAbstandAngleichen),
                                                   name: name, object: fenster)
        }
        standardAufklappen()
    }

    @objc private func kopfAbstandAngleichen() {
        guard let fenster = window else { return }
        let vollbild = fenster.styleMask.contains(.fullScreen)
        let sicher = fenster.contentView?.safeAreaInsets.top ?? 0
        kopfOben.constant = vollbild ? 12 + sicher : 12
    }

    /// Die Trennlinie zwischen Kopf und Lernseite blendet sich ein, sobald die
    /// Seite darunter wegscrollt — steht sie ganz oben, gehen Kopf und Seite
    /// nahtlos ineinander ueber.
    private func trennerZeigen(_ an: Bool) {
        guard trenner != nil, trenner.alphaValue != (an ? 1 : 0) else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            trenner.animator().alphaValue = an ? 1 : 0
        }
    }

    /// Wie huelle(), aber mit eigenem Hintergrund — den uebernimmt sonst der
    /// System-Sidebar-Stil, den wir hier nicht benutzen.
    private func huelleMitHintergrund(_ inhalt: NSView) -> NSViewController {
        let c = NSViewController()
        let v = SeitenleistenHintergrund()
        seitenleisteHG = v
        v.addSubview(inhalt)
        NSLayoutConstraint.activate([
            inhalt.topAnchor.constraint(equalTo: v.topAnchor),
            inhalt.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            inhalt.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            inhalt.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        c.view = v
        return c
    }

    private func huelle(_ inhalt: NSView) -> NSViewController {
        let c = NSViewController()
        let v = NSView()
        v.addSubview(inhalt)
        NSLayoutConstraint.activate([
            inhalt.topAnchor.constraint(equalTo: v.topAnchor),
            inhalt.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            inhalt.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            inhalt.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        c.view = v
        return c
    }

    // MARK: Daten

    private func neuEinlesen() {
        faecher = Bibliothek.einlesen()
        staende = Fortschritt.alleStaende()
        plan = Tagesplan.laden()
        leistenAbdruck = abdruck(faecher, staende)
        baumBauen()
    }

    /// Alles, was die Leiste zeigt: Seiten mit Titel und Ort, die Haken fuer
    /// „heute geschafft“ — und das Datum, weil die Haken um Mitternacht fallen.
    private func abdruck(_ faecher: [Fach], _ staende: [String: SeitenStand]) -> String {
        let seiten = faecher.flatMap(\.alleSeiten)
            .map { "\($0.id)|\($0.titel)|\($0.fach)|\($0.thema)|\(staende[$0.id]?.tagespensum?.erledigt == true)" }
        return ([Datum.heute] + seiten).joined(separator: "\n")
    }

    /// Liest Seiten, Fortschritt und Tagesplan neu ein, ohne dass man ⌘R drücken
    /// muss. Gezeichnet wird nur, was sich geaendert hat; eine offene Lernseite
    /// bleibt unberuehrt, damit keine Eingabe verloren geht.
    @objc private func auffrischen() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.auffrischen() }
            return
        }
        guard liste != nil, window?.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        faecher = Bibliothek.einlesen()
        staende = Fortschritt.alleStaende()
        plan = Tagesplan.laden()
        let neu = abdruck(faecher, staende)
        if neu != leistenAbdruck {
            leistenAbdruck = neu
            baumBauen()
            liste.reloadData()
            standardAufklappen()
            auswahlAngleichen()
        }
        if aktuelleSeite == nil {
            let html = startseiteBauen()
            if html != gezeigteStartseite {
                gezeigteStartseite = html
                web.load(URLRequest(url: URL(string: "\(Server.basis)/start")!))
            }
        }
    }

    // MARK: Neuigkeiten (ⓘ)

    @objc private func neuigkeitenZeigen() {
        let fenster = NSPopover()
        fenster.behavior = .transient
        fenster.contentViewController = Neuigkeiten.ansicht()
        fenster.show(relativeTo: infoKnopf.bounds, of: infoKnopf, preferredEdge: .minY)
        Neuigkeiten.gelesen()
        infoPunkt.isHidden = true
    }

    private func baumBauen() {
        var bereiche: [Knoten] = []
        let suche = suchtext.trimmingCharacters(in: .whitespaces).lowercased()

        if !suche.isEmpty {
            let treffer = faecher.flatMap(\.alleSeiten).filter {
                $0.titel.lowercased().contains(suche)
                || $0.fach.lowercased().contains(suche)
                || $0.thema.lowercased().contains(suche)
            }
            bereiche = [Knoten(art: .bereich,
                               name: treffer.isEmpty ? "Nichts gefunden" : "Treffer",
                               kinder: treffer.map { Knoten(art: .seite, name: $0.titel, seite: $0) })]
            wurzel = bereiche
            return
        }

        // Angepinnt
        let favoriten = Zustand.aktuell.favoriten.compactMap { seiteMitID($0) }
        if !favoriten.isEmpty {
            bereiche.append(Knoten(art: .bereich, name: "Angepinnt",
                                   kinder: favoriten.map { Knoten(art: .seite, name: $0.titel, seite: $0) }))
        }

        // Aktuelle Fächer
        let aktiv = faecher.filter { !$0.archiv }
        if !aktiv.isEmpty {
            bereiche.append(Knoten(art: .bereich, name: "Aktuell",
                                   kinder: aktiv.map(fachKnoten)))
        }

        // Archiv
        let archiv = faecher.filter(\.archiv)
        if !archiv.isEmpty {
            bereiche.append(Knoten(art: .bereich, name: "Fürs Physikum",
                                   kinder: archiv.map(fachKnoten)))
        }
        wurzel = bereiche
    }

    /// Themen mit nur einer Seite bekommen keine eigene Ebene — das spart
    /// in der schmalen Leiste eine Einrückung und damit Platz für den Titel.
    private func fachKnoten(_ fach: Fach) -> Knoten {
        var kinder: [Knoten] = []
        for thema in fach.themen {
            if thema.seiten.count == 1 {
                let seite = thema.seiten[0]
                kinder.append(Knoten(art: .seite, name: seite.titel, seite: seite))
            } else {
                kinder.append(Knoten(art: .thema, name: thema.name,
                                     kinder: thema.seiten.map {
                                         Knoten(art: .seite, name: $0.titel, seite: $0) }))
            }
        }
        return Knoten(art: .fach, name: fach.name, kinder: kinder)
    }

    /// Stellt den Klappzustand her: was er selbst zu- oder aufgeklappt hat,
    /// bleibt so; sonst aktuelle Fächer offen, das Physikum-Archiv zu.
    /// Beim Suchen ist alles offen, damit jeder Treffer zu sehen ist.
    private func standardAufklappen() {
        guard liste != nil else { return }
        for bereich in wurzel {
            klappen(bereich, standard: true, fuerKinder: bereich.name != "Fürs Physikum")
        }
    }

    private func klappen(_ knoten: Knoten, standard: Bool, fuerKinder: Bool) {
        guard knoten.art != .seite, !knoten.kinder.isEmpty else { return }
        let offen = !suchtext.isEmpty || (klappzustand[knoten.schluessel] ?? standard)
        klapptSelbst = true
        if offen { liste.expandItem(knoten) } else { liste.collapseItem(knoten) }
        klapptSelbst = false
        // Kinder eines zugeklappten Knotens richtet erst outlineViewItemDidExpand
        // her, sobald er ihn aufmacht — vorher sind sie ohnehin unsichtbar.
        guard offen else { return }
        for kind in knoten.kinder {
            klappen(kind, standard: fuerKinder, fuerKinder: fuerKinder)
        }
    }

    private func klappzustandMerken(_ note: Notification, offen: Bool) {
        guard !klapptSelbst, suchtext.isEmpty,
              let knoten = note.userInfo?["NSObject"] as? Knoten else { return }
        klappzustand[knoten.schluessel] = offen
        UserDefaults.standard.set(klappzustand, forKey: "LeisteKlappzustand")
        if offen {
            var bereich = knoten
            while let e = bereich.eltern { bereich = e }
            let standard = bereich.name != "Fürs Physikum"
            for kind in knoten.kinder { klappen(kind, standard: standard, fuerKinder: standard) }
        }
    }

    private func seiteMitID(_ id: String) -> Seite? {
        faecher.flatMap(\.alleSeiten).first { $0.id == id }
    }

    // MARK: Navigation

    @objc private func startseiteZeigen() {
        fortschrittSichern()
        aktuelleSeite = nil
        staende = Fortschritt.alleStaende()
        titelLabel.stringValue = "Lernkiste"
        unterLabel.stringValue = "Übersicht"
        sternKnopf.isHidden = true
        auswahlAngleichen()
        gezeigteStartseite = startseiteBauen()
        web.load(URLRequest(url: URL(string: "\(Server.basis)/start")!))
    }

    /// Zeigt in der Leiste, wo man gerade ist: die offene Seite bleibt markiert,
    /// auf der Startseite leuchtet stattdessen der Knopf oben. Muss nach jedem
    /// reloadData laufen — die Auswahl haengt an der Zeilennummer, und die
    /// verschiebt sich beim Suchen oder Neueinlesen.
    private func auswahlAngleichen() {
        guard liste != nil else { return }
        startKnopfMarkieren(aktuelleSeite == nil)
        guard let id = aktuelleSeite?.id else { liste.deselectAll(nil); return }
        for zeile in 0..<liste.numberOfRows {
            if let k = liste.item(atRow: zeile) as? Knoten, k.seite?.id == id {
                liste.selectRowIndexes([zeile], byExtendingSelection: false)
                liste.scrollRowToVisible(zeile)
                return
            }
        }
        liste.deselectAll(nil)   // Seite aus der Suche gefiltert
    }

    /// Der Startseiten-Knopf ist die oberste Zeile der Leiste und wird wie eine
    /// ausgewaehlte Zeile eingefaerbt, solange die Startseite offen ist.
    private func startKnopfMarkieren(_ aktiv: Bool) {
        guard startKnopf != nil, startPille != nil else { return }
        // cgColor friert die Farbe ein — darum im Erscheinungsbild der Pille
        // aufloesen und beim Themenwechsel neu setzen.
        startPille.effectiveAppearance.performAsCurrentDrawingAppearance {
            startPille.layer?.backgroundColor = aktiv
                ? Farben.markierung.cgColor : NSColor.clear.cgColor
        }
        startKnopf.contentTintColor = .labelColor
        startKnopf.attributedTitle = NSAttributedString(
            string: "  Startseite",
            attributes: [.foregroundColor: NSColor.labelColor,
                         .font: NSFont.systemFont(ofSize: 12.5,
                                                  weight: aktiv ? .semibold : .regular)])
    }

    private func startseiteBauen() -> String {
        Startseite.bauen(faecher: faecher, staende: Fortschritt.alleStaende(),
                         plan: plan, zustand: Zustand.aktuell)
    }

    func oeffnen(_ seite: Seite) {
        fortschrittSichern()           // Stand der vorigen Seite retten
        aktuelleSeite = seite
        titelLabel.stringValue = seite.titel
        unterLabel.stringValue = "\(seite.fach) · \(seite.thema)"
        sternKnopf.isHidden = false
        sternAktualisieren()

        Zustand.aktuell.besucht(seite.id)

        let pfad = seite.relativerPfad
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? seite.relativerPfad
        guard let url = URL(string: "\(Server.basis)/seite/\(pfad)") else { return }
        web.load(URLRequest(url: url))
        liste.reloadData()
        auswahlAngleichen()
        // Ab hier soll die Tastatur der Lernseite gehoeren, nicht dem Suchfeld —
        // sonst landen Antworten und Kuerzel in der Suche.
        window?.makeFirstResponder(web)
    }

    @objc private func zeileGeklickt() {
        let zeile = liste.selectedRow
        guard zeile >= 0, let knoten = liste.item(atRow: zeile) as? Knoten else { return }
        if let seite = knoten.seite {
            if seite.id != aktuelleSeite?.id { oeffnen(seite) }
        } else {
            if liste.isItemExpanded(knoten) { liste.collapseItem(knoten) }
            else { liste.expandItem(knoten) }
        }
    }

    // MARK: Fortschritt

    /// Liest den gespeicherten Stand aus der offenen Seite und legt ihn als Datei ab.
    private func fortschrittSichern() { fortschrittSichern(dann: nil) }

    /// Wie oben, meldet sich aber, wenn der Stand wirklich auf der Platte liegt —
    /// der Updater wartet darauf, bevor er die App austauscht.
    func fortschrittSichern(dann: (() -> Void)?) {
        guard let seite = aktuelleSeite else { dann?(); return }
        let js = """
        (function(){var o={};for(var i=0;i<localStorage.length;i++){
        var k=localStorage.key(i);if(k&&k.indexOf('lern:')===0)o[k]=localStorage.getItem(k);}
        return JSON.stringify(o);})()
        """
        web.evaluateJavaScript(js) { ergebnis, _ in
            guard let text = ergebnis as? String,
                  let daten = text.data(using: .utf8),
                  let roh = try? JSONDecoder().decode([String: String].self, from: daten)
            else { dann?(); return }
            let stand = Fortschritt.auswerten(roh: roh, seite: seite)
            Fortschritt.sichern(stand)
            dann?()
            DispatchQueue.main.async { [weak self] in
                self?.staende[seite.id] = stand
                self?.liste.reloadData()
                self?.auswahlAngleichen()
            }
        }
    }

    @objc private func fensterSchliesst() { fortschrittSichern() }

    /// Text nil blendet den Update-Knopf aus.
    func updateKnopfSetzen(_ text: String?, klickbar: Bool) {
        guard updateKnopf != nil else { return }
        updateKnopf.isHidden = text == nil
        if let text { updateKnopf.title = text }
        updateKnopf.isEnabled = klickbar
    }

    // MARK: Brücke zur Seite

    /// Textauswahl auf den Lernseiten: abgeschaltet. HTML markiert beim Ziehen
    /// immer ganze Zeilen des umgebenden Kastens — das lief quer ueber das Fenster.
    /// Eingabefelder bleiben ausgenommen, sonst koennte man dort nichts korrigieren.
    /// Die Restauswahl (Feldinhalt) wird grau statt system-blau gezeichnet.
    private func markierungsStil() -> String {
        """
        (function(){
          var s = document.createElement('style');
          s.textContent =
              'html,body{-webkit-user-select:none;user-select:none}'
            + 'input,textarea,[contenteditable="true"]{-webkit-user-select:text;user-select:text}'
            + '::selection{background:rgba(255,255,255,.16)}'
            + ':root[data-theme="light"] ::selection{background:rgba(0,0,0,.12)}';
          document.documentElement.appendChild(s);

          // Meldet der App, ob die Seite ganz oben steht (Trennlinie im Kopf).
          var obenZuletzt = null;
          function melden(){
            var oben = (window.scrollY || document.documentElement.scrollTop || 0) <= 2;
            if (oben === obenZuletzt) return;
            obenZuletzt = oben;
            try { window.webkit.messageHandlers.lernkiste.postMessage({art:'scroll', oben:oben}); } catch(e){}
          }
          window.addEventListener('scroll', melden, {passive:true});
          window.addEventListener('load', melden);
          document.addEventListener('DOMContentLoaded', melden);
        })();
        """
    }

    /// Welche GIFs heute welcher Seite gehoeren.
    /// „fertig" wird fest zugeteilt: an einem Tag bekommt jede Lernseite ein
    /// anderes GIF, am naechsten Tag dreht sich die Zuteilung weiter. Die
    /// beiden anderen Anlaesse werden auf der Seite zufaellig gezogen.
    private func gifsJSON() -> String {
        func dateien(_ anlass: String) -> [String] {
            let ordner = Orte.gifs.appendingPathComponent(anlass)
            let inhalt = (try? FileManager.default.contentsOfDirectory(atPath: ordner.path)) ?? []
            return inhalt.filter { !$0.hasPrefix(".") }.sorted()
        }
        let tag = Int(Date().timeIntervalSince1970 / 86_400)
        let seiten = faecher.flatMap { $0.themen.flatMap { $0.seiten } }.map { $0.id }.sorted()

        var fertig: [String: String] = [:]
        let vorrat = dateien("fertig")
        if !vorrat.isEmpty {
            for (i, id) in seiten.enumerated() {
                // Seitenindex + Tagesversatz: an einem Tag bekommt jede Seite ein
                // anderes GIF, und jeden Tag rutscht die ganze Reihe um eins weiter.
                // So laeuft der Vorrat wirklich durch, statt zwischen nur zwei
                // Verteilungen hin- und herzuspringen.
                fertig[id] = vorrat[(i + tag) % vorrat.count]
            }
        }
        let paket: [String: Any] = ["fertig": fertig,
                                    "meilenstein": dateien("meilenstein"),
                                    "durchhaenger": dateien("durchhaenger")]
        guard let daten = try? JSONSerialization.data(withJSONObject: paket),
              let text = String(data: daten, encoding: .utf8) else { return "{}" }
        return text
    }

    private func bruecke() -> String {
        let planJSON: String = {
            guard let plan, plan.fuerHeute else { return "[]" }
            // Bevorzugt die Rohfassung aus der Datei, damit Zusatzfelder erhalten bleiben.
            if let roh = Tagesplan.rohEintraegeJSON() { return roh }
            guard let daten = try? JSONEncoder().encode(plan.eintraege),
                  let text = String(data: daten, encoding: .utf8) else { return "[]" }
            return text
        }()
        return """
        (function(){
          var eintraege = \(planJSON);
          var gifs = \(gifsJSON());
          window.Lernkiste = {
            version: 1,
            theme: "\(Zustand.aktuell.theme)",
            tagesplan: function(id){
              for (var i=0;i<eintraege.length;i++){
                if (eintraege[i].seite === id) return eintraege[i];
              }
              return null;
            },
            /* anlass: 'fertig' | 'meilenstein' | 'durchhaenger'.
               Ohne passende Datei kommt null zurueck — die Seite bleibt dann
               bei ihrer eingebauten Darstellung. */
            gif: function(id, anlass){
              var a = anlass || 'fertig', name = null;
              if (a === 'fertig') name = (gifs.fertig || {})[id];
              else {
                var liste = gifs[a] || [];
                if (liste.length) name = liste[Math.floor(Math.random()*liste.length)];
              }
              return name ? '/gif/' + a + '/' + encodeURIComponent(name) : null;
            },
            fertig: function(ergebnis){
              sende({art:"fertig", ergebnis: ergebnis||null});
            },
            oeffne: function(id){ sende({art:"oeffnen", id:id}); }
          };
          // Die Startseite ruft oeffne(...) direkt auf.
          window.oeffne = window.Lernkiste.oeffne;
          document.documentElement.dataset.theme = window.Lernkiste.theme;
          function sende(n){
            try { window.webkit.messageHandlers.lernkiste.postMessage(n); } catch(e){}
          }
        })();
        """
    }

    func userContentController(_ c: WKUserContentController,
                               didReceive nachricht: WKScriptMessage) {
        guard let inhalt = nachricht.body as? [String: Any],
              let art = inhalt["art"] as? String else { return }
        switch art {
        case "fertig":
            fortschrittSichern()
        case "oeffnen":
            if let id = inhalt["id"] as? String { seiteOeffnenPerID(id) }
        case "anleitungWeg":
            Zustand.aktuell.anleitungAusgeblendet = true
            Zustand.aktuell.sichern()
            if aktuelleSeite == nil { startseiteZeigen() }
        case "scroll":
            trennerZeigen(!((inhalt["oben"] as? Bool) ?? true))
        default:
            break
        }
    }

    /// Wohin eine Seite springen darf. Lernseiten bleiben in der Lernkiste:
    /// Links ins Netz gehen erst nach Rueckfrage und dann im normalen Browser auf,
    /// alles, was eine Seite ungefragt ansteuern will, wird verworfen.
    func webView(_ webView: WKWebView, decidePolicyFor aktion: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = aktion.request.url else { decisionHandler(.cancel); return }
        let schema = url.scheme?.lowercased() ?? ""

        if ["about", "data", "blob"].contains(schema) { decisionHandler(.allow); return }
        if schema == "http", url.host == "127.0.0.1" || url.host == "localhost",
           url.port == Int(Server.port) {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)

        // Eine HTML-Datei ins Fenster gezogen: aufnehmen statt nur anzeigen.
        if url.isFileURL {
            if ["html", "htm"].contains(url.pathExtension.lowercased()) {
                DispatchQueue.main.async { [weak self] in Import.dateien([url], self) }
            }
            return
        }
        guard aktion.navigationType == .linkActivated,
              ["http", "https", "mailto"].contains(schema) else { return }
        DispatchQueue.main.async { [weak self] in self?.externFragen(url) }
    }

    private func externFragen(_ url: URL) {
        let frage = NSAlert()
        frage.messageText = "Seite im Browser öffnen?"
        frage.informativeText = "Der Link führt aus der Lernkiste hinaus zu:\n\n"
            + (url.scheme == "mailto" ? url.absoluteString : (url.host ?? url.absoluteString))
        frage.addButton(withTitle: "Im Browser öffnen")
        frage.addButton(withTitle: "Abbrechen")
        let antwort: (NSApplication.ModalResponse) -> Void = { r in
            if r == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
        }
        if let window { frage.beginSheetModal(for: window, completionHandler: antwort) }
        else { antwort(frage.runModal()) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        themaAnwenden()
        trennerZeigen(false)   // jede Seite faengt oben an
        // Kurz warten, bis die Seite ihren Stand geladen/geschrieben hat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.fortschrittSichern()
        }
    }

    // MARK: Aussehen

    @objc private func themaUmschalten() {
        Zustand.aktuell.theme = Zustand.aktuell.theme == "dark" ? "light" : "dark"
        Zustand.aktuell.sichern()
        themaAnwenden()
        if aktuelleSeite == nil { startseiteZeigen() }
    }

    private func themaAnwenden() {
        let dunkel = Zustand.aktuell.theme == "dark"
        window?.appearance = NSAppearance(named: dunkel ? .darkAqua : .aqua)
        seitenleisteHG?.needsDisplay = true
        web?.superview?.needsDisplay = true
        liste?.backgroundColor = Farben.seitenleiste
        // Die Akzentfarbe des Knopfes ist eingefroren — nach dem Wechsel neu setzen.
        startKnopfMarkieren(aktuelleSeite == nil)
        web.evaluateJavaScript("""
        document.documentElement.dataset.theme='\(Zustand.aktuell.theme)';
        if(window.Lernkiste) window.Lernkiste.theme='\(Zustand.aktuell.theme)';
        """)
    }

    @objc private func favoritUmschalten() {
        guard let seite = aktuelleSeite else { return }
        Zustand.aktuell.favoritUmschalten(seite.id)
        sternAktualisieren()
        baumBauen()
        liste.reloadData()
        standardAufklappen()
        auswahlAngleichen()   // Anpinnen schiebt die Zeilen
    }

    private func sternAktualisieren() {
        guard let seite = aktuelleSeite else { return }
        let an = Zustand.aktuell.istFavorit(seite.id)
        sternKnopf.image = NSImage(systemSymbolName: an ? "star.fill" : "star",
                                   accessibilityDescription: nil)
        sternKnopf.contentTintColor = an ? .systemOrange : nil
    }

    // MARK: Suche

    /// Setzt den Schreibcursor ins Suchfeld — ueber Bearbeiten > Suchen (Cmd-F).
    @objc func sucheFokussieren() {
        guard let fenster = window else { return }
        fenster.makeFirstResponder(suchfeld)
        suchfeld.currentEditor()?.selectAll(nil)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let feld = obj.object as? NSSearchField else { return }
        suchtext = feld.stringValue
        baumBauen()
        liste.reloadData()
        standardAufklappen()
        auswahlAngleichen()
    }

    // MARK: NSOutlineView

    func outlineView(_ v: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Knoten)?.kinder.count ?? wurzel.count
    }
    func outlineView(_ v: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Knoten)?.kinder[index] ?? wurzel[index]
    }
    func outlineView(_ v: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Knoten)?.kinder.isEmpty ?? true)
    }
    func outlineViewItemDidExpand(_ note: Notification) { klappzustandMerken(note, offen: true) }
    func outlineViewItemDidCollapse(_ note: Notification) { klappzustandMerken(note, offen: false) }

    func outlineView(_ v: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? Knoten)?.istGruppe ?? false
    }
    func outlineView(_ v: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !((item as? Knoten)?.istGruppe ?? false)
    }

    func outlineView(_ v: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        BetonteZeile()
    }

    func outlineView(_ v: NSOutlineView, viewFor spalte: NSTableColumn?,
                     item: Any) -> NSView? {
        guard let knoten = item as? Knoten else { return nil }
        let kennung = NSUserInterfaceItemIdentifier("zeile")
        let zelle = (v.makeView(withIdentifier: kennung, owner: self) as? ZeilenZelle)
            ?? zelleBauen(kennung)
        guard let text = zelle.textField else { return zelle }

        text.stringValue = knoten.name
        zelle.toolTip = knoten.seite.map { "\($0.titel)\n\($0.fach) · \($0.thema)" } ?? knoten.name
        zelle.imageView?.image = nil
        zelle.imageView?.isHidden = true

        switch knoten.art {
        case .bereich:
            text.font = .systemFont(ofSize: 11, weight: .semibold)
            zelle.eigeneFarbe = Farben.schriftLeise
            text.stringValue = knoten.name.uppercased()
        case .fach:
            text.font = .systemFont(ofSize: 13, weight: .medium)
            zelle.eigeneFarbe = Farben.schrift
        case .thema:
            text.font = .systemFont(ofSize: 12.5)
            zelle.eigeneFarbe = Farben.schrift
        case .seite:
            text.font = .systemFont(ofSize: 12.5)
            zelle.eigeneFarbe = Farben.schrift
            // Nur der gruene Haken fuer „heute geschafft“ bleibt. Wackelkandidaten
            // werden hier bewusst nicht mehr markiert — das stand wie eine Fehlermeldung
            // in der Liste; sie stehen auf der Seite selbst.
            if let seite = knoten.seite, let stand = staende[seite.id],
               let p = stand.tagespensum, p.erledigt {
                zelle.imageView?.isHidden = false
                zelle.imageView?.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                                 accessibilityDescription: "heute geschafft")
                zelle.imageView?.contentTintColor = .systemGreen
            }
        }
        return zelle
    }

    private func zelleBauen(_ kennung: NSUserInterfaceItemIdentifier) -> ZeilenZelle {
        let zelle = ZeilenZelle()
        zelle.identifier = kennung

        let bild = NSImageView()
        bild.translatesAutoresizingMaskIntoConstraints = false
        bild.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        zelle.addSubview(bild)
        zelle.imageView = bild

        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingTail
        zelle.addSubview(text)
        zelle.textField = text

        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: zelle.leadingAnchor),
            text.centerYAnchor.constraint(equalTo: zelle.centerYAnchor),
            bild.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor, constant: 5),
            bild.trailingAnchor.constraint(equalTo: zelle.trailingAnchor, constant: -6),
            bild.centerYAnchor.constraint(equalTo: zelle.centerYAnchor),
            bild.widthAnchor.constraint(equalToConstant: 13),
        ])
        return zelle
    }

    // MARK: Rechtsklick in der Leiste

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let zeile = liste.clickedRow
        guard zeile >= 0, let knoten = liste.item(atRow: zeile) as? Knoten,
              !knoten.istGruppe else { return }
        let titel: String
        switch knoten.art {
        case .seite:  titel = "Seite teilen …"
        case .thema:  titel = "Thema „\(knoten.name)“ teilen …"
        case .fach:   titel = "Fach „\(knoten.name)“ teilen …"
        case .bereich: return
        }
        let teilen = NSMenuItem(title: titel, action: #selector(knotenTeilen(_:)), keyEquivalent: "")
        teilen.target = self
        teilen.representedObject = knoten
        teilen.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        menu.addItem(teilen)
        let finder = NSMenuItem(title: "Im Finder zeigen", action: #selector(knotenImFinder(_:)),
                                keyEquivalent: "")
        finder.target = self
        finder.representedObject = knoten
        menu.addItem(finder)
    }

    /// Alle Seiten unter einem Knoten — beim Fach auch die Themen darunter.
    private func seitenUnter(_ knoten: Knoten) -> [Seite] {
        if let seite = knoten.seite { return [seite] }
        return knoten.kinder.flatMap(seitenUnter)
    }

    @objc private func knotenTeilen(_ eintrag: NSMenuItem) {
        guard let knoten = eintrag.representedObject as? Knoten else { return }
        let zeile = liste.row(forItem: knoten)
        let rechteck = zeile >= 0 ? liste.rect(ofRow: zeile) : liste.visibleRect
        var name = knoten.name
        if knoten.art == .thema, let fach = seitenUnter(knoten).first?.fach { name = "\(fach) – \(name)" }
        Export.teilen(seitenUnter(knoten), name: name, von: liste, bei: rechteck)
    }

    @objc private func knotenImFinder(_ eintrag: NSMenuItem) {
        guard let knoten = eintrag.representedObject as? Knoten else { return }
        let seiten = seitenUnter(knoten)
        if knoten.art == .seite {
            NSWorkspace.shared.activateFileViewerSelecting(seiten.map(\.datei))
        } else if let erste = seiten.first {
            // Thema: dessen Ordner; Fach: eine Ebene hoeher.
            var ordner = erste.datei.deletingLastPathComponent()
            if knoten.art == .fach { ordner = ordner.deletingLastPathComponent() }
            NSWorkspace.shared.activateFileViewerSelecting([ordner])
        }
    }

    /// Ablage → Seite teilen (Cmd-E): die gerade offene Seite.
    func offeneSeiteTeilen() {
        guard let seite = aktuelleSeite else {
            let hinweis = NSAlert()
            hinweis.messageText = "Öffne zuerst eine Seite."
            hinweis.informativeText = "Ganze Themen und Fächer teilst du mit einem Rechtsklick in der Seitenleiste."
            hinweis.addButton(withTitle: "OK")
            hinweis.runModal()
            return
        }
        Export.teilen([seite], name: seite.titel, von: titelLabel, bei: titelLabel.bounds)
    }

    // MARK: Hineinziehen in die Leiste

    private func gezogeneSeiten(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter {
            ["html", "htm", "zip"].contains($0.pathExtension.lowercased()) || $0.hasDirectoryPath
        }
    }

    func outlineView(_ o: NSOutlineView, validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard !gezogeneSeiten(info).isEmpty else { return [] }
        o.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)   // ganze Leiste leuchtet
        return .copy
    }

    func outlineView(_ o: NSOutlineView, acceptDrop info: NSDraggingInfo,
                     item: Any?, childIndex index: Int) -> Bool {
        let urls = gezogeneSeiten(info)
        guard !urls.isEmpty else { return false }
        DispatchQueue.main.async { [weak self] in Import.dateien(urls, self) }
        return true
    }

    // MARK: Von der Startseite aufgerufen

    func seiteOeffnenPerID(_ id: String) {
        guard let seite = seiteMitID(id) else { return }
        oeffnen(seite)
        standardAufklappen()
        auswahlAngleichen()   // nach dem Aufklappen stimmen die Zeilennummern wieder
    }

    func bibliothekNeuLaden() {
        neuEinlesen()
        liste.reloadData()
        standardAufklappen()
        auswahlAngleichen()
        if aktuelleSeite == nil { startseiteZeigen() }
    }
}
