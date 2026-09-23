# Lernkiste

Eine kleine Mac-App, die alle eigenen HTML-Lernseiten an einem Ort sammelt: aufmachen,
Seite anklicken, lernen. Kein Browser, kein Suchen in Ordnern, kein Chaos aus Tabs.
Der Lernstand jeder Seite wird automatisch gesichert, und die Startseite zeigt,
was heute dran ist und was noch wackelt.

Die Lernseiten selbst baut **Claude Code**. Was Claude dafür braucht, liegt in
diesem Ordner mit dabei — es muss also niemand etwas von Grund auf entwickeln.

> Läuft nur auf einem Mac. Kein Internet nötig, es wird nichts hochgeladen:
> alles bleibt in `~/Documents/Lernkiste/`.

---

## 1. Herunterladen

Oben auf dieser Seite auf den grünen Knopf **`Code`** klicken → **Download ZIP**.
Die geladene Datei im Downloads-Ordner doppelklicken, damit sie entpackt wird.

## 2. Installieren

Im entpackten Ordner liegt die Datei **`Installieren.command`**.

**Wichtig:** nicht normal doppelklicken, sondern **Rechtsklick → Öffnen**, und im
Fenster danach noch einmal auf **Öffnen**. Das ist einmalig nötig, weil die App von
keinem bezahlten Apple-Entwicklerkonto signiert ist — macOS ist bei allem misstrauisch,
was aus dem Internet kommt.

Es öffnet sich ein Terminal-Fenster, das ein paar Zeilen ausgibt und die App danach
startet. Es legt ab:

- `Lernkiste.app` → im Programme-Ordner
- `~/Documents/Lernkiste/Seiten/` → hier wohnen die Lernseiten
- eine Beispielseite zum Ausprobieren

Beim ersten Start fragt macOS einmal nach dem Zugriff auf den Ordner **Dokumente** —
das muss erlaubt werden, sonst findet die App die Lernseiten nicht.

## 3. Claude einrichten

Claude Code öffnen (im Terminal `claude`, oder die Claude-App) und diesen Satz
hineinkopieren — den Pfad an den eigenen anpassen:

```
Lies ~/Downloads/lernkiste-main/Fuer-Claude/START-HIER.md und richte alles ein, was dort steht.
```

Claude legt dann den Agenten, den Bauplan und die Fachprofile an ihren Platz. Danach
genügen Sätze wie:

```
Bau mir eine interaktive Lernseite zum Citratzyklus.
```

Die fertige Seite landet automatisch in der App. Dort einmal **Ablage → Seiten neu
einlesen** (⌘R) drücken, dann steht sie auf der Startseite.

## 4. Seiten von einer anderen KI (ChatGPT, Gemini …)

Claude Code ist nicht Pflicht. In der App **Ablage → Bauanleitung für eine KI kopieren**
wählen, die Anleitung in den Chat der KI einfügen und dazuschreiben, welches Thema
die Seite haben soll. Die Antwort der KI komplett kopieren und in der App
**Ablage → Seite aus Zwischenablage einfügen** (⇧⌘V) wählen — die App sucht die
HTML-Datei aus dem Text heraus und sortiert sie selbst in Fach und Thema ein.

Andere Wege, eine fertige Seite hineinzubekommen:

- **Ablage → Seite importieren …** (⌘O)
- die `.html`-Datei in die linke Leiste der App ziehen
- die Datei auf das Lernkiste-Symbol im Dock ziehen

Gibt es schon eine Seite mit derselben Kennung, fragt die App nach; die alte Fassung
wird nicht gelöscht, sondern unter `~/Documents/Lernkiste/_archiv/` aufgehoben.

**Roter Kasten oben auf einer Seite?** Dann hat die Seite Baufehler. Auf
**Liste kopieren** drücken, die Liste der KI geben und um eine korrigierte Fassung
bitten, danach wieder einfügen.

> Lernseiten dürfen nichts aus dem Internet nachladen und keine fremden Webseiten
> öffnen — die App blockiert das. Links nach draußen öffnen sich erst nach Rückfrage
> im normalen Browser.

---

## Was im Ordner liegt

| | |
|---|---|
| `Lernkiste.app` | die fertige App — muss nicht gebaut werden |
| `Installieren.command` | der Doppelklick-Helfer aus Schritt 2 |
| `Fuer-Claude/START-HIER.md` | die Einrichtungsanleitung für Claude |
| `Fuer-Claude/SPEC-Lernseiten.md` | der Bauplan: woran sich jede Lernseite halten muss |
| `Fuer-Claude/lern-interaktiv.md` | der Agent, der die Seiten baut |
| `Fuer-Claude/faecher/` | Fachprofile für Biochemie und Physiologie als Muster |
| `Beispiel/` | eine fertige Lernseite (Aminosäuren) als Vorlage |
| `Quelle/`, `bauen.sh` | der Quelltext der App, falls jemand selbst daran bauen will |

## Häufige Fragen

**„Die App lässt sich nicht öffnen, sie stammt von einem nicht verifizierten Entwickler."**
Rechtsklick auf die App → **Öffnen** → im Fenster noch einmal **Öffnen**. Nur beim
ersten Mal nötig.

**„Die App zeigt keine Lernseiten."**
Entweder liegt noch keine im Ordner, oder sie liegt an der falschen Stelle. Richtig ist
`~/Documents/Lernkiste/Seiten/<Fach>/<Thema>/<name>.html`. Über **Ablage → Ordner mit
den Lernseiten öffnen** kommt man direkt hin, danach ⌘R.

**„Gehen meine Fortschritte verloren, wenn ich Ordner umbenenne?"**
Nein. Der Lernstand hängt an der App, nicht am Dateipfad.

**„Kann ich die Seiten auch ohne die App öffnen?"**
Ja. Jede Lernseite ist eine einzelne HTML-Datei und funktioniert per Doppelklick auch
im Browser — nur ohne Startseite, Tagesplan und Fortschrittsübersicht.

**„Wie kommt eine neue Fassung der App auf meinen Rechner?"**
ZIP erneut herunterladen und `Installieren.command` wieder ausführen. Die alte Fassung
wandert in den Papierkorb, die Lernseiten und der Fortschritt bleiben unangetastet.
