# Einrichtung der Lernkiste — Anleitung für Claude Code

Du richtest gerade die **Lernkiste** ein: eine kleine Mac-App, in der interaktive
HTML-Lernseiten gesammelt und geöffnet werden. Die App ist fertig und muss **nicht**
gebaut werden. Deine Aufgabe ist die Zulieferung: Agent, Fachprofile, Bauplan — und
danach die Lernseiten selbst.

Diese Datei liegt im heruntergeladenen Ordner unter `Fuer-Claude/`. Alle Pfade unten
sind relativ zu diesem Ordner; nenne ihn im Folgenden `$PAKET`.

---

## Schritt 1 — Dateien an ihren Platz legen

```bash
# $PAKET durch den Pfad des heruntergeladenen Ordners ersetzen,
# z. B. ~/Downloads/lernkiste-main
PAKET=~/Downloads/lernkiste-main

mkdir -p ~/.claude/agents
mkdir -p ~/.claude/lernsystem/faecher/biochemie
mkdir -p ~/.claude/lernsystem/faecher/physiologie
mkdir -p ~/Documents/Lernkiste/Seiten

cp "$PAKET/Fuer-Claude/lern-interaktiv.md"        ~/.claude/agents/
cp "$PAKET/Fuer-Claude/SPEC-Lernseiten.md"        ~/Documents/Lernkiste/
cp "$PAKET/Fuer-Claude/faecher/biochemie.md"      ~/.claude/lernsystem/faecher/biochemie/fach.md
cp "$PAKET/Fuer-Claude/faecher/physiologie.md"    ~/.claude/lernsystem/faecher/physiologie/fach.md
cp -R "$PAKET/Beispiel/"*                          ~/Documents/Lernkiste/Seiten/
```

Danach existiert:

| Datei | wofür |
|---|---|
| `~/.claude/agents/lern-interaktiv.md` | der Agent, der die Lernseiten baut |
| `~/Documents/Lernkiste/SPEC-Lernseiten.md` | der **Bauplan** — der Vertrag zwischen Seiten und App |
| `~/.claude/lernsystem/faecher/<fach>/fach.md` | pro Fach: Prüfungsformat, Quellpfade, Themengebiete |
| `~/Documents/Lernkiste/Seiten/Biochemie/Aminosaeuren/…html` | eine fertige Beispielseite als Vorlage |

## Schritt 2 — Fachprofil ausfüllen

Frage nach, bevor du die erste eigene Seite baust, und trage die Antworten in
`~/.claude/lernsystem/faecher/<fach>/fach.md` ein:

- Welches Fach, welcher Prüfungstermin?
- Prüfungsformat: Single Choice, Freitext, mündlich — und in welchem Verhältnis?
- Wo liegt das eigene Material (Vorlesungsfolien, Altklausuren, Skripte)?

Für ein neues Fach legst du ein Profil nach dem Muster von `biochemie.md` an.

## Schritt 3 — Lernseiten bauen

Ab jetzt gilt: **Lies `~/Documents/Lernkiste/SPEC-Lernseiten.md`, bevor du eine Seite
baust.** Der Bauplan ist verbindlich; bei Widerspruch gewinnt er gegen alles andere.

Die drei Punkte, an denen es am häufigsten hakt:

1. **Ablageort.** Jede Seite gehört nach
   `~/Documents/Lernkiste/Seiten/<Fach>/<Themengebiet>/<name>.html`.
   Nur von dort liest die App. Nirgendwo sonst.
2. **Meta-Block im `<head>`.** Ohne `lernkiste-id`, `lernkiste-titel`, `lernkiste-typ`
   und `lernkiste-version` taucht die Seite in der App nicht auf. Die `id` muss zum
   Ablageort passen, kleingeschrieben und ohne Umlaute.
3. **Der Motor.** Jede Seite bindet `../../_motor/lernkiste.css` und
   `../../_motor/lernkiste.js` ein und ruft einmal `Lernseite.start({...})` auf.
   Fortschritt, Tagespensum, Wiederholung und Abschlussbildschirm liefert der Motor —
   die Seite enthält nur Stoff. Kein eigenes localStorage, kein Export-Knopf.

Die Beispielseite `Seiten/Biochemie/Aminosaeuren/aminosaeuren-grundlagen.html` erfüllt
den Bauplan vollständig — **nimm sie als Vorlage**, statt eine Seite von Null zu
schreiben. Sie zeigt vier der fünf Übungsarten (`wahl` mit drei Abfragerichtungen über
`varianten`, `rechnung`, `tabelle`, `svg`) und die vier Merkkasten-Sorten.
`karte` fehlt dort; wie sie aussieht, steht im Bauplan.

Vor der Abgabe: Seite im Browser öffnen, `Lernseite.pruefen()` muss `[]` liefern —
sonst steht oben ein roter Kasten mit den Baufehlern.

Nach jeder fertigen Seite in der App **Ablage → Seiten neu einlesen** (⌘R) — dann
steht sie auf der Startseite.

## Schritt 4 — Prüfen, bevor du abgibst

Der Agent beschreibt das ausführlich. Das Wichtigste in einem Satz: **Eine Seite
anschauen reicht nicht — spiel die Kernschleife einmal durch**, einmal richtig und
einmal absichtlich falsch antworten. Die gefährlichen Fehler schlagen erst beim Klick
zu, und Layout und Konsole sehen beim Laden trotzdem sauber aus.

---

## Hinweise

- Der Agent steht auf `model: sonnet`. Für aufwendige Seiten (große SVG-Schemata)
  lohnt sich `model: opus` — einfach in der ersten Zeile von
  `~/.claude/agents/lern-interaktiv.md` ändern.
- Die App braucht **kein** Internet und schickt nichts weg. Alles liegt in
  `~/Documents/Lernkiste/`.
- Der Fortschritt hängt an der App, nicht am Dateipfad: Ordner umbenennen oder
  verschieben kostet keinen Lernstand.
- Die App liest den Ordner bei jedem Start neu ein; sie muss nie neu gebaut werden.
