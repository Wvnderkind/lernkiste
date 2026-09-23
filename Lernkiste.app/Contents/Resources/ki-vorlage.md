# Bauanleitung: Lernseite für die Lernkiste

Du baust eine **Lernseite** für die Mac-App „Lernkiste". Eine Lernseite ist eine
einzelne HTML-Datei, die nur **Stoff** enthält: ein paar Merkkästen und eine Liste
von Aufgaben. Das ganze Übungsverhalten (Fortschritt speichern, Tagespensum,
Wiederholung wackliger Aufgaben, Enter-Steuerung, Abschlussbildschirm, hell/dunkel)
liefert der **Motor** der App. Du schreibst davon nichts selbst.

Halte dich genau an diese Anleitung. Die App prüft jede Seite beim Öffnen; Fehler
erscheinen als roter Kasten oben auf der Seite (siehe ganz unten).

---

## 1 · Ausgabe

- Gib **genau eine vollständige HTML-Datei** aus, in **einem** Codeblock, von
  `<!DOCTYPE html>` bis `</html>`. Nichts abkürzen, keine „…"-Platzhalter.
- Erklärungen, falls nötig, **außerhalb** des Codeblocks und kurz.
- Die Person kopiert deine Antwort und wählt in der App
  „Ablage → Seite aus Zwischenablage einfügen". Die App legt die Seite selbst ab.

## 2 · Gerüst (Pflicht, genau so)

```html
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="lernkiste-id"      content="FACH/THEMA/SLUG">
<meta name="lernkiste-titel"   content="Lesbarer Titel">
<meta name="lernkiste-typ"     content="drill">
<meta name="lernkiste-version" content="1">
<title>Lesbarer Titel</title>
<link rel="stylesheet" href="../../_motor/lernkiste.css">
<script src="../../_motor/lernkiste.js"></script>
</head>
<body>
  <!-- nur Merkkästen, siehe 4 -->
<script>
Lernseite.start({ /* siehe 3 */ });
</script>
</body>
</html>
```

- **`lernkiste-id`** = `fach/thema/slug`: nur Kleinbuchstaben, Ziffern und Bindestriche,
  Umlaute als ae/oe/ue/ss. Beispiel: `biologie/zelle/zellorganellen`. Daraus legt die
  App die Ordner an (Fach „Biologie", Thema „Zelle"). Gleiche id = gleiche Seite:
  eine neue Fassung ersetzt die alte, die alte wird archiviert.
- **`lernkiste-typ`**: einer von `drill`, `tabelle`, `schema`, `zuordnung`,
  `mechanismus`, `kompendium`.
- **`lernkiste-version`**: bei 1 anfangen. Nur erhöhen, wenn sich Aufgaben-ids
  ändern — dann beginnt der gespeicherte Lernstand von vorn.
- Die beiden Motor-Zeilen (`../../_motor/…`) **wörtlich** übernehmen.
- **Keine** große Überschrift und **kein** eigenes Seitengerüst: den Titel zeigt die App.

## 3 · `Lernseite.start({...})`

Genau **ein** Aufruf am Ende der Seite:

```js
Lernseite.start({
  id: "biologie/zelle/zellorganellen",   // exakt wie im Meta-Tag
  version: 1,                            // exakt wie im Meta-Tag
  untertitel: "Ein Satz, worum es geht.",
  fussnote: "<p><b>Quellen:</b> …</p>",  // optional, steht ganz unten
  standard: { ziel: 15 },                // Aufgaben pro Tag
  aufgaben: [ /* siehe unten */ ]
});
```

Weitere optionale Felder: `schemata` (für `svg`), `tabellen` (für `tabelle`),
`varianten`, `umfaenge` (siehe 5).

### Aufgaben

Jede Aufgabe hat eine **seitenweit eindeutige, feste `id`** (z. B. `"mito-funktion"`),
eine `art` und am besten eine `kategorie` (kurzer Text; ab zwei Kategorien erscheint
ein Filter). Optional überall: `hinweis` (kleiner Tipp vorab) und `merke` (erscheint
nach dem Prüfen). Texte dürfen einfaches HTML enthalten (`<b>`, `<sub>`, `<sup>`).

