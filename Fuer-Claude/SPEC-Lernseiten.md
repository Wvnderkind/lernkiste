# Vertrag: Lernseite ↔ Lernkiste-App

Version 2 · gilt für alle Seiten, die der Agent `lern-interaktiv` baut
und für alle Seiten, die für die Lernkiste nachgerüstet werden.

## Grundregel

Eine Lernseite ist **Stoff, kein Programm**. Das Übungsverhalten — Fortschritt,
Tagespensum, Enter-Steuerung, Abschlussbildschirm, GIFs — liefert der gemeinsame
Motor unter `Seiten/_motor/` (Kapitel 8). Die Seite selbst enthält nur noch den
Kopf, ein paar Merkkästen und die Aufgabenliste.

Eine Lernseite funktioniert **weiterhin per Doppelklick im Finder, offline**: der
Motor liegt im selben Ordnerbaum und wird relativ geladen. Die Lernkiste ist ein
*zusätzliches* Zuhause, kein Ersatz. **Niemals** etwas einbauen, das ohne die App
kaputtgeht.

Aeltere Seiten, die ihr eigenes Geruest mitbringen, bleiben so, wie sie sind.
Sie werden nicht umgebaut.

## 0 — Ablageort (Pflicht)

Alles, was zur Lernkiste gehoert, liegt in **einem** Ordner:

```
~/Documents/Lernkiste/
  Seiten/<Fach>/<Themengebiet>/<slug>.html   ← hier kommt jede neue Lernseite hin
  fortschritt/    gifs/    tagesplan.json    konfiguration.json    zustand.json
```

Neue Seiten gehoeren **ausschliesslich** nach `Seiten/<Fach>/<Themengebiet>/` — nur
von dort liest die App. Seiten, die woanders liegen, tauchen nicht auf.

## 1 — Identität der Seite (Pflicht)

Im `<head>` genau ein Meta-Block. Daraus liest die App Titel, Fach, Thema und Seitentyp:

```html
<meta name="lernkiste-id"    content="chemie/redox/oxidationszahlen">
<meta name="lernkiste-titel" content="Oxidationszahlen bestimmen">
<meta name="lernkiste-typ"   content="drill">
<meta name="lernkiste-version" content="1">
```

- `id` = `<fach>/<themengebiet>/<slug>`, kleingeschrieben, ohne Umlaute (ae/oe/ue/ss).
  Muss zum Ablageort passen: `~/Documents/Lernkiste/Seiten/Chemie/Redox/oxidationszahlen.html`.
- `typ` = einer von: `schema`, `tabelle`, `drill`, `mechanismus`, `zuordnung`, `kompendium`.
- `version` hochzählen, wenn sich die Item-IDs ändern (alter Fortschritt wird dann verworfen).

## 2 — Fortschritt (Pflicht)

Die Seite schreibt ihren Stand in **genau einen** localStorage-Schlüssel:

```
lern:<id>@v<version>
```

Inhalt, exakt dieses Format — die App zeigt daraus die Fortschrittsanzeige:

```json
{
  "items": {
    "item-id": { "sass": 3, "sassNicht": 1, "letzter": "sass", "zuletzt": "2026-09-21" }
  },
  "gesamt": 30,
  "tagespensum": {
    "datum": "2026-09-21",
    "ziel": 20,
    "geschafft": 12,
    "treffer": 9,
    "offen": { "item-id": 1 }
  },
  "zuletztGeoeffnet": "2026-09-21T14:32:00"
}
```

- `gesamt` = Anzahl aller abfragbaren Items der Seite (für "12 von 30 sitzen").
- `sass` / `sassNicht` = Zähler über alle Versuche hinweg.
- `letzter` = Ausgang des **letzten** Versuchs, genau `"sass"` oder `"sassNicht"`. Pflichtfeld.
- `zuletzt` = Datum des letzten Versuchs, `JJJJ-MM-TT`.
- **Wackelkandidat** = Item mit `letzter == "sassNicht"`. Die App rechnet das selbst aus
  und zeigt es in der Seitenleiste an — deshalb muss `letzter` bei **jedem** Versuch
  mitgeschrieben werden, nicht nur die Zähler.
