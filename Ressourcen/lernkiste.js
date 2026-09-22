/* ============================================================
   lernkiste.js — gemeinsamer Motor aller Lernseiten
   ------------------------------------------------------------
   Eine Lernseite sagt nur noch: hier ist der Stoff, nimm diese
   Uebungsart. Fortschritt, Tagespensum, Enter-Steuerung,
   Schlussbildschirm und Glueckwunsch-GIFs macht der Motor.

   Laeuft unveraendert in der Lernkiste-App und beim Doppelklick
   im Finder — window.Lernkiste ist dort schlicht nicht da.

   Vier Uebungsarten:
     karte     Karteikarte, Selbsteinschaetzung
     rechnung  Zahlen-/Textfelder, danach Rechenweg in Schritten
     svg       Beschriftung: auf den gesuchten Teil klicken
     tabelle   Vergleichstabelle zeilenweise ausfuellen
   ============================================================ */
(function (global) {
"use strict";

/* Theme: die App setzt es selbst. Im Browser der gespeicherte Wunsch. */
if (!global.Lernkiste) {
  try {
    document.documentElement.dataset.theme = localStorage.getItem("lern-theme") || "dark";
  } catch (e) { document.documentElement.dataset.theme = "dark"; }
}

/* ------------------------------------------------------------
   Kleine Helfer
   ------------------------------------------------------------ */
function heuteStr() {
  var d = new Date();
  return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0")
                         + "-" + String(d.getDate()).padStart(2, "0");
}
function jetztStr() {
  var d = new Date();
  return heuteStr() + "T" + String(d.getHours()).padStart(2, "0") + ":"
       + String(d.getMinutes()).padStart(2, "0") + ":"
       + String(d.getSeconds()).padStart(2, "0");
}
function shuffle(arr) {
  var a = arr.slice();
  for (var i = a.length - 1; i > 0; i--) {
    var j = Math.floor(Math.random() * (i + 1)), t = a[i]; a[i] = a[j]; a[j] = t;
  }
  return a;
}
/* Nur fuer Werte, die in ein Attribut wandern (GIF-Adressen). Alles, was die
   Seite selbst an Text liefert, darf HTML sein — sonst liesse sich kein
   pK<sub>S</sub> und kein &auml; schreiben. */
function esc(s) {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
/* "1,5e-3" und "1.5E-3" sollen beide gehen — er tippt mit deutschem Komma. */
function alsZahl(text) {
  var s = String(text == null ? "" : text).trim().replace(/\s/g, "").replace(",", ".");
  if (s === "") return NaN;
  return Number(s);
}
function normText(text) {
  return String(text == null ? "" : text).toLowerCase().trim()
    .replace(/\s+/g, " ")
    .replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss");
}
function nachkommastellen(wert) {
  var s = String(wert).replace(",", ".");
  var p = s.indexOf(".");
  return p < 0 ? 0 : s.length - p - 1;
}
/* Ergaenzt nur, was wirklich gesetzt ist — sonst faellt ein Feld, das der
   Tagesplan nicht nennt, auf undefined und die Seite zeigt keine Frage mehr. */
function nurGesetzte(o) {
  var r = {};
  for (var k in (o || {})) if (o[k] !== null && o[k] !== undefined) r[k] = o[k];
  return r;
}
function $(id) { return document.getElementById(id); }

/* ------------------------------------------------------------
   Zustand
   ------------------------------------------------------------ */
var K = null;            // Konfiguration der Seite
var KEY = "", EKEY = "";
var alleItems = [];      // alles Abfragbare
var aktiv = [];          // nach Filtern uebrig
var schlange = [];       // Reihenfolge dieser Runde
var jetzt = null;        // laufendes Item
var plan = null;         // zusammengefuehrter Tagesplan
var serie = 0;           // richtige in Folge
var fehl = {};           // Fehlversuche in Folge, pro Item
var geprueft = false;    // Antwort schon bewertet?
var wahl = null;         // "sass" | "sassNicht" der Selbsteinschaetzung
var warWackler = false;  // stand das Item vorher auf "sassNicht"?
var nurWackler = false;
var kategorie = null;    // null = alle
var weiterUeben = false; // Tagespensum geschafft, er uebt trotzdem weiter

/* ------------------------------------------------------------
   Speicher (genau ein Schluessel, Format laut Vertrag)
   ------------------------------------------------------------ */
var Store = (function () {
  var mem = null;
  function leer() {
    return { items: {}, gesamt: 0,
             tagespensum: { datum: "", ziel: 20, geschafft: 0, treffer: 0 },
             zuletztGeoeffnet: "" };
  }
  return {
    load: function () {
      try {
        var roh = localStorage.getItem(KEY);
        if (roh) { mem = JSON.parse(roh); return mem; }
      } catch (e) {}
      return mem || leer();
    },
    save: function (o) {
      mem = o;
      try { localStorage.setItem(KEY, JSON.stringify(o)); } catch (e) {}
    },
    reset: function () {
      mem = leer();
      try { localStorage.removeItem(KEY); } catch (e) {}
    },
    leer: leer
  };
})();

/* Eigene Wahl schlaegt den Tagesplan — aber nur bei dem, was er selbst
   angeklickt hat. Kurzlebige Filter merken wir bewusst nicht. */
var Eigene = {
  load: function () {
    try { return JSON.parse(localStorage.getItem(EKEY) || "null") || {}; }
    catch (e) { return {}; }
  },
  merken: function (feld, wert) {
    var o = Eigene.load(); o[feld] = wert;
    try { localStorage.setItem(EKEY, JSON.stringify(o)); } catch (e) {}
  }
};

/* ------------------------------------------------------------
   Glueckwunsch-GIFs — ohne App bleibt es beim Haken
   ------------------------------------------------------------ */
var GIF = {
  bild: function (anlass) {
    try {
      var u = (global.Lernkiste && global.Lernkiste.gif)
            ? global.Lernkiste.gif(K.id, anlass) : null;
      return u ? '<img class="gif-gross" src="' + esc(u) + '" alt="">' : "";
    } catch (e) { return ""; }
  },
  toast: function (anlass, text) {
    var kasten = $("gifToast");
    if (!kasten) return;
    var u = null;
    try {
      u = (global.Lernkiste && global.Lernkiste.gif)
        ? global.Lernkiste.gif(K.id, anlass) : null;
    } catch (e) { u = null; }
    if (!u && !text) return;
    kasten.innerHTML = (u ? '<img src="' + esc(u) + '" alt="">' : "")
                     + '<div class="text">' + esc(text) + "</div>";
    kasten.classList.add("an");
    clearTimeout(GIF._uhr);
    GIF._uhr = setTimeout(function () { kasten.classList.remove("an"); }, 5000);
  },
  _uhr: null
};

var MEILENSTEIN = ["Zehn am Stück. Läuft.", "Serie steht.", "Das sitzt jetzt."];
var WACKLER_GESCHAFFT = ["Wackelkandidat erledigt.", "Der saß endlich.", "Genau den wolltest du haben."];
var DURCHHAENGER = ["Konzentrier dich mal.", "Nochmal in Ruhe angucken.", "Der will einfach nicht, oder?"];
function ausWahl(liste) { return liste[Math.floor(Math.random() * liste.length)]; }

/* ------------------------------------------------------------
   Items einsammeln
   ------------------------------------------------------------ */
function itemsEinsammeln(cfg) {
  var roh = typeof cfg.aufgaben === "function" ? cfg.aufgaben() : (cfg.aufgaben || []);
  var raus = [];
  roh.forEach(function (it, n) {
    var kopie = Object.assign({}, it);
    if (!kopie.id) kopie.id = "item-" + (n + 1);
    if (!kopie.art) kopie.art = "karte";
    raus.push(kopie);
  });
  return raus;
}

/* ------------------------------------------------------------
   Aufbau
   ------------------------------------------------------------ */
function start(cfg) {
  K = cfg;
  if (!K.id) { throw new Error("Lernseite.start braucht eine id"); }
  K.version = K.version || 1;
  KEY  = "lern:" + K.id + "@v" + K.version;
  EKEY = "lern:" + K.id + "@v1-einstellungen";

  alleItems = itemsEinsammeln(K);

  var standard = Object.assign({ ziel: 20, schwerpunkt: null, hinweis: "" }, K.standard || {});
  var vonApp = null;
  try {
    vonApp = (global.Lernkiste && global.Lernkiste.tagesplan)
           ? global.Lernkiste.tagesplan(K.id) : null;
  } catch (e) { vonApp = null; }
  plan = Object.assign({}, standard,
                       nurGesetzte((K.tagesplan || {})[heuteStr()]),
                       nurGesetzte(vonApp));

  var eig = Eigene.load();
  kategorie = eig.kategorie !== undefined ? eig.kategorie
            : (plan.schwerpunkt || null);

  geruestBauen();

  var s = Store.load();
  s.gesamt = alleItems.length;
  if (s.tagespensum.datum !== heuteStr()) {
    s.tagespensum = { datum: heuteStr(), ziel: plan.ziel, geschafft: 0, treffer: 0 };
  } else {
    s.tagespensum.ziel = plan.ziel;
  }
  s.zuletztGeoeffnet = jetztStr();
  Store.save(s);

  auswahlBauen();
  kopfZeichnen();
  weiterMachen();
}

function geruestBauen() {
  /* Was die Seite selbst im <body> mitbringt (Merksaetze, Eselsbruecken),
     wandert unter den Uebungsbereich. Skripte bleiben, wo sie sind. */
  var eigenes = [];
  Array.prototype.slice.call(document.body.children).forEach(function (kind) {
    if (kind.tagName !== "SCRIPT") eigenes.push(kind);
  });

  var huelle = document.createElement("div");
  huelle.className = "container";
  huelle.innerHTML =
      (K.untertitel ? '<p class="subtitle">' + K.untertitel + "</p>" : "")
    + '<div class="progresswrap no-print">'
    +   '<div class="progress-stats" id="lkStats">wird geladen…</div>'
    +   '<div class="bar-outer"><div class="bar-inner" id="lkBalken"></div></div>'
    +   '<div class="controls" id="lkKnoepfe"></div>'
    + "</div>"
    + '<div class="box merksatz" id="lkHinweis" style="display:none;"></div>'
    + '<div id="lkHaupt"></div>'
    + '<div id="lkZusatz"></div>'
    + (K.fussnote ? "<footer>" + K.fussnote + "</footer>" : "");

  document.body.insertBefore(huelle, document.body.firstChild);
  var zusatz = $("lkZusatz");
  eigenes.forEach(function (kind) { zusatz.appendChild(kind); });

  var toast = document.createElement("div");
  toast.id = "gifToast";
  document.body.appendChild(toast);

  if (plan.hinweis) {
    var h = $("lkHinweis");
    h.innerHTML = '<div class="box-title">★ Heute</div>' + plan.hinweis;
    h.style.display = "";
  }
  enterEinhaengen();
}

/* ------------------------------------------------------------
   Auswahl und Reihenfolge
   ------------------------------------------------------------ */
function auswahlBauen() {
  var s = Store.load();
  aktiv = alleItems.filter(function (it) {
    if (kategorie && it.kategorie !== kategorie) return false;
    if (nurWackler) {
      var e = s.items[it.id];
      return !!e && e.letzter === "sassNicht";
    }
    return true;
  });
  schlange = [];
}

function schlangeFuellen() {
  var s = Store.load();
  var doppelt = [];
  aktiv.forEach(function (it) {
    doppelt.push(it);
    var e = s.items[it.id];
    /* Wackelkandidaten kommen in einer Runde zweimal dran — sie sind ja der Grund,
       warum man ueberhaupt nochmal uebt. */
    if (e && e.letzter === "sassNicht") doppelt.push(it);
  });
  schlange = shuffle(doppelt);
  /* Nicht dasselbe Item zweimal hintereinander. */
  if (jetzt && schlange.length > 1 && schlange[0].id === jetzt.id) {
    var t = schlange[0]; schlange[0] = schlange[1]; schlange[1] = t;
  }
}

function naechstesItem() {
  if (!aktiv.length) return null;
  if (!schlange.length) schlangeFuellen();
  return schlange.shift();
}

/* ------------------------------------------------------------
   Kopfzeile
   ------------------------------------------------------------ */
function kopfZeichnen() {
  var s = Store.load();
  var sitzen = 0, wackler = 0;
  alleItems.forEach(function (it) {
    var e = s.items[it.id];
    if (!e) return;
    if (e.letzter === "sass") sitzen++;
    if (e.letzter === "sassNicht") wackler++;
  });
  var tp = s.tagespensum;
  var quote = tp.geschafft ? Math.round(100 * tp.treffer / tp.geschafft) : 0;

  $("lkStats").innerHTML =
      "Heute geschafft <b>" + tp.geschafft + " / " + tp.ziel + "</b>"
    + "<span>Trefferquote <b>" + quote + " %</b></span>"
    + "<span>Sitzt: <b>" + sitzen + " / " + alleItems.length + "</b></span>"
    + "<span>Wackelkandidaten: <b>" + wackler + "</b></span>";
  $("lkBalken").style.width = Math.min(100, Math.round(100 * tp.geschafft / Math.max(1, tp.ziel))) + "%";

  var kats = [];
  alleItems.forEach(function (it) {
    if (it.kategorie && kats.indexOf(it.kategorie) < 0) kats.push(it.kategorie);
  });

  var knopfBox = $("lkKnoepfe");
  knopfBox.innerHTML = "";
  knopfBox.appendChild(knopf("Nur meine Wackelkandidaten", nurWackler, function () {
    nurWackler = !nurWackler;
    auswahlBauen(); kopfZeichnen(); weiterMachen();
  }, wackler === 0 && !nurWackler));

  if (kats.length > 1) {
    knopfBox.appendChild(knopf("Alle Kategorien", kategorie === null, function () {
      kategorie = null; Eigene.merken("kategorie", null);
      auswahlBauen(); kopfZeichnen(); weiterMachen();
    }));
    kats.forEach(function (kat) {
      knopfBox.appendChild(knopf(kat, kategorie === kat, function () {
        kategorie = kat; Eigene.merken("kategorie", kat);
        auswahlBauen(); kopfZeichnen(); weiterMachen();
      }));
    });
  }

  var zurueck = knopf("Fortschritt zurücksetzen", false, function () {
    Store.reset();
    var n = Store.load(); n.gesamt = alleItems.length;
    n.tagespensum = { datum: heuteStr(), ziel: plan.ziel, geschafft: 0, treffer: 0 };
    Store.save(n);
    serie = 0; fehl = {}; weiterUeben = false; jetzt = null;
    auswahlBauen(); kopfZeichnen(); weiterMachen();
  });
  zurueck.className = "danger";
  knopfBox.appendChild(zurueck);
}

function knopf(text, an, tun, aus) {
  var b = document.createElement("button");
  b.innerHTML = text;
  if (an) b.className = "active";
  if (aus) b.disabled = true;
  b.addEventListener("click", tun);
  return b;
}

/* ------------------------------------------------------------
   Ablauf
   ------------------------------------------------------------ */
function weiterMachen() {
  var s = Store.load();
  if (!weiterUeben && s.tagespensum.geschafft >= s.tagespensum.ziel) { fertigSchirm(); return; }
  if (!aktiv.length) {
    $("lkHaupt").innerHTML = '<div class="leer-hinweis">'
      + (nurWackler ? "Kein Wackelkandidat übrig — alles sitzt gerade."
                    : "Für diese Auswahl gibt es keine Aufgaben.")
      + "</div>";
    jetzt = null;
    return;
  }
  jetzt = naechstesItem();
  if (!jetzt) return;
  var e = s.items[jetzt.id];
  warWackler = !!e && e.letzter === "sassNicht";
  geprueft = false; wahl = null;
  aufgabeZeichnen(jetzt);
}

function aufgabeZeichnen(it) {
  var karte = document.createElement("div");
  karte.className = "card";
  karte.innerHTML =
      (it.kategorie ? '<span class="kat-label">' + it.kategorie + "</span>" : "")
    + '<div class="frage">' + (it.frage || "") + "</div>"
    + '<div id="lkKoerper"></div>'
    + '<div id="lkErgebnis"></div>'
    + '<div class="weiter-zeile no-print">'
    +   '<div class="selfcheck" id="lkSelbst" style="display:none;">'
    +     '<span class="info">Und ehrlich?</span>'
    +     '<button class="ok-btn" id="btnSass">saß</button>'
    +     '<button class="no-btn" id="btnSassNicht">saß nicht</button>'
    +   "</div>"
    +   '<div style="flex:1"></div>'
    +   '<button class="primary" id="btnPruefen">' + (it.art === "karte" ? "Aufdecken" : "Prüfen") + "</button>"
    +   '<button class="primary" id="btnWeiter" style="display:none;">Weiter</button>'
    + "</div>";

  var haupt = $("lkHaupt");
  haupt.innerHTML = "";
  haupt.appendChild(karte);

  ARTEN[it.art].zeichnen(it, $("lkKoerper"));
  /* Beim Schema gibt der Klick auf das Bild die Antwort. Waere der Pruefen-Knopf
     da, wuerde Enter die Aufgabe sofort als falsch abhaken, bevor er ueberhaupt
     geklickt hat. */
  if (ARTEN[it.art].direkt) $("btnPruefen").style.display = "none";

  $("btnPruefen").addEventListener("click", pruefen);
  $("btnWeiter").addEventListener("click", weiter);
  $("btnSass").addEventListener("click", function () { selbst("sass"); });
  $("btnSassNicht").addEventListener("click", function () { selbst("sassNicht"); });

  var erstes = haupt.querySelector("input");
  if (erstes) erstes.focus();
}

function pruefen() {
  if (geprueft || !jetzt) return;
  var art = ARTEN[jetzt.art];
  var ergebnis = art.pruefen(jetzt, $("lkKoerper"));
  geprueft = true;
  $("btnPruefen").style.display = "none";

  if (ergebnis.richtig === null) {
    /* Karteikarte: das Urteil faellt er selbst. Erst danach geht es weiter. */
    $("lkSelbst").style.display = "";
    return;
  }

  $("lkErgebnis").innerHTML =
    '<div class="ergebnis ' + (ergebnis.richtig ? "ok" : "no") + '">'
    + (ergebnis.richtig ? "✓ Richtig" : "✗ Nicht ganz")
    + (ergebnis.text ? " — " + ergebnis.text : "") + "</div>"
    + (ergebnis.anhang || "");

  wahl = ergebnis.richtig ? "sass" : "sassNicht";
  $("lkSelbst").style.display = "";
  markiereWahl();
  $("btnWeiter").style.display = "";
  $("btnWeiter").focus();
}

/* Mit der Maus bleibt beides frei waehlbar — auch gegen das Urteil des Motors. */
function selbst(w) {
  if (!geprueft) return;
  wahl = w;
  markiereWahl();
  if (jetzt.art === "karte") { weiter(); return; }
  $("btnWeiter").style.display = "";
}

function markiereWahl() {
  var a = $("btnSass"), b = $("btnSassNicht");
  if (!a || !b) return;
  a.classList.toggle("chosen", wahl === "sass");
  b.classList.toggle("chosen", wahl === "sassNicht");
}

function weiter() {
  if (!geprueft || !jetzt || !wahl) return;
  buchen(jetzt, wahl === "sass");
  kopfZeichnen();
  weiterMachen();
}

function buchen(it, richtig) {
  var s = Store.load();
  var e = s.items[it.id] || { sass: 0, sassNicht: 0, letzter: "", zuletzt: "" };
  if (richtig) e.sass++; else e.sassNicht++;
  e.letzter = richtig ? "sass" : "sassNicht";
  e.zuletzt = heuteStr();
  s.items[it.id] = e;
  s.gesamt = alleItems.length;
  s.tagespensum.geschafft++;
  if (richtig) s.tagespensum.treffer++;
  Store.save(s);

  if (richtig) {
    serie++;
    fehl[it.id] = 0;
    if (serie > 0 && serie % 10 === 0) GIF.toast("meilenstein", ausWahl(MEILENSTEIN));
    else if (warWackler) GIF.toast("meilenstein", ausWahl(WACKLER_GESCHAFFT));
  } else {
    serie = 0;
    fehl[it.id] = (fehl[it.id] || 0) + 1;
    var n = fehl[it.id];
    /* Ab dem vierten Mal aufmuntern, danach nur noch jedes dritte Mal —
       sonst wird die Einblendung selbst zum Durchhaenger. */
    if (n === 4 || (n > 4 && (n - 4) % 3 === 0)) GIF.toast("durchhaenger", ausWahl(DURCHHAENGER));
  }
}

function fertigSchirm() {
  var s = Store.load(), tp = s.tagespensum;
  var quote = tp.geschafft ? Math.round(100 * tp.treffer / tp.geschafft) : 0;
  var bild = GIF.bild("fertig") || '<div class="fertig-icon">✅</div>';

  $("lkHaupt").innerHTML =
      '<div class="fertigscreen">'
    +   bild
    +   "<h2>Geschafft für heute</h2>"
    +   '<div class="fertig-quote">' + tp.treffer + " von " + tp.geschafft + "</div>"
    +   "<p>Aufgaben auf Anhieb richtig &mdash; das sind " + quote + " %.</p>"
    +   '<button class="ghost no-print" id="btnTrotzdem">Trotzdem weiterüben</button>'
    + "</div>";
  $("btnTrotzdem").addEventListener("click", function () {
    weiterUeben = true;
    weiterMachen();
  });

  try {
    if (global.Lernkiste && global.Lernkiste.fertig) {
      global.Lernkiste.fertig({ seite: K.id, ziel: tp.ziel,
                                geschafft: tp.geschafft, treffer: tp.treffer });
    }
  } catch (e) {}
}

/* ------------------------------------------------------------
   Enter: immer genau einen Schritt weiter, ueber den sichtbaren Knopf
   ------------------------------------------------------------ */
function enterEinhaengen() {
  function sichtbar(el) { return !!el && !el.disabled && el.offsetParent !== null; }
  function klick(wahlAusdruck) {
    var el = document.querySelector(wahlAusdruck);
    if (!sichtbar(el)) return false;
    el.click();
    return true;
  }
  document.addEventListener("keydown", function (ev) {
    if (ev.key !== "Enter" || ev.repeat || ev.isComposing) return;
    if (ev.altKey || ev.metaKey || ev.ctrlKey) return;
    var ziel = ev.target;
    if (ziel && (ziel.tagName === "TEXTAREA" || ziel.isContentEditable)) return;
    if (klick("#btnWeiter") || klick("#btnPruefen")) ev.preventDefault();
  });
}

/* ============================================================
   Die vier Uebungsarten
   ============================================================ */
var ARTEN = {};

/* --- 1. Karteikarte -------------------------------------- */
ARTEN.karte = {
  zeichnen: function (it, wo) {
    wo.innerHTML = it.hinweis ? '<div class="hinweis-klein">' + it.hinweis + "</div>" : "";
  },
  pruefen: function (it, wo) {
    wo.innerHTML = '<div class="begruendung"><b>Antwort:</b> ' + (it.antwort || "") + "</div>"
                 + (it.merke ? '<div class="step">' + it.merke + "</div>" : "");
    return { richtig: null };
  }
};

/* --- 2. Rechnung mit Zwischenschritten -------------------- */
function feldStimmt(feld, eingabe) {
  if (feld.art === "text") {
    var erlaubt = [feld.loesung].concat(feld.alternativen || []);
    var e = normText(eingabe);
    return erlaubt.some(function (l) { return normText(l) === e; });
  }
  var ist = alsZahl(eingabe), soll = alsZahl(feld.loesung);
  if (isNaN(ist) || isNaN(soll)) return false;
  if (typeof feld.toleranz === "number") return Math.abs(ist - soll) <= feld.toleranz + 1e-12;
  /* Ohne Toleranz auf die Stellen runden, die in der Loesung stehen — aber
     mindestens auf zwei. Sonst waere bei der Loesung "2" alles von 1,5 bis 2,5
     richtig, und ein danebenliegendes Ergebnis kaeme als Treffer durch. */
  var st = Math.max(2, nachkommastellen(feld.loesung));
  var f = Math.pow(10, st);
  return Math.round(ist * f) === Math.round(soll * f);
}

ARTEN.rechnung = {
  zeichnen: function (it, wo) {
    var html = '<div class="eingabe-zeile">';
    (it.felder || []).forEach(function (f, n) {
      html += '<div class="eingabe-feld">'
            +   "<label>" + (f.label || "Ergebnis")
            +     (f.einheit ? ' <span class="einheit">' + f.einheit + "</span>" : "")
            +   "</label>"
            +   '<input type="text" id="lkFeld' + n + '" autocomplete="off" spellcheck="false">'
            + "</div>";
    });
    html += "</div>";
    if (it.hinweis) html += '<div class="hinweis-klein">' + it.hinweis + "</div>";
    wo.innerHTML = html;
  },
  pruefen: function (it, wo) {
    var felder = it.felder || [], allesGut = true, teile = [];
    felder.forEach(function (f, n) {
      var el = $("lkFeld" + n);
      var gut = feldStimmt(f, el.value);
      if (!gut) allesGut = false;
      el.classList.add(gut ? "richtig" : "falsch");
      el.disabled = true;
      teile.push((f.label || "Ergebnis") + " = " + f.loesung
                 + (f.einheit ? " " + f.einheit : ""));
    });
    var anhang = "";
    if (it.schritte && it.schritte.length) {
      anhang += '<div class="steps">';
      it.schritte.forEach(function (s, n) {
        anhang += '<div class="step"><b>' + (n + 1) + ".</b> " + s + "</div>";
      });
      anhang += "</div>";
    }
    if (it.merke) anhang += '<div class="begruendung"><b>Merke:</b> ' + it.merke + "</div>";
    return { richtig: allesGut, text: teile.join(" · "), anhang: anhang };
  }
};

/* --- 3. SVG-Beschriftung ---------------------------------- */
ARTEN.svg = {
  direkt: true,        // der Klick ins Bild ist die Antwort, kein Pruefen-Knopf
  zeichnen: function (it, wo) {
    var svg = (K.schemata || {})[it.schema] || it.svg || "";
    wo.innerHTML = '<div class="svg-suchziel">Klick auf: ' + it.ziel + "</div>"
                 + '<div class="svg-buehne" id="lkBuehne">' + svg + "</div>"
                 + (it.hinweis ? '<div class="hinweis-klein">' + it.hinweis + "</div>" : "");
    var buehne = $("lkBuehne");
    buehne.querySelectorAll("[data-teil]").forEach(function (el) {
      el.addEventListener("click", function () {
        if (geprueft) return;
        buehne.dataset.geklickt = el.getAttribute("data-teil");
        pruefen();
      });
    });
  },
  pruefen: function (it, wo) {
    var buehne = $("lkBuehne");
    var geklickt = buehne ? (buehne.dataset.geklickt || "") : "";
    if (buehne) buehne.classList.add("gesperrt");
    var richtig = geklickt === it.teil;
    if (buehne) {
      var soll = buehne.querySelector('[data-teil="' + it.teil + '"]');
      if (soll) soll.classList.add("teil-richtig");
      if (!richtig && geklickt) {
        var falsch = buehne.querySelector('[data-teil="' + geklickt + '"]');
        if (falsch) falsch.classList.add("teil-falsch");
      }
    }
    var text = geklickt ? "" : "nichts angeklickt";
    return { richtig: richtig, text: text,
             anhang: it.merke ? '<div class="begruendung"><b>Merke:</b> ' + it.merke + "</div>" : "" };
  }
};

/* --- 4. Vergleichstabelle --------------------------------- */
ARTEN.tabelle = {
  zeichnen: function (it, wo) {
    var def = (K.tabellen || {})[it.tabelle] || { spalten: [] };
    var html = '<table class="lk-tabelle"><thead><tr>'
             + "<th>" + (def.kopfspalte || "") + "</th>";
    def.spalten.forEach(function (sp) { html += "<th>" + sp + "</th>"; });
    html += "</tr></thead><tbody><tr>"
          + '<td class="zeilenkopf">' + (it.kopf || "") + "</td>";
    (it.zellen || []).forEach(function (z, n) {
      html += '<td><input type="text" id="lkZelle' + n + '" autocomplete="off" spellcheck="false"></td>';
    });
    html += "</tr></tbody></table>";
    if (it.hinweis) html += '<div class="hinweis-klein">' + it.hinweis + "</div>";
    wo.innerHTML = html;
  },
  pruefen: function (it, wo) {
    var allesGut = true;
    (it.zellen || []).forEach(function (z, n) {
      var el = $("lkZelle" + n);
      var feld = { art: z.art || "text", loesung: z.loesung,
                   alternativen: z.alternativen, toleranz: z.toleranz };
      var gut = feldStimmt(feld, el.value);
      if (!gut) allesGut = false;
      el.classList.add(gut ? "richtig" : "falsch");
      el.disabled = true;
      var zelle = el.parentNode;
      var hinweis = document.createElement("span");
      hinweis.className = "loesung" + (gut ? "" : " daneben");
      hinweis.innerHTML = z.loesung;
      zelle.appendChild(hinweis);
    });
    return { richtig: allesGut, text: allesGut ? "" : "richtige Werte stehen jetzt darunter",
             anhang: it.merke ? '<div class="begruendung"><b>Merke:</b> ' + it.merke + "</div>" : "" };
  }
};

/* ------------------------------------------------------------ */
global.Lernseite = { start: start, heuteStr: heuteStr, shuffle: shuffle };

})(window);
