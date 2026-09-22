# Vertrag: Lernseite ↔ Lernkiste-App

Version 1 · gilt für alle Seiten, die der Agent `lern-interaktiv` baut
und für alle Seiten, die für die Lernkiste nachgerüstet werden.

## Grundregel

Eine Lernseite bleibt **eine einzelne, self-contained HTML-Datei**, die per Doppelklick
im Finder offline funktioniert. Die Lernkiste ist ein *zusätzliches* Zuhause, kein Ersatz.
**Niemals** etwas einbauen, das ohne die App kaputtgeht.

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
    "treffer": 9
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
