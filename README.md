# Lernkiste

Eine kleine App für Mac und Windows, die alle eigenen HTML-Lernseiten an einem Ort sammelt: aufmachen,
Seite anklicken, lernen. Kein Browser, kein Suchen in Ordnern, kein Chaos aus Tabs.
Der Lernstand jeder Seite wird automatisch gesichert, und die Startseite zeigt,
was heute dran ist und was noch wackelt.

Die Lernseiten selbst baut **Claude Code**. Was Claude dafür braucht, liegt in
diesem Ordner mit dabei — es muss also niemand etwas von Grund auf entwickeln.

> Läuft auf dem Mac und unter Windows 10/11 (für Windows siehe [unten](#windows)).
> Kein Internet nötig, es wird nichts hochgeladen: alles bleibt in
> `~/Documents/Lernkiste/` (Windows: `Dokumente\Lernkiste\`).

---

## 1. Herunterladen

Oben auf dieser Seite auf den grünen Knopf **`Code`** klicken → **Download ZIP**.
Die geladene Datei im Downloads-Ordner doppelklicken, damit sie entpackt wird.

## 2. Installieren

Im entpackten Ordner liegt die Datei **`Installieren.command`**.

macOS lässt die Datei beim Doppelklick nicht einfach starten, weil sie von keinem
bezahlten Apple-Entwicklerkonto signiert ist. Es erscheint dann **„Installieren.command“
nicht geöffnet**. Dort auf **Fertig** klicken, **nicht** auf „In den Papierkorb legen“.
Seit macOS 15 (Sequoia) hilft auch **Rechtsklick → Öffnen** nicht mehr. So geht es:

**Weg 1 – über das Terminal (am schnellsten):**

1. Terminal öffnen: **⌘ + Leertaste**, `Terminal` eintippen, Enter.
2. `bash` und **ein Leerzeichen** eintippen, aber noch nicht Enter drücken.
3. Die Datei `Installieren.command` aus dem Finder ins Terminal-Fenster ziehen. Dann
   steht dort ihr Pfad.
4. Enter drücken.

Liegt der Ordner unter seinem üblichen Namen in den Downloads, reicht auch:

```bash
bash ~/Downloads/lernkiste-main/Installieren.command
```

Mit `bash` davor wird die Datei direkt ausgeführt, ohne dass macOS sie blockiert.
Mit `open` im Terminal oder per Doppelklick blockiert macOS sie weiterhin.

**Weg 2 – über die Systemeinstellungen:**

1. `Installieren.command` einmal doppelklicken und im Hinweis auf **Fertig** klicken.
2. **Systemeinstellungen → Datenschutz & Sicherheit** öffnen und ganz nach unten
   scrollen. Dort steht *„Installieren.command“ wurde blockiert*, daneben der Knopf
   **Dennoch öffnen**.
3. Auf den Knopf klicken und das Mac-Passwort eingeben. Danach die Datei noch einmal
   doppelklicken und **Dennoch öffnen** wählen.

Das ist nur einmal nötig. Das Skript nimmt der App selbst die Download-Sperre ab, sie
startet danach ganz normal.

Das Skript gibt im Terminal ein paar Zeilen aus und startet die App danach. Es legt ab:

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

**Seiten an andere weitergeben:** In der linken Leiste mit der rechten Maustaste auf
eine Seite, ein Thema oder ein ganzes Fach klicken → **… teilen …**. Es öffnet sich
das Teilen-Menü von macOS (AirDrop, Nachrichten, Mail …). Die offene Seite geht auch
über **Ablage → Seite teilen …** (⌘E). Eine einzelne Seite kommt als `.html`-Datei an,
ein Thema oder Fach als ZIP-Paket. Der Empfänger zieht die Datei einfach in seine
Lernkiste-Leiste oder wählt **Ablage → Seite importieren …**. Die Seiten landen dann
von selbst im richtigen Fach und Thema. Dein Lernstand geht dabei nicht mit.

**Was ist neu?** Das kleine **ⓘ** oben rechts neben dem Hell/Dunkel-Schalter bekommt
nach einem Update einen roten Punkt. Ein Klick zeigt, was sich geändert hat.

**Die App frischt sich selbst auf** — alle 30 Minuten, kurz nach Mitternacht und wenn
man ins Fenster zurückkommt: Neue Seiten erscheinen in der Leiste, der Gruß wechselt,
die Haken vom Vortag verschwinden.

**Nach der Installation** erklärt die Startseite die ersten Schritte. Der Kasten
verschwindet, sobald die erste eigene Seite da ist (oder mit dem ×).

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
| `windows/` | der Quelltext der Windows-Fassung (den Installer baut GitHub) |

## Häufige Fragen

**„…“ nicht geöffnet – Apple konnte nicht überprüfen, ob … frei von Schadsoftware ist.**
Das ist die Download-Sperre von macOS. Auf **Fertig** klicken, nicht auf „In den
Papierkorb legen“, und dann `Installieren.command` wie in [Schritt 2](#2-installieren)
beschrieben über das Terminal (`bash` + Datei ins Fenster ziehen) oder über
**Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen** starten. Meldet sich
die App selbst so, `Installieren.command` einfach noch einmal ausführen. Es nimmt die
Sperre ab.

**„Die App zeigt keine Lernseiten."**
Entweder liegt noch keine im Ordner, oder sie liegt an der falschen Stelle. Richtig ist
`~/Documents/Lernkiste/Seiten/<Fach>/<Thema>/<name>.html`. Über **Ablage → Ordner mit
den Lernseiten öffnen** kommt man direkt hin, danach ⌘R.

**„Gehen meine Fortschritte verloren, wenn ich Ordner umbenenne?"**
Nein. Der Lernstand hängt an der App, nicht am Dateipfad.

**„Kann ich die Seiten auch ohne die App öffnen?"**
Ja. Jede Lernseite ist eine einzelne HTML-Datei und funktioniert per Doppelklick auch
im Browser — nur ohne Startseite, Tagesplan und Fortschrittsübersicht.

**„Wie wiederhole ich gezielt, was nicht sitzt?"**
Jede Aufgabe hat ihr eigenes Wiederholungsdatum: Richtiges ruht immer länger (1, 3, 7,
16, 35 Tage), Falsches ist morgen wieder dran. Steht in `konfiguration.json` unter
`naechsterTermin` eine Prüfung, kommt vorher alles noch einmal. Auf der Startseite steht
je Fach **Fehlerkiste & Probeklausur**: *Fällige üben* und *Wackler üben* mischen die
Aufgaben aller Seiten des Fachs, die *Probeklausur* zieht 20, 40 oder 60 Fragen, wahlweise
mit Uhr, und zeigt die Lösungen erst am Ende als Tabelle.

**„Eine Aufgabe ist falsch. Was tun?"**
Unter der Aufgabe auf **⚑ Melden** klicken und kurz schreiben, was nicht stimmt. Die
Meldung landet in `Lernkiste/meldungen.json`, die Startseite zählt die offenen. Claude
arbeitet sie ab, wenn man sagt: „schau die Meldungen durch".

**„Wie kommt eine neue Fassung der App auf meinen Rechner?"**
Von selbst. Die App sieht beim Start nach, ob es auf GitHub eine neuere Fassung gibt.
Wenn ja, erscheint oben rechts der Knopf **Update verfügbar**. Ein Klick, einmal
bestätigen: Die App lädt die neue Fassung, tauscht sich aus und startet neu. Die alte
Fassung wandert in den Papierkorb, die Lernseiten und der Fortschritt bleiben
unangetastet. Von Hand geht es über **Lernkiste → Nach Updates suchen …**.

Danach kann macOS noch einmal nach dem Zugriff auf **Dokumente** fragen — einfach
erlauben. Das liegt an der kostenlosen Signatur.

Klappt das Update nicht (etwa weil die App nicht im Programme-Ordner liegt): ZIP erneut
herunterladen und `Installieren.command` wieder ausführen. Was schiefging, steht in
`~/Library/Logs/Lernkiste-Update.log`.

---

## Windows

Für Windows 10 und 11 gibt es eine eigene Fassung mit Installer.

1. **Herunterladen:** Auf GitHub rechts auf **Releases** klicken (oder direkt
   [github.com/Wvnderkind/lernkiste/releases/latest](https://github.com/Wvnderkind/lernkiste/releases/latest))
   und die Datei **`Lernkiste_…_x64-setup.exe`** laden.
2. **Installieren:** Die Datei doppelklicken. Weil der Installer von keinem bezahlten
   Zertifikat signiert ist, meldet sich Windows mit **„Windows hat den PC geschützt“**.
   Dann auf **Weitere Informationen** und danach auf **Trotzdem ausführen** klicken.
   Der Installer braucht keine Administratorrechte; die Lernkiste landet im
   Startmenü.
3. **Lernseiten** wohnen in `Dokumente\Lernkiste\Seiten\<Fach>\<Thema>\`. Beim
   ersten Start liegt dort schon die Beispielseite. Über **Datei → Ordner mit den
   Lernseiten öffnen** kommt man direkt hin.

Alles andere funktioniert wie auf dem Mac — mit **Strg** statt ⌘ und dem Menü
**Datei** statt **Ablage**: Seiten importieren (Strg+O), in die Leiste ziehen, aus der
Zwischenablage einfügen (Strg+Umschalt+V), eine `.html`-Datei per Rechtsklick →
**Öffnen mit → Lernkiste** hineinholen. ZIP-Pakete, die jemand am Mac mit **Teilen**
verschickt hat, lassen sich genauso importieren oder in die Leiste ziehen.

**Seiten weitergeben:** In der Leiste mit der rechten Maustaste auf eine Seite, ein
Thema oder ein Fach klicken → **… exportieren …** und einen Speicherort wählen (die
offene Seite geht auch über **Datei → Seite exportieren …**, Strg+E). Eine Seite wird
eine `.html`-Datei, ein Thema oder Fach ein ZIP-Paket — das kann man per Mail,
WhatsApp oder USB-Stick weitergeben. Der Lernstand bleibt bei dir.

**Updates kommen von selbst.** Gibt es eine neue Fassung, erscheint oben rechts der
Knopf **Update verfügbar**. Ein Klick, **Jetzt aktualisieren** — die Lernkiste lädt
die neue Fassung, installiert sie und startet neu. Lernseiten und Fortschritt bleiben
erhalten. Von Hand geht es über **Hilfe → Nach Updates suchen …**.

Wenn etwas nicht klappt, hilft das Protokoll unter
`%LOCALAPPDATA%\de.lernkiste.app\logs\Lernkiste.log` (in die Adresszeile des
Explorers einfügen).