| art | Pflichtfelder | Verhalten |
|---|---|---|
| `karte` | `frage`, `antwort` | Karteikarte: aufdecken, dann „saß / saß nicht". |
| `wahl` | `frage`, `loesung`, `optionen[]` **oder** `ablenkerAus` | Eine Antwort anklicken. `optionen` muss die `loesung` enthalten und mind. 2 Einträge haben. Mit `ablenkerAus: "loesung"` nimmt der Motor falsche Antworten aus den anderen Aufgaben der Seite. |
| `rechnung` | `frage`, `felder[]` | Eingabefelder, jedes mit `loesung`. Optional `schritte[]` = Rechenweg, der nach dem Prüfen erscheint. |
| `tabelle` | `tabelle`, `kopf`, `zellen[]` | Eine Zeile einer Tabelle ausfüllen. `tabelle` verweist auf `tabellen: { name: { kopfspalte: "…", spalten: ["…","…"] } }`; `zellen` hat genauso viele Einträge wie `spalten`, jeder mit `loesung`. |
| `svg` | `schema` (oder `svg`), `teil`, `ziel` | In ein Bild klicken. Das SVG steht in `schemata: { name: "<svg …>" }`; jedes anklickbare Element trägt `data-teil="…"`, und `teil` muss darin vorkommen. `ziel` = was gesucht ist. |

Felder in `felder[]` und `zellen[]`: `{ loesung, alternativen: [], einheit, label,
art: "text", toleranz }`. Ohne `art: "text"` wird als Zahl verglichen (Komma erlaubt).
Bei Text sind Groß-/Kleinschreibung, Umlaut-Schreibweise, Bindestriche und
Leerzeichen egal.

## 4 · Merkkästen (optional, im `<body>`)

```html
<div class="box merksatz">
  <div class="box-title">★ Merksatz</div>
  Kernaussage in zwei, drei Sätzen.
</div>
```

Klassen: `merksatz` (Kernwissen), `falle` (typischer Fehler), `esel` (Eselsbrücke),
`klinik` (Praxisbezug). Sie erscheinen automatisch unter der Übung.

## 5 · Fortgeschritten (nur wenn sinnvoll)

- **`varianten`**: Abfragerichtungen über denselben Stoff, z. B. Begriff → Erklärung
  und Erklärung → Begriff. Jede ist `{ id, label, bauen: function (it) { return {…} } }`;
  `bauen` liefert die Felder, die für diese Richtung anders sind. Die Aufgaben-id bleibt gleich.
- **`umfaenge`**: Ausschnitte des Stoffs, `{ id, label, gilt: function (it) { return true/false } }`.

## 6 · Verboten

- Jeder Netzzugriff: keine CDNs, keine externen Schriften, Bilder, Skripte, kein `fetch`
  nach außen. Die App blockiert das ohnehin — die Seite wäre dann kaputt.
- `alert()`, `confirm()`, `prompt()`, `window.open()`, `location.href = …`.
- Eigene Farben außerhalb der vorgegebenen Variablen (`var(--accent)`, `var(--ok)`,
  `var(--no)`, `var(--text)`, `var(--line)` …). Eigenes CSS nur für Kleinigkeiten.
- Eigener Fortschritt, eigene Knöpfe für Zurücksetzen oder Download, eigener
  Hell/Dunkel-Schalter — das macht alles der Motor.

## 7 · Inhalt

- Fachlich korrekt. Was du nicht sicher weißt, lässt du weg, statt zu raten.
- Lieber 20 gute Aufgaben als 60 dünne. Jede Aufgabe prüft **eine** Sache.
- `merke` nutzen, um das *Warum* hinter der Antwort in einem Satz zu erklären.

## 8 · Wenn die App einen roten Kasten zeigt

