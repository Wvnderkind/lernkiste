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
  Quelle/Startseite.swift Quelle/Fenster.swift Quelle/main.swift

echo "→ Ressourcen kopieren"
cp Ressourcen/tokens.css "$ZIEL/Resources/"
# Der gemeinsame Motor der Lernseiten. Er liegt hier im Programm und wird
# beim Start nach Seiten/_motor/ gespiegelt — so hat jede Lernseite denselben
# Stand, egal wer die App installiert.
cp Ressourcen/lernkiste.js Ressourcen/lernkiste.css "$ZIEL/Resources/"
[ -f Ressourcen/Lernkiste.icns ] && cp Ressourcen/Lernkiste.icns "$ZIEL/Resources/"

echo "→ Info.plist schreiben"
cat > "$ZIEL/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lernkiste</string>
  <key>CFBundleDisplayName</key><string>Lernkiste</string>
  <key>CFBundleExecutable</key><string>Lernkiste</string>
  <key>CFBundleIdentifier</key><string>de.lernkiste.app</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>Lernkiste</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Lernkiste — interaktive Lernseiten</string>
</dict>
</plist>
PLIST

# Wegwerf-Signatur ("ad hoc"). Sie haengt an keinem Entwicklerkonto und bleibt
# fuer dieselbe App stabil — macOS fragt also nur einmal nach dem Zugriff auf
# "Dokumente" und danach nicht wieder.
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
