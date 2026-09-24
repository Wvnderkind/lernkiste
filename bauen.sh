#!/bin/bash
# Baut aus den Swift-Dateien die fertige Lernkiste.app.
set -e
cd "$(dirname "$0")"

APP="Lernkiste.app"
ZIEL="$APP/Contents"

echo "→ altes Bundle aufräumen"
rm -rf "$APP"
mkdir -p "$ZIEL/MacOS" "$ZIEL/Resources"

echo "→ Swift übersetzen"
swiftc -O -o "$ZIEL/MacOS/Lernkiste" \
  Quelle/Modell.swift Quelle/Server.swift Quelle/Fortschritt.swift \
  Quelle/Startseite.swift Quelle/Fenster.swift Quelle/Import.swift Quelle/Export.swift Quelle/Neuigkeiten.swift Quelle/Updater.swift \
  Quelle/main.swift

echo "→ Ressourcen kopieren"
cp Ressourcen/tokens.css "$ZIEL/Resources/"
# Der gemeinsame Motor der Lernseiten. Er liegt hier im Programm und wird
# beim Start nach Seiten/_motor/ gespiegelt — so hat jede Lernseite denselben
# Stand, egal wer die App installiert.
cp Ressourcen/lernkiste.js Ressourcen/lernkiste.css "$ZIEL/Resources/"
# Bauanleitung, die man einer beliebigen KI in den Chat gibt (Menue Ablage).
cp Ressourcen/ki-vorlage.md "$ZIEL/Resources/"
cp Ressourcen/neuigkeiten.json "$ZIEL/Resources/"
# Die Beispielseite legt die App beim allerersten Start in den leeren Seiten-Ordner.
cp Beispiel/Biochemie/Aminosaeuren/aminosaeuren-grundlagen.html "$ZIEL/Resources/"
[ -f Ressourcen/Lernkiste.icns ] && cp Ressourcen/Lernkiste.icns "$ZIEL/Resources/"

# Der Stand (Datum + Uhrzeit der Veroeffentlichung) steht in der Datei STAND.
# Die App vergleicht ihn mit dem Stand auf GitHub und bietet ein Update an,
# sobald dort ein groesserer steht.
STAND="$(tr -dc '0-9' < STAND 2>/dev/null)"
STAND="${STAND:-0}"

echo "→ Info.plist schreiben (Stand $STAND)"
cat > "$ZIEL/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lernkiste</string>
  <key>CFBundleDisplayName</key><string>Lernkiste</string>
  <key>CFBundleExecutable</key><string>Lernkiste</string>
  <key>CFBundleIdentifier</key><string>de.lernkiste.app</string>
  <key>CFBundleVersion</key><string>$STAND</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>Lernkiste</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>Lernseite</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>public.html</string></array>
  </dict></array>
  <key>LernkisteUpdates</key><true/>
  <key>LernkisteStand</key><string>$STAND</string>
  <key>NSHumanReadableCopyright</key><string>Lernkiste — interaktive Lernseiten</string>
</dict>
</plist>
PLIST

# Wegwerf-Signatur ("ad hoc"). Sie haengt an keinem Entwicklerkonto. Nach einem
# Update kann macOS deshalb einmal erneut nach dem Zugriff auf "Dokumente" fragen.
echo "→ signieren (ad hoc)"
codesign --force --deep -s - "$APP" 2>/dev/null || echo "  (Signatur übersprungen)"

echo "✓ fertig: $(pwd)/$APP"

if [ "$1" = "--installieren" ]; then
  echo "→ nach /Applications kopieren"
  pkill -f "Lernkiste.app/Contents/MacOS/Lernkiste" 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Lernkiste.app
  cp -R "$APP" /Applications/
  echo "✓ installiert: /Applications/Lernkiste.app"
fi
