#!/bin/bash
#
#  Neue Fassung veroeffentlichen.
#
#  Baut die App frisch, packt sie mit allem Drumherum ins Repo
#  und laedt alles zu GitHub hoch. Ein Befehl, fertig:
#
#      ./Werkzeuge/veroeffentlichen.sh "was neu ist"
#
set -e
cd "$(dirname "$0")/.."
ORDNER="$(pwd)"

NACHRICHT="${1:-Neue Fassung}"

echo ""
echo "  Lernkiste veroeffentlichen"
echo "  ──────────────────────────────────────────"
echo ""

# 1 — App neu bauen -----------------------------------------------------------
echo "  → App bauen"
./bauen.sh >/dev/null
echo "    ✓ $(du -sh Lernkiste.app | cut -f1) gebaut"

# 2 — Sicherheitsnetz: nichts Privates mitschicken ----------------------------
if [ -d zertifikat ] || ls -1 *.p12 2>/dev/null | grep -q .; then
  echo ""
  echo "  ✗ Abbruch: hier liegt ein privater Signierschluessel."
  echo "    Der darf nicht ins oeffentliche Repo. Bitte erst herausnehmen."
  exit 1
fi

# 3 — Hochladen ---------------------------------------------------------------
if [ ! -d .git ]; then
  echo ""
  echo "  ✗ Hier ist noch kein Repo eingerichtet."
  echo "    Einmalig noetig:"
  echo "        cd \"$ORDNER\""
  echo "        git init -b main && git add -A && git commit -m \"Erste Fassung\""
  echo "        git remote add origin <URL des GitHub-Repos>"
  echo "        git push -u origin main"
  exit 1
fi

echo "  → Aenderungen sichern"
git add -A
if git diff --cached --quiet; then
  echo "    (nichts geaendert)"
else
  git commit -q -m "$NACHRICHT"
  echo "    ✓ \"$NACHRICHT\""
fi

echo "  → hochladen"
git push -q
echo ""
echo "  ✓ Fertig. Wer die App neu laedt, bekommt ab jetzt diese Fassung."
echo ""