- Eigene Zusatzschlüssel sind erlaubt, müssen aber mit `lern:<id>@` beginnen.

**Kein Export-Knopf mehr.** Die App liest den Schlüssel automatisch aus und legt den
Stand in `~/Documents/Lernkiste/fortschritt/` ab. Der alte Knopf
„📤 Fortschritt für Claude sichern" entfällt bei nachgerüsteten Seiten ersatzlos.

## 3 — Tagespensum (Pflicht bei Trainer-Seiten)

Unverändert wie gehabt: `const TAGESPLAN = {'JJJJ-MM-TT': {ziel, schwerpunkt, hinweis}}`
plus `STANDARD`-Fallback, Fortschrittsleiste „Heute geschafft x / n", Abschlussbildschirm
„Geschafft für heute" mit Trefferquote, Knopf „Trotzdem weiterüben".

**Heutige Wackler zuerst festigen:** Was heute falsch beantwortet wurde, steht in
`tagespensum.offen` (`id → richtig in Folge`). Ist das Ziel erreicht, aber noch etwas
offen, fragt der Motor nur noch diese Aufgaben ab — jede muss **zweimal hintereinander**
sitzen, erst dann kommt „Geschafft für heute". Die Kopfzeile zeigt dabei
„Vor dem Ziel noch festigen: n". Es zählen nur Aufgaben aus der aktuellen Auswahl.

Neu: Die Seite darf den Tagesplan auch von der App beziehen, wenn sie dort läuft.
**Der Plan aus der App ergänzt die Voreinstellungen, er ersetzt sie nicht** — sonst
fallen Felder, die der Plan nicht nennt (z. B. `umfang`, `modus`), auf `undefined`
und die Seite zeigt gar keine Frage mehr. Also immer zusammenführen statt `??`:

```js
function nurGesetzte(o){
  const r = {};
  for (const k in (o||{})) if (o[k] !== null && o[k] !== undefined) r[k] = o[k];
  return r;
}
const planVonApp = window.Lernkiste?.tagesplan?.(SEITEN_ID);
const heute = Object.assign({}, STANDARD,
                            nurGesetzte(TAGESPLAN[datumHeute()]),
                            nurGesetzte(planVonApp));
```

Läuft die Seite im Browser, ist `window.Lernkiste` schlicht `undefined` und der
eingebaute `TAGESPLAN` greift. Immer mit `?.` absichern.

Ein Eintrag in `tagesplan.json` darf über `ziel`/`schwerpunkt`/`hinweis` hinaus
beliebige weitere Felder tragen (`umfang`, `modus`, `kategorien` …). Die App reicht
den Eintrag unverändert durch, die Seite nimmt davon, was sie kennt.

**Seine eigene Wahl gewinnt über den Plan.** Klickt er einen Modus-, Umfang- oder
Kategorie-Knopf an, merkt sich die Seite das dauerhaft und startet beim nächsten
Öffnen genau so. Der Tagesplan liefert nur den Startwert, solange er das
betreffende Feld noch nie selbst gewählt hat. Eigener Schlüssel dafür:

```js
const EKEY = "lern:" + SEITEN_ID + "@v1-einstellungen";
const Eigene = {
  load(){ try{ return JSON.parse(localStorage.getItem(EKEY)||'null') || {}; }catch(e){ return {}; } },
  merken(feld, wert){
    const o = Eigene.load(); o[feld] = wert;
    try{ localStorage.setItem(EKEY, JSON.stringify(o)); }catch(e){}
  }
};
const EIGENE = Eigene.load();
let state = { modus: EIGENE.modus ?? PLAN.modus, umfang: EIGENE.umfang ?? PLAN.umfang, … };
```

