; Lernkiste — Zusatzschritte fuer den Installer.
;
; Bewusst nicht ueber "fileAssociations" in tauri.conf.json: das wuerde die
; Lernkiste zum Standardprogramm fuer ALLE .html-Dateien machen. Hier taucht sie
; nur unter "Oeffnen mit" auf; der Browser bleibt Standard.
; Alles unter HKCU — die Installation braucht keine Admin-Rechte.

!macro NSIS_HOOK_POSTINSTALL
  WriteRegStr HKCU "Software\Classes\Lernkiste.Lernseite" "" "Lernseite"
  WriteRegStr HKCU "Software\Classes\Lernkiste.Lernseite\DefaultIcon" "" "$INSTDIR\${MAINBINARYNAME}.exe,0"
  WriteRegStr HKCU "Software\Classes\Lernkiste.Lernseite\shell\open\command" "" '"$INSTDIR\${MAINBINARYNAME}.exe" "%1"'
  WriteRegStr HKCU "Software\Classes\.html\OpenWithProgids" "Lernkiste.Lernseite" ""
  WriteRegStr HKCU "Software\Classes\.htm\OpenWithProgids" "Lernkiste.Lernseite" ""
  WriteRegStr HKCU "Software\Classes\Applications\${MAINBINARYNAME}.exe" "FriendlyAppName" "Lernkiste"
  WriteRegStr HKCU "Software\Classes\Applications\${MAINBINARYNAME}.exe\shell\open\command" "" '"$INSTDIR\${MAINBINARYNAME}.exe" "%1"'
  WriteRegStr HKCU "Software\Classes\Applications\${MAINBINARYNAME}.exe\SupportedTypes" ".html" ""
  WriteRegStr HKCU "Software\Classes\Applications\${MAINBINARYNAME}.exe\SupportedTypes" ".htm" ""
  ; Explorer ueber die neuen Eintraege informieren
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  DeleteRegValue HKCU "Software\Classes\.html\OpenWithProgids" "Lernkiste.Lernseite"
  DeleteRegValue HKCU "Software\Classes\.htm\OpenWithProgids" "Lernkiste.Lernseite"
  DeleteRegKey HKCU "Software\Classes\Lernkiste.Lernseite"
  DeleteRegKey HKCU "Software\Classes\Applications\${MAINBINARYNAME}.exe"
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
!macroend
