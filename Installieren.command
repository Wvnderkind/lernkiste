#!/bin/bash
#
#  Lernkiste installieren — einfach doppelklicken.
#
#  Das Skript macht drei Dinge:
#    1. es nimmt der App die Download-Sperre von macOS ab
#    2. es legt die App in den Programme-Ordner
#    3. es legt den Ordner an, in dem die Lernseiten wohnen
#
set -e
cd "$(dirname "$0")"

APP="Lernkiste.app"
ZIEL="/Applications/$APP"
DATEN="$HOME/Documents/Lernkiste"

echo ""
echo "  Lernkiste wird eingerichtet"
echo "  ──────────────────────────────────────────"
echo ""

if [ ! -d "$APP" ]; then
  echo "  ✗ '$APP' liegt nicht neben diesem Skript."
  echo "    Bitte den heruntergeladenen Ordner vollstaendig entpacken"
  echo "    und 'Installieren.command' darin doppelklicken."
  echo ""
  read -r -p "  Mit der Eingabetaste schliessen "
  exit 1
fi

# 1 — Download-Sperre abnehmen -------------------------------------------------
echo "  → Download-Sperre entfernen"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# 2 — in den Programme-Ordner legen -------------------------------------------
if [ -d "$ZIEL" ]; then
  echo "  → aeltere Fassung in den Papierkorb legen"
  ALT="$HOME/.Trash/Lernkiste $(date +%Y-%m-%d_%H%M).app"
  mv "$ZIEL" "$ALT"
fi
echo "  → App nach /Applications kopieren"
cp -R "$APP" "$ZIEL"
xattr -dr com.apple.quarantine "$ZIEL" 2>/dev/null || true

# 3 — Ordner fuer die Lernseiten ----------------------------------------------
echo "  → Ordner fuer die Lernseiten anlegen"
mkdir -p "$DATEN/Seiten"

# Bauplan und Beispielseite gleich mitliefern, falls vorhanden
[ -f "Fuer-Claude/SPEC-Lernseiten.md" ] && cp "Fuer-Claude/SPEC-Lernseiten.md" "$DATEN/"
if [ -d "Beispiel" ] && [ -z "$(ls -A "$DATEN/Seiten" 2>/dev/null)" ]; then
  echo "  → Beispielseite einlegen"
  cp -R Beispiel/* "$DATEN/Seiten/"
fi

echo ""
echo "  ✓ Fertig."
echo ""
echo "    Die App liegt jetzt im Programme-Ordner."
echo "    Die Lernseiten liegen in:  $DATEN/Seiten"
echo ""
echo "    Beim ersten Start fragt macOS einmal nach dem Zugriff auf"
echo "    den Ordner 'Dokumente' — das muss erlaubt werden, sonst"
echo "    findet die App die Lernseiten nicht."
echo ""

open "$ZIEL"

read -r -p "  Mit der Eingabetaste schliessen "