Oben auf der Seite steht dann „Diese Seite hat N Baufehler" mit einer Liste. Die
Person drückt „Liste kopieren" und gibt dir die Liste. Dann: **alle** genannten
Fehler beheben und die **ganze** Seite erneut ausgeben — gleiche `lernkiste-id`,
gleiche Aufgaben-ids, damit der Lernstand erhalten bleibt.

---

## Beispielseite (vollständig)

```html
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="lernkiste-id"      content="biologie/zelle/zellorganellen">
<meta name="lernkiste-titel"   content="Zellorganellen und ihre Aufgaben">
<meta name="lernkiste-typ"     content="drill">
<meta name="lernkiste-version" content="1">
<title>Zellorganellen und ihre Aufgaben</title>
<link rel="stylesheet" href="../../_motor/lernkiste.css">
<script src="../../_motor/lernkiste.js"></script>
</head>
<body>

  <div class="box merksatz">
    <div class="box-title">★ Merksatz</div>
    Membranumschlossene Organellen teilen die Zelle in Reaktionsräume: Jedes Organell
    schafft die Bedingungen für seine eigene Chemie.
  </div>

  <div class="box falle">
    <div class="box-title">⚠ Typischer Fehler</div>
    Ribosomen sind <b>keine</b> membranumschlossenen Organellen — sie kommen auch bei
    Bakterien vor.
  </div>

<script>
Lernseite.start({
  id: "biologie/zelle/zellorganellen",
  version: 1,
  untertitel: "Welches Organell macht was? Karten, Auswahl und eine Tabelle.",
  fussnote: "<p><b>Quelle:</b> gängige Lehrbücher der Zellbiologie.</p>",
  standard: { ziel: 10 },
  tabellen: {
    membran: { kopfspalte: "Organell", spalten: ["Anzahl Membranen", "eigene DNA (ja/nein)"] }
  },
  aufgaben: [
    { id: "mito-funktion", art: "karte", kategorie: "Funktion",
      frage: "Wofür ist das Mitochondrium vor allem zuständig?",
      antwort: "Zellatmung: Bildung von ATP über die Atmungskette.",
      merke: "Deshalb haben Muskel- und Nervenzellen besonders viele Mitochondrien." },
    { id: "lyso-funktion", art: "karte", kategorie: "Funktion",
      frage: "Was geschieht in Lysosomen?",
      antwort: "Abbau von Makromolekülen durch saure Hydrolasen." },
    { id: "wahl-proteinsynthese", art: "wahl", kategorie: "Zuordnung",
      frage: "Wo werden Proteine für den Export synthetisiert?",
      loesung: "raues ER",
      optionen: ["raues ER", "glattes ER", "Golgi-Apparat", "Peroxisom"] },
    { id: "wahl-lipide", art: "wahl", kategorie: "Zuordnung",
      frage: "Wo entstehen Membranlipide und Steroide?",
      loesung: "glattes ER",
      optionen: ["glattes ER", "raues ER", "Lysosom", "Zellkern"] },
    { id: "rechnung-atp", art: "rechnung", kategorie: "Rechnen",
      frage: "Eine Zelle verbraucht 2 × 10<sup>7</sup> ATP pro Sekunde. Wie viele sind das pro Minute?",
      felder: [{ loesung: 1.2e9, label: "ATP pro Minute" }],
      schritte: ["2 × 10<sup>7</sup> × 60 = 1,2 × 10<sup>9</sup>"] },
    { id: "tab-mito", art: "tabelle", kategorie: "Tabelle", tabelle: "membran",
      kopf: "Mitochondrium",
      zellen: [{ loesung: 2 }, { loesung: "ja", art: "text" }] },
    { id: "tab-lyso", art: "tabelle", kategorie: "Tabelle", tabelle: "membran",
      kopf: "Lysosom",
      zellen: [{ loesung: 1 }, { loesung: "nein", art: "text" }] }
  ]
});
</script>
</body>
</html>
```