Jede `setXY`-Funktion ruft zusätzlich `Eigene.merken('xy', wert)`. **Nicht** gemerkt
werden kurzlebige Filter („Nur Wackelkandidaten"), die bei jedem Öffnen wieder
aus sein sollen. Das Tagesziel (`ziel`) bleibt immer Sache des Plans.

## 4 — Aussehen (Pflicht)

Diese Tokens exakt übernehmen — sie sind der Kanon der App (Variante „Schiefer“:
kühles Neutralgrau + Kupfer). Identisch mit `~/Lernkiste/Ressourcen/tokens.css`.

**Keine hartkodierten Farben** irgendwo sonst — auch nicht in SVG: dort `fill="var(--accent)"`.

```css
:root{
  --bg:#0f1011;      --surface:#191b1c;   --surface-2:#232628;
  --line:#2f3335;    --text:#e8eaea;      --text-dim:#949a9c;
  --accent:#c9683c;  --accent-soft:#25190f;
  --gold:#cba14e;    --red:#d95f4e;       --orange:#d2823f;
  --green:#4f9e7c;   --teal:#4b9aa3;      --violet:#9b8ec4;
  --ok:#4f9e7c;      --no:#d95f4e;
  --shadow:0 2px 14px rgba(0,0,0,.55);
}
:root[data-theme="light"]{
  --bg:#f7f7fb;      --surface:#ffffff;   --surface-2:#eef0f7;
  --line:#d3d7e6;    --text:#1a1a2e;      --text-dim:#5a5f7a;
  --accent:#a8512a;  --accent-soft:#f7e6dc;
  --gold:#8a6a1e;    --red:#c02626;       --orange:#a85b00;
  --green:#1a7a42;   --teal:#1f6f78;      --violet:#6a3fc0;
  --ok:#1a7a42;      --no:#c02626;
  --shadow:0 2px 10px rgba(30,40,80,.10);
}
```

Dazu gehoert die Textauswahl: **aus**. Beim Ziehen markiert HTML immer ganze Zeilen
des umgebenden Kastens, nicht nur die Buchstaben — das lief quer ueber das Fenster.
Eingabefelder bleiben ausgenommen, sonst kann man dort nichts mehr korrigieren:

```css
html, body{ -webkit-user-select: none; user-select: none; }
input, textarea, [contenteditable="true"]{ -webkit-user-select: text; user-select: text; }
::selection{ background: rgba(255,255,255,.16); }
:root[data-theme="light"] ::selection{ background: rgba(0,0,0,.12); }
```

(In der App spielt das Programm dieselben Regeln zusaetzlich in jede Seite ein.)

Weiteres:
- Schrift: `-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif`.
- Inhalt in einem zentrierten Container `max-width: 980px; margin: 0 auto; padding: 0 20px`.
- **Kein eigener Theme-Umschalter mehr** bei App-Seiten: die App schaltet um und setzt
  `document.documentElement.dataset.theme`. Läuft die Seite im Browser, greift der
  Fallback unten. Den alten Umschalt-Knopf im Seitenkopf entfernen.

```js
// Theme: App gewinnt, sonst gespeicherte Wahl, sonst dunkel
if (!window.Lernkiste) {
  document.documentElement.dataset.theme =
    localStorage.getItem('lern-theme') || 'dark';
}
```

- **Keinen großen Titel-Header mehr** oben auf der Seite: die App zeigt Titel und Fach
  bereits in ihrer Kopfzeile. Direkt mit dem Inhalt anfangen. Im Browser ist das
  verschmerzbar, in der App sieht doppelt gemoppelt schlecht aus.

## 5 — Die Brücke `window.Lernkiste`

Nur vorhanden, wenn die Seite in der App läuft. **Immer** auf Existenz prüfen.

| Aufruf | Wirkung |
|---|---|
| `Lernkiste.version` | `1` |
| `Lernkiste.tagesplan(id)` | Eintrag aus `tagesplan.json`, unverändert (mindestens `{ziel, schwerpunkt, hinweis}`, ggf. mehr) oder `null` |
| `Lernkiste.fertig(ergebnis)` | meldet „Tagespensum geschafft" an die App (Startseite hakt ab) |
| `Lernkiste.theme` | `'dark'` \| `'light'` |
| `Lernkiste.gif(id, anlass)` | Pfad zu einem Glückwunsch-GIF oder `null` |

Fortschritt muss **nicht** aktiv gemeldet werden — die App liest localStorage selbst aus.

### Glückwunsch-GIFs

`Lernkiste.gif(id, anlass)` liefert eine URL auf ein GIF aus dem Ordner
`~/Documents/Lernkiste/gifs/<anlass>/`. Drei Anlässe:

| Anlass | Wann | Wie ausgewählt |
|---|---|---|
| `fertig` | Tagespensum geschafft — ersetzt den grünen Haken auf dem Schlussbildschirm | fest zugeteilt: jede Seite bekommt an einem Tag ein anderes GIF, am nächsten Tag wandert die Zuteilung weiter |
| `meilenstein` | Serie von 10 richtigen Antworten, oder ein Wackelkandidat sitzt endlich | zufällig aus dem Ordner |
| `durchhaenger` | dieselbe Aufgabe war 4× falsch (danach nur noch jedes dritte Mal) | zufällig aus dem Ordner |

**Pflicht: die Seite muss ohne GIF genauso funktionieren.** Im Browser gibt es die
Brücke nicht, dann kommt `null` zurück und die Seite bleibt bei ihrer eingebauten
Darstellung (Haken, Text). Also immer `GIF.bild('fertig') || '<div class="fertig-icon">✅</div>'`.

Der Baustein dafür steht in jeder Trainer-Seite gleich (`const GIF = {…}`,
`gifReaktion(eintrag, richtig, warWackler)`, `#gifToast` direkt vor `</body>`) —
beim Bauen einer neuen Seite aus einer bestehenden übernehmen.

Meilenstein und Durchhänger erscheinen als kleine Einblendung unten rechts
(`#gifToast`), nie als Blocker: sie halten die Seite nicht an und verschwinden nach
5 Sekunden von selbst. Der Text dazu ist deutsch und kurz, beim Durchhänger
aufmunternd bis leicht ironisch („Konzentrier dich mal").

Die App zählt in `gifs/nutzung.json` mit, welche Datei wirklich ausgeliefert wurde.
Der geplante Task **„Lernkiste-GIFs auffrischen"** schaut da alle zwei Wochen rein
und tauscht die abgenutzten aus (verschieben nach `gifs/archiv/`, nie löschen).

## 6 — Enter (Pflicht bei Trainer-Seiten)

Eine Trainer-Seite muss sich mit **Enter allein** durchspielen lassen. Enter bringt die
Seite immer genau **einen Schritt weiter**: erst prüfen, dann zur nächsten Frage. Die
Antwort selbst wird weiterhin mit der Maus gewählt — **keine Zifferntasten**, keine
weiteren Kürzel.

Am Dateiende, als eigener `<script>`-Block vor `</body>`:

```html
<script>
(function(){
  function sichtbar(el){ return !!el && !el.disabled && el.offsetParent !== null; }
  function klick(wurzel, wahl){
    const el = (wurzel || document).querySelector(wahl);
    if(!sichtbar(el)) return false;
    el.click();
    return true;
  }

  /* Der erste Treffer von oben gewinnt — seitenspezifisch. */
  function schritt(){
    if(klick(document, '#btnWeiter')) return true;
    return klick(document, '#btnPruefen');
  }

  document.addEventListener('keydown', function(ev){
    if(ev.key !== 'Enter' || ev.repeat || ev.isComposing) return;
    if(ev.altKey || ev.metaKey || ev.ctrlKey) return;
    const ziel = ev.target;
    if(ziel && (ziel.tagName === 'TEXTAREA' || ziel.isContentEditable)) return;
    if(ziel && ziel.tagName === 'INPUT' && ziel.hasAttribute('onkeydown')) return;
    if(schritt()) ev.preventDefault();
  });
})();
</script>
```

Regeln dazu:

- **Über den sichtbaren Knopf gehen, nicht über interne Zustände.** Steht kein passender
  Knopf da (Startbildschirm, „Geschafft für heute"), passiert nichts.
- **Textfelder mit eigenem `onkeydown` bleiben unangetastet** — sonst prüft Enter zweimal.
  Felder ohne eigene Enter-Logik darf der Handler bedienen.
- **Selbsteinschätzung („saß" / „saß nicht"):** Enter nimmt das Ergebnis, das die Seite
  ohnehin kennt (richtig → „saß", falsch → „saß nicht"). Mit der Maus bleibt beides frei
  wählbar.
- **Nie automatisch klicken**, was eine eigene Entscheidung ist: „Rechenweg zeigen",
  „Trotzdem weiterüben", „Fortschritt zurücksetzen", Filter- und Modus-Knöpfe.
- Ein Rechenweg in Schritten darf mit Enter durchgeblättert werden.
- Enter darf den Fortschritt nie anders zählen als ein Mausklick auf denselben Knopf.

## 7 — Verboten

- CDNs, externe Fonts, jeder Netzwerkzugriff.
- `alert()`, `confirm()`, `prompt()` — blockieren das App-Fenster.
- `window.open()`, Navigation zu anderen Seiten (`location.href = ...`).
- Ein Download-Knopf für den Fortschritt (die App übernimmt das).

## 8 — Der Motor `Lernseite.start()`

Der Motor liegt in **zwei Dateien** und wird im Kopf der Seite eingebunden — immer
relativ, zwei Ebenen hoch (Seite liegt in `Seiten/<Fach>/<Thema>/`):

```html
<link rel="stylesheet" href="../../_motor/lernkiste.css">
<script src="../../_motor/lernkiste.js"></script>
```

Die beiden Dateien liegen **im Programm** (`Ressourcen/lernkiste.js`, `.css`) und
werden bei jedem Start nach `Seiten/_motor/` gespiegelt. Wer am Motor etwas ändert,
ändert die Fassung in `~/Lernkiste/Ressourcen/` und baut die App neu — eine Kopie
im Datenordner wird beim nächsten Start überschrieben. Ordner mit führendem `_`
listet die App nicht als Fach.

Die Seite ruft am Ende genau einmal auf:

```js
Lernseite.start({
  id: "chemie/saeure-base/ph-und-titration",   // wie im Meta-Block
  version: 1,
  untertitel: "...",           // ein Satz, steht über dem Fortschrittsblock
  fussnote: "<p><b>Quellen:</b> …</p>",   // steht ganz unten, HTML erlaubt
  standard: { ziel: 20 },      // Tagespensum, wenn kein Plan etwas anderes sagt
  tagesplan: { "2026-10-01": { ziel: 30, kategorien: ["Puffer rechnen"] } },
  schemata: { titration: "<svg …>" },          // nur für die Übungsart svg
  tabellen:  { pks: { kopfspalte: "Säure", spalten: ["…", "…"] } },
  varianten: [ … ],            // optional, siehe unten
  umfaenge:  [ … ],            // optional, siehe unten
  aufgaben: [ … ]              // Liste oder Funktion, die eine Liste liefert
});
```

Die Seite baut **kein** eigenes Gerüst (kein `.container`, keine Überschrift): den
Titel zeigt die App aus dem Meta-Block, Untertitel und Fußnote kommen aus der
Konfiguration. In `<body>` stehen nur Merkkästen.

Reihenfolge der Einstellungen — die **spätere gewinnt**: `standard` → `tagesplan`
(Datum von heute) → Tagesplan der App → eigene Wahl im Filter. Alles über
`nurGesetzte()`, damit ein Plan mit nur `ziel` nicht die Kategorien mitlöscht.

### Die fünf Übungsarten

Jede Aufgabe braucht `id` (seitenweit eindeutig) und `art`, dazu in aller Regel
eine `kategorie` (ohne sie entfällt nur der Kategoriefilter). Optional
überall: `hinweis` (kleiner Vorabtipp) und `merke` (steht nach dem Prüfen unter dem
Ergebnis). Text darf HTML enthalten (`<sub>`, `&auml;` …) — der Motor escaped nur
Attributwerte. Kategorienamen möglichst als schlichter Text: sie landen zugleich in
der gespeicherten Filterwahl.

| Art | Feld | Was passiert |
|---|---|---|
| `karte` | `frage`, `antwort` | Karteikarte. Knopf heißt „Aufdecken", danach entscheidet er selbst „saß / saß nicht". |
| `rechnung` | `frage`, `felder[]`, `schritte[]` | Eingabefelder; nach dem Prüfen stehen Lösung und alle Zwischenschritte darunter. |
| `svg` | `schema` oder `svg`, `ziel`, `teil` | Er klickt ins Bild. Jedes anklickbare Element trägt `data-teil="…"`. Kein Prüfen-Knopf — der Klick *ist* die Antwort. |
| `tabelle` | `tabelle`, `kopf`, `zellen[]` | Eine Zeile einer Vergleichstabelle ausfüllen; Kopfzeile kommt aus `tabellen[…]`. |
| `wahl` | `frage`, `optionen[]`, `loesung` | Antwort anklicken, dann Prüfen. Statt `optionen` geht `ablenkerAus: "feld"` — dann nimmt der Motor die Werte dieses Feldes aus anderen Aufgaben der Seite als Ablenker (`anzahl`, Standard 4). |

`felder` und `zellen` nehmen je `{ loesung, alternativen[], einheit, label,
art: "text", toleranz }`. Ohne `art: "text"` wird als Zahl verglichen (Komma und
`3,98e-4` erlaubt); ohne `toleranz` wird auf die Stellen der Lösung gerundet,
mindestens auf zwei. Zahlen dürfen mit echtem Minus (−, auch – und —) oder
führendem Plus getippt werden: „−1" und „+2" zählen wie -1 und 2. Nicht-Zahlen als
`loesung` werden automatisch als Text verglichen. Bei Text wird klein geschrieben,
Umlaute werden aufgelöst, und zusätzlich gilt eine Antwort als richtig, wenn sie
ohne Bindestriche, Klammern und Leerzeichen gleich ist („Propan-2-ol" = „propan 2 ol").

### Varianten und Umfänge

**`varianten`** sind Abfragerichtungen über denselben Stoff (etwa Symbol → Name
und Name → Symbol). Jede ist `{ id, label, mix, bauen(it) }`: `bauen` gibt ein
Objekt zurück, dessen Felder die Aufgabe für diese Richtung überschreiben (oder
`null` = Aufgabe bleibt, wie sie ist). Die `id` der Aufgabe bleibt dabei immer
gleich — der Fortschritt zählt pro Stoff, nicht pro Richtung. Ab zwei Varianten
zeigt der Motor die Knöpfe plus „🔀 Gemischt"; `mix: false` hält eine Richtung
(etwa reines Karteikarten-Lernen) aus „Gemischt" heraus. Die Wahl merkt sich der
Motor unter `lern:<id>@v1-einstellungen`.

Trick: **eine einzige** Variante erzeugt keinen Knopf, ihr `bauen` läuft aber bei
jeder Aufgabe neu. So lassen sich Aufgaben bei jedem Drankommen frisch würfeln
(z. B. zufällige Salze in `chemie/redox/oxidationszahlen`), ohne dass sich ihre
`id` ändert.

**`umfaenge`** schränken ein, welcher Ausschnitt drankommt: `{ id, label,
gilt(it) }` — `gilt` sagt, ob eine Aufgabe zum Umfang gehört (z. B. „Elemente
1–18"). Knöpfe erscheinen ab zwei Umfängen. Ebenso erscheint der Kategoriefilter
nur, wenn es mehr als eine Kategorie gibt.

### Was der Motor von selbst tut

Fortschrittsblock mit Trefferquote und Wackelkandidaten · Balken · Filter nach
Kategorie und „Nur meine Wackelkandidaten" · „Fortschritt zurücksetzen" ·
Wackelkandidaten kommen in derselben Runde doppelt dran · Enter nach dem Vertrag
aus Kapitel 6 · Speichern nach Kapitel 2 und 3 · GIFs und Abschlussbildschirm nach
Kapitel 5. Die Seite muss davon **nichts** selbst bauen.

Alles, was die Seite sonst noch in `<body>` schreibt (Merkkästen `.box.merksatz`,
`.falle`, `.esel`, `.klinik`), rutscht automatisch unter die Übung.
Jeder Kasten mit einem `.box-title` als Kind lässt sich über den Titel zuklappen;
der Motor merkt sich zugeklappte Kästen je Seite (nach Titeltext), auch den
„★ Heute"-Kasten. `<details>`-Kästen (z. B. ein Spickzettel) bleiben unverändert.

### Selbstprüfung

Beim Start prüft der Motor den Bauplan der Seite: Meta-Block passt zu `id` und
`version`, jede Aufgabe hat eine eindeutige `id`, eine bekannte `art` und alle
Pflichtfelder ihrer Art (bei `wahl` enthält `optionen` die `loesung`, bei `svg`
gibt es das `data-teil`, bei `tabelle` passt die Zahl der `zellen` zu den
`spalten`) — und das für **jede** Variante, die `bauen` erzeugen kann.

Findet er etwas, steht oben auf der Seite ein roter Kasten „Diese Seite hat N
Baufehler" mit Liste und Knopf „Liste kopieren" (fertig formuliert, um sie einer
KI zurückzugeben). Die Übung läuft trotzdem, so gut es geht.

Für Agenten und Tests: `Lernseite.pruefen()` liefert dieselbe Liste — **leeres
Array = alles in Ordnung**. Jede neue Seite muss vor der Abgabe `[]` liefern.

## 9 — Import und Schutz

**Import.** Seiten müssen nicht mehr von Hand in den Ordner: „Ablage → Seite
importieren …", eine HTML-Datei ins Fenster oder auf die Seitenleiste ziehen, aufs
Dock-Symbol ziehen, oder „Ablage → Seite aus Zwischenablage einfügen" (Chat-Text
und ```-Zäune um die Seite werden abgeschnitten). Die App legt die Seite nach
ihrer `lernkiste-id` unter `Seiten/<Fach>/<Thema>/<slug>.html` ab; vorhandene
Ordner werden unabhängig von Groß-/Kleinschreibung und Umlaut-Schreibweise
wiedergefunden. Gibt es die `id` schon, fragt die App und verschiebt die alte
Fassung nach `~/Documents/Lernkiste/_archiv/<Zeitstempel>-import/` — gelöscht wird
nie. Seiten ohne Kennung: die App fragt nach Fach und Thema.

**Bauanleitung für andere KIs.** „Ablage → Bauanleitung für eine KI kopieren"
legt `Ressourcen/ki-vorlage.md` in die Zwischenablage: eine eigenständige,
neutrale Kurzfassung dieses Vertrags mit Beispielseite. Wer den Vertrag ändert,
passt die Vorlage mit an.

**Schutz.** Alle Seiten teilen sich einen Ursprung und damit einen Speicher —
eine fremde Seite könnte also fremden Fortschritt lesen. Deshalb:
- Der Server schickt zu jeder HTML-Seite eine Content-Security-Policy: nichts aus
  dem Netz laden, nichts dorthin senden, keine Formulare (`Server.schutz`).
- Das Fenster lässt nur Navigation innerhalb der Lernkiste zu. Links ins Netz
  öffnen erst nach Rückfrage im normalen Browser; alles, was eine Seite ungefragt
  ansteuert, wird verworfen.
