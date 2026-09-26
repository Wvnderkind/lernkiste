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

/* Misch-Modus: die Seite laeuft unsichtbar in der Fehlerkiste oder der
   Probeklausur (mix.html) und zeigt nur die Aufgaben, die die Huelle anfordert. */
var MIX = null;
try {
  if (/(^|&)mix=1(&|$)/.test(location.search.slice(1)) && global.parent !== global
      && global.parent.LernkisteMix) MIX = global.parent.LernkisteMix;
} catch (e) { MIX = null; }

/* Die Bruecke zur App. Im Misch-Modus gehoert sie der Huelle. */
function bruecke() {
  if (MIX) { try { if (global.parent.Lernkiste) return global.parent.Lernkiste; } catch (e) {} }
  return global.Lernkiste || null;
}

/* Theme: die App setzt es selbst. Im Browser der gespeicherte Wunsch. */
if (MIX) {
  try {
    document.documentElement.dataset.theme =
      global.parent.document.documentElement.dataset.theme || "dark";
  } catch (e) { document.documentElement.dataset.theme = "dark"; }
} else if (!global.Lernkiste) {
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
/* Fuer Textantworten entscheiden Bindestriche, Klammern und Leerzeichen nicht
   ueber richtig oder falsch: "Propan-2-ol", "propan 2 ol" und "propan2ol"
   meinen dasselbe Molekuel. */
function knapp(text) {
  return normText(text).replace(/[^a-z0-9]/g, "");
}

function alsZahl(text) {
  /* Das echte Minuszeichen (U+2212) steht in jeder Chemie-Seite im Text; wer es
     abschreibt, hat sonst trotz richtiger Zahl eine falsche Antwort. Ein
     fuehrendes Plus ("+2") meint dasselbe wie 2. */
  var s = String(text == null ? "" : text).trim().replace(/\s/g, "")
            .replace(/[\u2212\u2013\u2014]/g, "-")
            .replace(/^\+/, "")
            .replace(",", ".");
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
/* Reiner Text aus dem HTML einer Aufgabe — fuer Meldungen und die Klausurtabelle. */
function klartext(html) {
  try {
    var doc = new DOMParser().parseFromString(String(html == null ? "" : html), "text/html");
    return (doc.body.textContent || "").replace(/\s+/g, " ").trim();
  } catch (e) { return String(html == null ? "" : html); }
}

/* ------------------------------------------------------------
   Faelligkeit (verteiltes Wiederholen)
   Richtig beantwortet: die Aufgabe steigt eine Stufe und ruht
   1 → 3 → 7 → 16 → 35 Tage. Falsch: morgen wieder. Steht in der
   App ein Pruefungstermin, kommt alles spaetestens am Vortag dran.
   ------------------------------------------------------------ */
var LEITER = [1, 3, 7, 16, 35];

function datumPlus(iso, tage) {
  var t = String(iso).slice(0, 10).split("-");
  var d = new Date(+t[0], +t[1] - 1, +t[2]);
  d.setDate(d.getDate() + tage);
  return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0")
                         + "-" + String(d.getDate()).padStart(2, "0");
}

function terminStr() {
  try {
    var b = bruecke(), t = b && b.termin;
    return typeof t === "string" && /^\d{4}-\d{2}-\d{2}$/.test(t) ? t : null;
  } catch (e) { return null; }
}

function deckeln(datum) {
  var t = terminStr();
  if (!t || !datum) return datum;
  var grenze = datumPlus(t, -1);
  return grenze > heuteStr() && datum > grenze ? grenze : datum;
}

/* Wann ist ein Eintrag wieder dran? null = noch nie geuebt. Eintraege aus der
   Zeit vor der Leiter bekommen ihr Datum aus dem letzten Ergebnis. */
function faelligkeit(e) {
  if (!e || !e.zuletzt) return null;
  if (e.faellig) return deckeln(e.faellig);
  if (e.letzter === "sassNicht") return datumPlus(e.zuletzt, 1);
  var n = e.sass || 0;
  return deckeln(datumPlus(e.zuletzt, n >= 3 ? 7 : n === 2 ? 3 : 1));
}
function istFaellig(e, heute) {
  var f = faelligkeit(e);
  return f !== null && f <= (heute || heuteStr());
}
function stufeVon(e) {
  if (typeof e.stufe === "number") return e.stufe;
  if (e.letzter === "sassNicht") return 0;
  return Math.min(e.sass || 0, 3);
}

/* ------------------------------------------------------------
   Zustand
   ------------------------------------------------------------ */
var K = null;            // Konfiguration der Seite
var KEY = "", EKEY = "", KKEY = "";
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
var variante = null;     // gewaehlte Abfragerichtung, "mix" = gemischt
var umfang = null;       // gewaehlter Umfang (zweite Filterebene)
var weiterUeben = false; // Tagespensum geschafft, er uebt trotzdem weiter
var mixModus = null;     // im Misch-Modus: "ueben" | "klausur"
var mixRueckruf = null;  // meldet der Huelle, wie die Aufgabe ausging

/* ------------------------------------------------------------
   Speicher (genau ein Schluessel, Format laut Vertrag)
   ------------------------------------------------------------ */
var Store = (function () {
  var mem = null;
  function leer() {
    return { items: {}, gesamt: 0,
             tagespensum: { datum: "", ziel: 20, geschafft: 0, treffer: 0, offen: {} },
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
   Abfragerichtungen und Umfaenge

   Manche Seiten fragen denselben Stoff aus mehreren Richtungen ab —
   beim Periodensystem etwa "Element -> Ordnungszahl" und umgekehrt.
   Die Aufgabe bleibt dieselbe (und damit auch der Fortschritt), nur die
   Frage aendert sich. Der Umfang ist davon unabhaengig: er entscheidet,
   welcher Ausschnitt ueberhaupt drankommt.
   ------------------------------------------------------------ */
function varianten() { return K && K.varianten ? K.varianten : []; }
function umfaenge()  { return K && K.umfaenge  ? K.umfaenge  : []; }

function findeVariante(id) {
  var v = varianten(), i;
  for (i = 0; i < v.length; i++) { if (v[i].id === id) return v[i]; }
  return null;
}

/* Wendet die gewaehlte Richtung auf eine Aufgabe an. Bei "mix" wuerfelt
   der Motor pro Aufgabe neu — die id bleibt in jedem Fall unangetastet,
   sonst zaehlte derselbe Stoff mehrfach im Fortschritt. */
function variantePraegen(it) {
  var v = varianten();
  if (!v.length) return it;
  /* Bei "Gemischt" kommen nur Richtungen dran, die sich mischen lassen. Eine
     Richtung mit mix:false (etwa reines Lernen mit Selbsteinschaetzung) bleibt
     aussen vor — sonst landet mitten in der Abfrage eine Karteikarte. */
  var mischbar = v.filter(function (x) { return x.mix !== false; });
  if (!mischbar.length) mischbar = v;
  var gewaehlt = variante === "mix" || !variante ? ausWahl(mischbar)
                                                 : (findeVariante(variante) || v[0]);
  var zusatz;
  try { zusatz = gewaehlt.bauen ? gewaehlt.bauen(it) : null; } catch (e) { zusatz = null; }
  if (!zusatz) return it;
  var kopie = Object.assign({}, it, zusatz);
  kopie.id = it.id;
  kopie.variante = gewaehlt.id;
  return kopie;
}

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
   Selbstpruefung
   ------------------------------------------------------------ */
/* Findet Baufehler, bevor sie beim Ueben auffallen: eine Loesung, die in
   keiner Auswahl steht, eine doppelte id, die zwei Aufgaben denselben
   Fortschritt teilen laesst, ein Meta-Block, der nicht zur Konfiguration
   passt. Wer die Seite gebaut hat — Mensch oder KI — bekommt die Liste im
   Klartext und weiss genau, was zu reparieren ist. */
function metaWert(name) {
  var m = document.querySelector('meta[name="' + name + '"]');
  return m ? m.getAttribute("content") : null;
}

function leer(x) { return x === undefined || x === null || String(x).trim() === ""; }

function aufgabePruefen(it, wo, melde) {
  if (it.art === "karte") {
    if (leer(it.frage))   melde(wo, "frage fehlt.");
    if (leer(it.antwort)) melde(wo, "antwort fehlt.");
  } else if (it.art === "rechnung") {
    if (leer(it.frage)) melde(wo, "frage fehlt.");
    if (!Array.isArray(it.felder) || !it.felder.length) {
      melde(wo, "felder fehlt (mindestens ein Eingabefeld).");
    } else {
      it.felder.forEach(function (f, n) {
        if (leer(f.loesung)) melde(wo, "Feld " + (n + 1) + ": loesung fehlt.");
      });
    }
  } else if (it.art === "wahl") {
    if (leer(it.frage)) melde(wo, "frage fehlt.");
    if (leer(it.loesung)) {
      melde(wo, "loesung fehlt.");
    } else if (Array.isArray(it.optionen)) {
      if (it.optionen.length < 2) melde(wo, "optionen braucht mindestens zwei Antworten.");
      if (it.optionen.map(String).indexOf(String(it.loesung)) < 0)
        melde(wo, 'loesung "' + it.loesung + '" steht nicht unter den optionen (Schreibweise muss exakt gleich sein).');
    } else if (!it.ablenkerAus) {
      melde(wo, "optionen fehlt (oder ablenkerAus angeben).");
    }
  } else if (it.art === "svg") {
    var svg = (K.schemata || {})[it.schema] || it.svg || "";
    if (!svg) melde(wo, it.schema ? 'Schema "' + it.schema + '" steht nicht in schemata.'
                                  : "schema oder svg fehlt.");
    if (leer(it.teil)) {
      melde(wo, "teil fehlt (welches data-teil ist die richtige Stelle?).");
    } else if (svg && svg.indexOf('data-teil="' + it.teil + '"') < 0
                   && svg.indexOf("data-teil='" + it.teil + "'") < 0) {
      melde(wo, 'im Schema gibt es kein Element mit data-teil="' + it.teil + '".');
    }
    if (leer(it.ziel)) melde(wo, "ziel fehlt (was soll angeklickt werden?).");
  } else if (it.art === "tabelle") {
    var def = (K.tabellen || {})[it.tabelle];
    if (!def) melde(wo, 'Tabelle "' + it.tabelle + '" steht nicht in tabellen.');
    if (!Array.isArray(it.zellen) || !it.zellen.length) {
      melde(wo, "zellen fehlt.");
    } else {
      if (def && def.spalten && def.spalten.length !== it.zellen.length)
        melde(wo, it.zellen.length + " zellen, aber die Tabelle hat " + def.spalten.length + " spalten.");
      it.zellen.forEach(function (z, n) {
        if (leer(z.loesung)) melde(wo, "Zelle " + (n + 1) + ": loesung fehlt.");
      });
    }
  }
}

function bauplanPruefen() {
  var fehler = [];
  function melde(wo, text) {
    var zeile = (wo ? wo + ": " : "") + text;
    if (fehler.indexOf(zeile) < 0) fehler.push(zeile);
  }

  var metaId = metaWert("lernkiste-id"), metaVer = metaWert("lernkiste-version");
  if (!metaId) melde("Kopf", '<meta name="lernkiste-id"> fehlt — ohne sie ordnet die App den Fortschritt nicht zu.');
  else if (metaId !== K.id)
    melde("Kopf", 'lernkiste-id im Kopf ("' + metaId + '") und id in Lernseite.start ("' + K.id + '") sind verschieden.');
  if (metaVer && Number(metaVer) !== Number(K.version))
    melde("Kopf", "lernkiste-version im Kopf (" + metaVer + ") und version in Lernseite.start ("
                  + K.version + ") sind verschieden.");
  if (!alleItems.length) melde("", "Die Seite hat keine einzige Aufgabe.");

  var vs = varianten();
  vs.forEach(function (v, n) {
    if (!v.id) melde("Variante " + (n + 1), "id fehlt.");
    if (v.bauen && typeof v.bauen !== "function") melde("Variante " + (v.id || n + 1), "bauen muss eine Funktion sein.");
  });
  umfaenge().forEach(function (u, n) {
    if (!u.id) melde("Umfang " + (n + 1), "id fehlt.");
    if (typeof u.gilt !== "function") melde("Umfang " + (u.id || n + 1), "gilt(aufgabe) muss eine Funktion sein.");
  });

  var gesehen = {};
  alleItems.forEach(function (roh) {
    var wo = "Aufgabe " + roh.id;
    if (gesehen[roh.id]) melde(wo, "id kommt doppelt vor — beide Aufgaben teilten sich den Fortschritt.");
    gesehen[roh.id] = true;
    if (!ARTEN[roh.art]) {
      melde(wo, 'unbekannte art "' + roh.art + '" (erlaubt: ' + Object.keys(ARTEN).join(", ") + ").");
      return;
    }
    if (roh.kategorie !== undefined && typeof roh.kategorie !== "string") melde(wo, "kategorie muss ein Text sein.");

    /* Varianten fuellen manche Felder erst beim Drankommen — also jede
       Fassung pruefen, die tatsaechlich auf den Bildschirm kommen kann. */
    if (!vs.length) { aufgabePruefen(roh, wo, melde); return; }
    vs.forEach(function (v) {
      if (typeof v.bauen !== "function") { aufgabePruefen(roh, wo, melde); return; }
      var zusatz;
      try { zusatz = v.bauen(roh); }
      catch (e) { melde(wo, 'Variante "' + v.id + '" bricht mit einem Fehler ab: ' + e.message); return; }
      aufgabePruefen(zusatz ? Object.assign({}, roh, zusatz) : roh,
                     wo + (vs.length > 1 ? ' (Variante "' + v.id + '")' : ""), melde);
    });
  });
  return fehler;
}

function textKopieren(text) {
  try { if (navigator.clipboard) { navigator.clipboard.writeText(text); return; } } catch (e) {}
  var feld = document.createElement("textarea");
  feld.value = text;
  feld.style.position = "fixed"; feld.style.opacity = "0";
  document.body.appendChild(feld);
  feld.select();
  try { document.execCommand("copy"); } catch (e) {}
  document.body.removeChild(feld);
}

function baufehlerZeigen(fehler) {
  if (!fehler.length) return;
  fehler.forEach(function (f) { try { console.error("Lernseite-Baufehler: " + f); } catch (e) {} });
  var zeigen = fehler.slice(0, 12);
  var kasten = document.createElement("div");
  kasten.className = "box falle lk-baufehler";
  kasten.id = "lkBaufehler";
  kasten.innerHTML =
      "<b>Diese Seite hat " + fehler.length + " Baufehler.</b> Die Übung läuft trotzdem, "
    + "einzelne Aufgaben können aber falsch bewertet werden. Gib die Liste der KI, "
    + "die die Seite gebaut hat — dann weiß sie genau, was zu reparieren ist."
    + "<ul>" + zeigen.map(function (f) { return "<li>" + esc(f) + "</li>"; }).join("")
    + (fehler.length > zeigen.length ? "<li>… und " + (fehler.length - zeigen.length) + " weitere</li>" : "")
    + "</ul>";
  var knopfKopieren = knopf("Liste kopieren", false, function () {
    textKopieren("Die Lernkiste meldet in der Seite \"" + K.id + "\" diese Baufehler. "
               + "Bitte behebe sie und gib die ganze Seite neu aus:\n- " + fehler.join("\n- "));
    knopfKopieren.innerHTML = "Kopiert ✓";
  });
  kasten.appendChild(knopfKopieren);
  var huelle = document.querySelector(".container") || document.body;
  huelle.insertBefore(kasten, huelle.firstChild);
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
  // Klappzustand der Hinweiskaesten: bewusst ohne "lern:", gehoert nicht zum Fortschritt.
  KKEY = "lernkiste-klapp:" + K.id;

  alleItems = itemsEinsammeln(K);

  var standard = Object.assign({ ziel: 20, schwerpunkt: null, hinweis: "" }, K.standard || {});
  var vonApp = null;
  try {
    vonApp = (global.Lernkiste && global.Lernkiste.tagesplan)
           ? global.Lernkiste.tagesplan(K.id) : null;
  } catch (e) { vonApp = null; }
  if (MIX) { mixStarten(standard); return; }
  plan = Object.assign({}, standard,
                       nurGesetzte((K.tagesplan || {})[heuteStr()]),
                       nurGesetzte(vonApp));

  var eig = Eigene.load();

  /* Ein neuer Tagesplan darf seine Auswahl einmal ueberschreiben: Beim ersten
     Oeffnen gelten Kategorien, Umfang und Richtung aus dem Plan. Klickt er
     danach selbst um, bleibt seine Wahl — bis wieder ein anderer Plan kommt.
     Erkannt wird ein neuer Plan am Stempel aus Datum und Planfeldern.
     "stand" im Plan-Eintrag erzwingt das erneut, auch bei gleichem Inhalt
     (wenn er sagt: "ueberschreib meine Auswahl"). */
  var planFelder = {};
  ["kategorien", "kategorie", "umfang", "variante", "stand"].forEach(function (f) {
    if (plan[f] !== undefined && plan[f] !== null) planFelder[f] = plan[f];
  });
  if (Object.keys(planFelder).length) {
    var stempel = heuteStr() + " " + JSON.stringify(planFelder);
    if (eig.planStempel !== stempel) {
      if (planFelder.kategorien !== undefined || planFelder.kategorie !== undefined) delete eig.kategorie;
      if (planFelder.umfang !== undefined) delete eig.umfang;
      if (planFelder.variante !== undefined) delete eig.variante;
      eig.planStempel = stempel;
      try { localStorage.setItem(EKEY, JSON.stringify(eig)); } catch (e) {}
    }
  }

  /* Kategorie: seine Wahl, sonst plan.kategorien, sonst ein schwerpunkt, der
     zufaellig genau eine Kategorie benennt. Alles, was die Seite nicht kennt,
     faellt weg — "schwerpunkt" ist meist nur ein Beschreibungstext, und ein
     Filter auf einen unbekannten Namen liesse keine einzige Aufgabe uebrig. */
  var kats = [];
  alleItems.forEach(function (it) {
    if (it.kategorie && kats.indexOf(it.kategorie) < 0) kats.push(it.kategorie);
  });
  function gueltigeKategorie(w) {
    var liste = (Array.isArray(w) ? w : [w]).filter(function (k) {
      return typeof k === "string" && kats.indexOf(k) >= 0;
    });
    return liste.length === 0 ? null : liste.length === 1 ? liste[0] : liste;
  }
  kategorie = gueltigeKategorie(eig.kategorie !== undefined ? eig.kategorie
                              : plan.kategorien !== undefined ? plan.kategorien
                              : plan.kategorie !== undefined ? plan.kategorie
                              : plan.schwerpunkt);

  /* Seine letzte Wahl gilt weiter — sonst das, was der Tagesplan vorgibt,
     sonst die erste Richtung bzw. der erste Umfang, den die Seite anbietet.
     Ids werden als Text verglichen: im Plan steht oft "umfang": 20 statt "20". */
  var vs = varianten(), us = umfaenge();
  variante = eig.variante !== undefined ? eig.variante
           : (plan.variante || (vs.length ? vs[0].id : null));
  if (variante !== "mix" && vs.length && !findeVariante(variante)) variante = vs[0].id;
  umfang = eig.umfang !== undefined && eig.umfang !== null ? eig.umfang
         : (plan.umfang !== undefined && plan.umfang !== null ? plan.umfang
            : (us.length ? us[0].id : null));
  umfang = umfang === null ? null : String(umfang);
  var umfangBekannt = us.some(function (u) { return String(u.id) === umfang; });
  if (us.length && !umfangBekannt) umfang = String(us[0].id);

  geruestBauen();
  /* Die Pruefung darf nie selbst die Seite umwerfen. */
  try { baufehlerZeigen(bauplanPruefen()); } catch (e) {}

  var s = Store.load();
  s.gesamt = alleItems.length;
  if (s.tagespensum.datum !== heuteStr()) {
    s.tagespensum = { datum: heuteStr(), ziel: plan.ziel, geschafft: 0, treffer: 0, offen: {} };
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
  klappbarMachen();
  enterEinhaengen();
  tippenUmleiten();
}

/* Jeder Hinweiskasten mit .box-title laesst sich ueber den Titel zuklappen.
   Zugeklappte bleiben zu, auch nach einem Neustart — je Seite, nach Kastentitel.
   <details>-Kaesten (z. B. Spickzettel) bleiben, wie die Seite sie gebaut hat. */
function klappbarMachen() {
  var zu;
  try { zu = JSON.parse(localStorage.getItem(KKEY) || "null") || {}; } catch (e) { zu = {}; }
  var kaesten = [$("lkHinweis")].concat(
    Array.prototype.slice.call($("lkZusatz").querySelectorAll("div.box")));
  kaesten.forEach(function (box) {
    var titel = null;
    for (var k = box.firstElementChild; k; k = k.nextElementSibling) {
      if (k.classList.contains("box-title")) { titel = k; break; }
    }
    if (!titel || box.classList.contains("klappbar")) return;
    // Alles ausser dem Titel in eine Huelle, damit auch lose Textstuecke mit zuklappen.
    var inhalt = document.createElement("div");
    inhalt.className = "box-inhalt";
    Array.prototype.slice.call(box.childNodes).forEach(function (n) {
      if (n !== titel) inhalt.appendChild(n);
    });
    box.appendChild(inhalt);
    var name = titel.textContent.trim();
    box.classList.add("klappbar");
    if (zu[name]) box.classList.add("zu");
    titel.title = "Klicken zum Ein- oder Ausklappen";
    titel.addEventListener("click", function () {
      var jetztZu = box.classList.toggle("zu");
      if (jetztZu) zu[name] = true; else delete zu[name];
      try { localStorage.setItem(KKEY, JSON.stringify(zu)); } catch (e) {}
    });
  });
}

/* ------------------------------------------------------------
   Misch-Modus: Fehlerkiste und Probeklausur
   Die Huelle (mix.html) laedt jede Seite eines Fachs unsichtbar
   und fordert einzelne Aufgaben an. Gebucht wird hier, im
   Speicher der jeweiligen Seite — so zaehlt alles zum Fortschritt.
   ------------------------------------------------------------ */
function mixStarten(standard) {
  plan = standard;
  kategorie = null; umfang = null; nurWackler = false;
  var vs = varianten();
  variante = vs.length > 1 ? "mix" : (vs.length ? vs[0].id : null);

  var s = Store.load();
  s.gesamt = alleItems.length;
  if (!s.tagespensum || s.tagespensum.datum !== heuteStr()) {
    s.tagespensum = { datum: heuteStr(), ziel: plan.ziel, geschafft: 0, treffer: 0, offen: {} };
  }
  Store.save(s);
  aktiv = alleItems.slice();

  /* Nur die Aufgabe ist zu sehen — Kopfzeile und eigene Kaesten der Seite nicht. */
  Array.prototype.slice.call(document.body.children).forEach(function (kind) {
    if (kind.tagName !== "SCRIPT") kind.style.display = "none";
  });
  var huelle = document.createElement("div");
  huelle.className = "container lk-mix";
  huelle.innerHTML = '<div id="lkHaupt"></div>';
  document.body.insertBefore(huelle, document.body.firstChild);
  document.body.style.padding = "0";
  enterEinhaengen();
  tippenUmleiten();

  function hoeheMelden() {
    try { MIX.hoehe(global, Math.ceil(huelle.offsetTop + huelle.offsetHeight + 4)); } catch (e) {}
  }
  try { new ResizeObserver(hoeheMelden).observe(huelle); }
  catch (e) { setInterval(hoeheMelden, 400); }

  function finde(id) {
    for (var i = 0; i < alleItems.length; i++) if (alleItems[i].id === id) return alleItems[i];
    return null;
  }
  try {
    MIX.bereit(global, {
      id: K.id,
      titel: document.title || K.id,
      kandidaten: function () {
        var st = Store.load(), heute = heuteStr();
        return alleItems.map(function (it) {
          var e = st.items[it.id];
          return { id: it.id, art: it.art, neu: !e,
                   faellig: !!e && istFaellig(e, heute),
                   wackler: !!e && e.letzter === "sassNicht" };
        });
      },
      zeigen: function (id, modus, fertig) {
        var it = finde(id);
        if (!it) return false;
        mixModus = modus === "klausur" ? "klausur" : "ueben";
        mixRueckruf = fertig;
        jetzt = variantePraegen(it);
        var e = Store.load().items[it.id];
        warWackler = !!e && e.letzter === "sassNicht";
        geprueft = false; wahl = null;
        aufgabeZeichnen(jetzt);
        return true;
      },
      buchen: function (id, richtig) {
        var it = finde(id);
        if (!it) return;
        var e = Store.load().items[it.id];
        warWackler = !!e && e.letzter === "sassNicht";
        buchen(it, !!richtig);
      },
      leeren: function () { $("lkHaupt").innerHTML = ""; jetzt = null; mixRueckruf = null; }
    });
  } catch (e) {}
}

function klausurLaeuft() { return !!MIX && mixModus === "klausur"; }

function mixZurueck(ergebnis) {
  var cb = mixRueckruf;
  mixRueckruf = null;
  if (typeof cb === "function") cb(ergebnis);
}

/* Probeklausur: Antwort festhalten, still auswerten, keine Loesung zeigen. */
function klausurAbgeben() {
  if (geprueft || !jetzt) return;
  geprueft = true;
  var it = jetzt, art = ARTEN[it.art];
  var du = antwortLesen(it);
  var erg;
  try { erg = art.pruefen(it, $("lkKoerper")) || {}; } catch (e) { erg = { richtig: false }; }
  var ok = erg.richtig === null || erg.richtig === undefined ? null : !!erg.richtig;
  if (it.art === "svg") du = du ? (ok ? klartext(it.ziel) : "andere Stelle") : "";
  var frage = frageFesthalten(it);
  $("lkHaupt").innerHTML = "";
  jetzt = null;
  mixZurueck({ id: it.id, frage: frage, du: du,
               loesung: loesungHtml(it, erg), ok: ok, merke: it.merke || "" });
}

/* Steckt in der Frage eine Zeichnung (z. B. eine Strukturformel), haengt ihr
   Aussehen am CSS der Seite. Fuer die Auswertungstabelle der Huelle werden die
   wichtigsten Stilwerte darum direkt an die Elemente geschrieben. */
function frageFesthalten(it) {
  var el = document.querySelector("#lkHaupt .card > .frage");
  if (!el || !el.querySelector("svg")) return frageHtml(it);
  try {
    var kopie = el.cloneNode(true);
    var alt = el.querySelectorAll("svg, svg *"), neu = kopie.querySelectorAll("svg, svg *");
    var EIG = ["fill", "stroke", "stroke-width", "stroke-dasharray", "stroke-linecap",
               "opacity", "font-size", "font-weight", "font-family", "font-style",
               "text-anchor", "dominant-baseline", "color"];
    for (var i = 0; i < alt.length && i < neu.length; i++) {
      var cs = getComputedStyle(alt[i]);
      neu[i].setAttribute("style", EIG.map(function (p) {
        return p + ":" + cs.getPropertyValue(p);
      }).join(";"));
    }
    return frageHtml(it, kopie.innerHTML);
  } catch (e) { return frageHtml(it); }
}

function frageHtml(it, basis) {
  var f = basis !== undefined ? basis : (it.frage || "");
  if (it.art === "svg" && !klartext(f)) f = "Klick auf: " + (it.ziel || "");
  if (it.art === "tabelle" && it.kopf) f = (f ? f + " — " : "") + "<b>" + it.kopf + "</b>";
  return f;
}

function spaltenname(it, n) {
  var def = (K.tabellen || {})[it.tabelle] || { spalten: [] };
  return klartext((def.spalten || [])[n] || ("Spalte " + (n + 1)));
}

/* Was er eingegeben hat — immer als reiner Text. */
function antwortLesen(it) {
  function wert(id) { var el = $(id); return el ? String(el.value || "").trim() : ""; }
  if (it.art === "karte") return wert("lkAntwort");
  if (it.art === "rechnung") {
    var felder = it.felder || [];
    return felder.map(function (f, n) {
      var v = wert("lkFeld" + n);
      return felder.length > 1 ? klartext(f.label || "Ergebnis") + ": " + (v || "—") : v;
    }).join(" · ");
  }
  if (it.art === "tabelle") {
    return (it.zellen || []).map(function (z, n) {
      return spaltenname(it, n) + ": " + (wert("lkZelle" + n) || "—");
    }).join(" · ");
  }
  if (it.art === "wahl") { var l = $("lkWahl"); return l ? klartext(l.dataset.gewaehlt || "") : ""; }
  if (it.art === "svg")  { var b = $("lkBuehne"); return b ? (b.dataset.geklickt || "") : ""; }
  return "";
}

/* Die richtige Antwort — HTML der Seite selbst. */
function loesungHtml(it, erg) {
  if (it.art === "karte") return it.antwort || "";
  if (it.art === "rechnung") return erg.text || "";
  if (it.art === "svg") return it.ziel || "";
  if (it.art === "tabelle") {
    return (it.zellen || []).map(function (z, n) {
      return spaltenname(it, n) + ": " + z.loesung;
    }).join(" · ");
  }
  if (it.art === "wahl") return String(it.loesung == null ? "" : it.loesung);
  return "";
}

/* ------------------------------------------------------------
   Melden: stimmt an einer Aufgabe etwas nicht, landet ein Eintrag
   in der Meldeliste der App. Wer die Seite baut, arbeitet sie ab.
   ------------------------------------------------------------ */
function meldenGeht() {
  if (MIX) return typeof MIX.melden === "function";
  return !!(global.Lernkiste && typeof global.Lernkiste.melden === "function");
}

function meldenOeffnen() {
  var box = $("lkMeldung");
  if (!box || !jetzt) return;
  if (box.style.display !== "none") { box.style.display = "none"; return; }
  var it = jetzt;
  box.innerHTML =
      '<input type="text" id="lkMeldText" maxlength="500" autocomplete="off" '
    +   'placeholder="Was stimmt nicht? (optional)">'
    + '<button type="button" class="primary" id="btnMeldSenden">Melden</button>'
    + '<button type="button" class="ghost" id="btnMeldWeg">Abbrechen</button>';
  box.style.display = "";
  var feld = $("lkMeldText");

  function senden() {
    var pfad = "";
    try { pfad = decodeURIComponent(location.pathname.replace(/^\/seite\//, "")); } catch (e) {}
    var eintrag = {
      datum: jetztStr(), seite: K.id, version: K.version, pfad: pfad,
      titel: document.title || K.id, item: it.id, variante: it.variante || null,
      art: it.art, frage: klartext(frageHtml(it)).slice(0, 300),
      text: String(feld.value || "").trim().slice(0, 500), erledigt: false
    };
    try {
      if (MIX) MIX.melden(eintrag); else global.Lernkiste.melden(eintrag);
      box.innerHTML = '<span class="lk-gemeldet">⚑ Gemeldet — die Aufgabe wird beim nächsten Durchsehen geprüft.</span>';
      var k = $("btnMelden"); if (k) k.disabled = true;
    } catch (e) {
      box.innerHTML = '<span class="lk-gemeldet">Melden hat nicht geklappt.</span>';
    }
  }
  feld.addEventListener("keydown", function (ev) {
    if (ev.key === "Enter" && !ev.isComposing) { ev.preventDefault(); ev.stopPropagation(); senden(); }
    else if (ev.key === "Escape") { ev.stopPropagation(); box.style.display = "none"; }
  });
  $("btnMeldSenden").addEventListener("click", senden);
  $("btnMeldWeg").addEventListener("click", function () { box.style.display = "none"; });
  feld.focus({ preventScroll: true });
}

/* ------------------------------------------------------------
   Auswahl und Reihenfolge
   ------------------------------------------------------------ */
function auswahlBauen() {
  var s = Store.load();
  var uf = null;
  umfaenge().forEach(function (u) { if (String(u.id) === umfang) uf = u; });
  aktiv = alleItems.filter(function (it) {
    if (kategorie && (Array.isArray(kategorie) ? kategorie.indexOf(it.kategorie) < 0
                                               : it.kategorie !== kategorie)) return false;
    if (uf && typeof uf.gilt === "function" && !uf.gilt(it)) return false;
    if (nurWackler) {
      var e = s.items[it.id];
      return !!e && e.letzter === "sassNicht";
    }
    return true;
  });
  schlange = [];
}

function schlangeFuellen() {
  var s = Store.load(), heute = heuteStr();
  /* Erst was heute faellig ist, dann Neues, dann der Rest. */
  var faellig = [], neu = [], rest = [];
  aktiv.forEach(function (it) {
    var e = s.items[it.id];
    var topf = !e ? neu : istFaellig(e, heute) ? faellig : rest;
    topf.push(it);
    /* Wackelkandidaten kommen in einer Runde zweimal dran — sie sind ja der Grund,
       warum man ueberhaupt nochmal uebt. */
    if (e && e.letzter === "sassNicht") topf.push(it);
  });
  schlange = shuffle(faellig).concat(shuffle(neu), shuffle(rest));
  /* Nicht dasselbe Item zweimal hintereinander. */
  if (jetzt && schlange.length > 1 && schlange[0].id === jetzt.id) {
    var t = schlange[0]; schlange[0] = schlange[1]; schlange[1] = t;
  }
}

/* Heute falsch beantwortete Aufgaben muessen heute noch zweimal hintereinander
   sitzen, bevor der Tag geschafft ist. tagespensum.offen: { id: richtigInFolge }.
   Es zaehlen nur die aus der aktuellen Auswahl — die anderen sind hier nicht erreichbar. */
var NACHHOLEN_RICHTIG = 2;
function offeneVonHeute(s) {
  var offen = s.tagespensum.offen || {};
  return aktiv.filter(function (it) { return offen.hasOwnProperty(it.id); });
}

function naechstesItem() {
  if (!aktiv.length) return null;
  var s = Store.load();
  /* Tagesziel erreicht, aber heutige Wackler noch offen: nur noch die. */
  if (!weiterUeben && s.tagespensum.geschafft >= s.tagespensum.ziel) {
    var offen = offeneVonHeute(s);
    if (offen.length) {
      var andere = offen.filter(function (it) { return !jetzt || it.id !== jetzt.id; });
      var pool = andere.length ? andere : offen;
      return pool[Math.floor(Math.random() * pool.length)];
    }
  }
  if (!schlange.length) schlangeFuellen();
  return schlange.shift();
}

/* ------------------------------------------------------------
   Kopfzeile
   ------------------------------------------------------------ */
function kopfZeichnen() {
  var s = Store.load(), heute = heuteStr();
  var sitzen = 0, wackler = 0, faellig = 0;
  alleItems.forEach(function (it) {
    var e = s.items[it.id];
    if (!e) return;
    if (e.letzter === "sass") sitzen++;
    if (e.letzter === "sassNicht") wackler++;
    if (istFaellig(e, heute)) faellig++;
  });
  var tp = s.tagespensum;
  var quote = tp.geschafft ? Math.round(100 * tp.treffer / tp.geschafft) : 0;
  var nachholen = offeneVonHeute(s).length;

  $("lkStats").innerHTML =
      "Heute geschafft <b>" + tp.geschafft + " / " + tp.ziel + "</b>"
    + "<span>Trefferquote <b>" + quote + " %</b></span>"
    + '<span title="Aufgaben, deren Wiederholung heute ansteht">Fällig heute: <b>' + faellig + "</b></span>"
    + "<span>Sitzt: <b>" + sitzen + " / " + alleItems.length + "</b></span>"
    + "<span>Wackelkandidaten: <b>" + wackler + "</b></span>"
    + (nachholen ? '<span class="lk-nachholen">Vor dem Ziel noch festigen: <b>' + nachholen + "</b></span>" : "");
  $("lkBalken").style.width = Math.min(100, Math.round(100 * tp.geschafft / Math.max(1, tp.ziel))) + "%";

  var kats = [];
  alleItems.forEach(function (it) {
    if (it.kategorie && kats.indexOf(it.kategorie) < 0) kats.push(it.kategorie);
  });

  var knopfBox = $("lkKnoepfe");
  knopfBox.innerHTML = "";

  /* Abfragerichtung — erst danach kommt, was den Stoff einschraenkt. */
  var vs = varianten();
  if (vs.length > 1) {
    vs.forEach(function (v) {
      knopfBox.appendChild(knopf(v.label || v.id, variante === v.id, function () {
        variante = v.id; Eigene.merken("variante", v.id);
        kopfZeichnen(); weiterMachen();
      }));
    });
    knopfBox.appendChild(knopf("🔀 Gemischt", variante === "mix", function () {
      variante = "mix"; Eigene.merken("variante", "mix");
      kopfZeichnen(); weiterMachen();
    }));
    knopfBox.appendChild(trenner());
  }

  /* Umfang — welcher Ausschnitt ueberhaupt drankommt. */
  var us = umfaenge();
  if (us.length > 1) {
    us.forEach(function (u) {
      knopfBox.appendChild(knopf(u.label || u.id, umfang === String(u.id), function () {
        umfang = String(u.id); Eigene.merken("umfang", u.id);
        auswahlBauen(); kopfZeichnen(); weiterMachen();
      }));
    });
    knopfBox.appendChild(trenner());
  }

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
      knopfBox.appendChild(knopf(kat, kategorie === kat || (Array.isArray(kategorie) && kategorie.indexOf(kat) >= 0), function () {
        /* Mehrfachauswahl: jeder Kategorie-Knopf schaltet an und aus.
           Nichts oder alles gewaehlt heisst wieder "Alle Kategorien". */
        var gewaehlt = kategorie === null ? [] : Array.isArray(kategorie) ? kategorie.slice() : [kategorie];
        var i = gewaehlt.indexOf(kat);
        if (i >= 0) gewaehlt.splice(i, 1); else gewaehlt.push(kat);
        gewaehlt = kats.filter(function (k) { return gewaehlt.indexOf(k) >= 0; });
        kategorie = (gewaehlt.length === 0 || gewaehlt.length === kats.length) ? null
                  : gewaehlt.length === 1 ? gewaehlt[0] : gewaehlt;
        Eigene.merken("kategorie", kategorie);
        auswahlBauen(); kopfZeichnen(); weiterMachen();
      }));
    });
  }

  var zurueck = knopf("Fortschritt zurücksetzen", false, function () {
    Store.reset();
    var n = Store.load(); n.gesamt = alleItems.length;
    n.tagespensum = { datum: heuteStr(), ziel: plan.ziel, geschafft: 0, treffer: 0, offen: {} };
    Store.save(n);
    serie = 0; fehl = {}; weiterUeben = false; jetzt = null;
    auswahlBauen(); kopfZeichnen(); weiterMachen();
  });
  zurueck.className = "danger";
  knopfBox.appendChild(zurueck);
}

/* Schmaler Strich zwischen zwei Knopfgruppen — sonst verschwimmt in einer
   langen Reihe, was Richtung ist und was Einschraenkung. */
function trenner() {
  var s = document.createElement("span");
  s.className = "knopf-trenner";
  return s;
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
  if (!weiterUeben && s.tagespensum.geschafft >= s.tagespensum.ziel
      && !offeneVonHeute(s).length) { fertigSchirm(); return; }
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
  jetzt = variantePraegen(jetzt);
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
    +   (meldenGeht() ? '<button type="button" class="ghost lk-melden-knopf" id="btnMelden" '
                      + 'title="Stimmt an dieser Aufgabe etwas nicht? Kurz melden.">⚑ Melden</button>' : "")
    +   '<div style="flex:1"></div>'
    +   '<button class="primary" id="btnPruefen">'
    +     (klausurLaeuft() ? "Weiter" : it.art === "karte" ? "Aufdecken" : "Prüfen") + "</button>"
    +   '<button class="primary" id="btnWeiter" style="display:none;">Weiter</button>'
    + "</div>"
    + '<div class="lk-meldung no-print" id="lkMeldung" style="display:none;"></div>';

  var haupt = $("lkHaupt");
  haupt.innerHTML = "";
  haupt.appendChild(karte);

  ARTEN[it.art].zeichnen(it, $("lkKoerper"));
  /* Beim Schema gibt der Klick auf das Bild die Antwort. Waere der Pruefen-Knopf
     da, wuerde Enter die Aufgabe sofort als falsch abhaken, bevor er ueberhaupt
     geklickt hat. In der Probeklausur waehlt der Klick nur aus. */
  if (ARTEN[it.art].direkt && !klausurLaeuft()) $("btnPruefen").style.display = "none";

  $("btnPruefen").addEventListener("click", pruefen);
  $("btnWeiter").addEventListener("click", weiter);
  $("btnSass").addEventListener("click", function () { selbst("sass"); });
  $("btnSassNicht").addEventListener("click", function () { selbst("sassNicht"); });
  if ($("btnMelden")) $("btnMelden").addEventListener("click", meldenOeffnen);

  /* Fokus nur, wenn das Feld schon ganz im Bild ist. WebKit (die Engine der
     App) holt den Cursor eines fokussierten Feldes kurz darauf trotz
     preventScroll ins Bild — bei grossen Bildern oder dem Heute-Kasten
     sprang die Seite so nach unten und die Frage oben war weg. Liegt das
     Feld tiefer, bekommt es den Fokus erst beim ersten Tippen. */
  var erstes = $("lkKoerper").querySelector("input, textarea");
  if (erstes && ganzImBild(erstes)) erstes.focus({ preventScroll: true });
  scrollHalten();
}

function ganzImBild(el) {
  var r = el.getBoundingClientRect();
  return r.top >= 0 && r.bottom <= (window.innerHeight || document.documentElement.clientHeight);
}

/* Nach dem Zeichnen einer Aufgabe darf nur er selbst scrollen. Laedt ein Bild
   nach und schiebt das Feld aus dem Bild, rueckt WebKit von sich aus nach —
   das wird hier zurueckgenommen, solange er weder Maus, Rad noch Tasten
   benutzt hat. */
var scrollWache = null;
function scrollHalten() {
  if (scrollWache) scrollWache();
  var y = window.scrollY, bis = Date.now() + 1500, frei = false;
  function selbst() { frei = true; }
  function zurueck() {
    if (frei || Date.now() > bis) { weg(); return; }
    if (Math.abs(window.scrollY - y) > 1) window.scrollTo(0, y);
  }
  var arten = ["wheel", "mousedown", "keydown", "touchstart"];
  function weg() {
    window.removeEventListener("scroll", zurueck);
    arten.forEach(function (a) { window.removeEventListener(a, selbst, true); });
    scrollWache = null;
  }
  window.addEventListener("scroll", zurueck);
  arten.forEach(function (a) { window.addEventListener(a, selbst, true); });
  scrollWache = weg;
}

/* Tippt er los, ohne vorher ins Feld zu klicken, landet der Text trotzdem
   im ersten Feld der Aufgabe. */
function tippenUmleiten() {
  document.addEventListener("keydown", function (ev) {
    if (ev.key.length !== 1 || ev.altKey || ev.metaKey || ev.ctrlKey || ev.isComposing) return;
    var ziel = ev.target;
    if (ziel && (ziel.tagName === "INPUT" || ziel.tagName === "TEXTAREA"
                 || ziel.tagName === "SELECT" || ziel.isContentEditable)) return;
    if (geprueft) return;
    var feld = document.querySelector("#lkKoerper input:not([disabled]), #lkKoerper textarea:not([disabled])");
    if (feld) feld.focus();
  });
}

function pruefen() {
  if (geprueft || !jetzt) return;
  if (klausurLaeuft()) { klausurAbgeben(); return; }
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
  $("btnWeiter").focus({ preventScroll: true });
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
  if (MIX) {
    var r = { id: jetzt.id, ok: wahl === "sass" };
    $("lkHaupt").innerHTML = "";
    jetzt = null;
    mixZurueck(r);
    return;
  }
  kopfZeichnen();
  weiterMachen();
}

function buchen(it, richtig) {
  var s = Store.load(), heute = heuteStr();
  var e = s.items[it.id] || { sass: 0, sassNicht: 0, letzter: "", zuletzt: "" };
  /* Leiter: nur wer faellig (oder neu) ist, steigt. Wer vorzeitig richtig
     liegt, behaelt seinen Termin; ein Fehler setzt immer zurueck. */
  var vorher = faelligkeit(e);
  if (!richtig) {
    e.stufe = 0;
    e.faellig = deckeln(datumPlus(heute, 1));
  } else if (vorher === null || vorher <= heute) {
    var st = Math.min(stufeVon(e), LEITER.length - 1);
    e.faellig = deckeln(datumPlus(heute, LEITER[st]));
    e.stufe = Math.min(st + 1, LEITER.length - 1);
  } else if (!e.faellig) {
    e.faellig = vorher;
    e.stufe = stufeVon(e);
  }
  if (richtig) e.sass++; else e.sassNicht++;
  e.letzter = richtig ? "sass" : "sassNicht";
  e.zuletzt = heute;
  s.items[it.id] = e;
  s.gesamt = alleItems.length;
  s.tagespensum.geschafft++;
  if (richtig) s.tagespensum.treffer++;
  var offen = s.tagespensum.offen = s.tagespensum.offen || {};
  if (!richtig) offen[it.id] = 0;
  else if (offen.hasOwnProperty(it.id)) {
    offen[it.id]++;
    if (offen[it.id] >= NACHHOLEN_RICHTIG) delete offen[it.id];
  }
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
    /* Probeklausur: er schreibt seine Antwort auf und vergleicht erst am Ende. */
    if (klausurLaeuft()) {
      var feld = document.createElement("textarea");
      feld.id = "lkAntwort";
      feld.className = "lk-antwort";
      feld.rows = 3;
      feld.placeholder = "Deine Antwort … (Enter = weiter, Umschalt+Enter = neue Zeile)";
      feld.addEventListener("keydown", function (ev) {
        if (ev.key === "Enter" && !ev.shiftKey && !ev.isComposing) { ev.preventDefault(); pruefen(); }
      });
      wo.appendChild(feld);
    }
  },
  pruefen: function (it, wo) {
    wo.innerHTML = '<div class="begruendung"><b>Antwort:</b> ' + (it.antwort || "") + "</div>"
                 + (it.merke ? '<div class="step">' + it.merke + "</div>" : "");
    return { richtig: null };
  }
};

/* --- 2. Rechnung mit Zwischenschritten -------------------- */
function feldStimmt(feld, eingabe) {
  /* Eine Loesung, die keine Zahl ist, kann nur Text sein. Frueher fiel so ein
     Feld ohne ausdrueckliches art:"text" in den Zahlenvergleich und war damit
     immer falsch — eine Falle, in die jede neue Seite einmal tappt. */
  if (feld.art === "text" || isNaN(alsZahl(feld.loesung))) {
    var erlaubt = [feld.loesung].concat(feld.alternativen || []);
    var e = normText(eingabe), k = knapp(eingabe);
    return erlaubt.some(function (l) {
      return normText(l) === e || (k !== "" && knapp(l) === k);
    });
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
        if (klausurLaeuft()) {
          buehne.querySelectorAll(".teil-gewaehlt").forEach(function (x) { x.classList.remove("teil-gewaehlt"); });
          el.classList.add("teil-gewaehlt");
          return;
        }
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

/* --- 5. Auswahl (Multiple Choice) -------------------------- */
ARTEN.wahl = {
  zeichnen: function (it, wo) {
    var opts = it.optionen;
    /* Keine eigenen Ablenker angegeben? Dann nimmt der Motor die Antworten
       anderer Aufgaben derselben Seite — die sind vom Fach her plausibel
       und aendern sich bei jedem Durchgang. */
    if (!opts && it.ablenkerAus) {
      var topf = [];
      aktiv.forEach(function (a) {
        var w = a[it.ablenkerAus];
        if (a.id !== it.id && w && topf.indexOf(w) < 0) topf.push(w);
      });
      opts = shuffle(topf).slice(0, (it.anzahl || 4) - 1);
      opts.push(it.loesung);
    }
    opts = shuffle((opts || []).slice());
    var html = '<div class="wahl-liste" id="lkWahl">';
    opts.forEach(function (o, n) {
      html += '<button type="button" class="wahl-option" data-wert="' + esc(o) + '">'
            +   '<span class="wahl-nr">' + (n + 1) + "</span>"
            /* Eigenes Element: sonst wird im Flex-Knopf jedes <sub>/<sup> zu
               einem eigenen Stueck mit Abstand — aus pK<sub>S</sub> wurde "pK  S". */
            +   '<span class="wahl-text">' + o + "</span>"
            + "</button>";
    });
    html += "</div>";
    if (it.hinweis) html += '<div class="hinweis-klein">' + it.hinweis + "</div>";
    wo.innerHTML = html;

    var liste = $("lkWahl");
    liste.querySelectorAll(".wahl-option").forEach(function (b) {
      b.addEventListener("click", function () {
        if (geprueft) return;
        liste.querySelectorAll(".wahl-option").forEach(function (x) {
          x.classList.remove("gewaehlt");
        });
        b.classList.add("gewaehlt");
        liste.dataset.gewaehlt = b.getAttribute("data-wert");
      });
    });
  },
  pruefen: function (it, wo) {
    var liste = $("lkWahl");
    var gewaehlt = liste ? (liste.dataset.gewaehlt || "") : "";
    var richtig = gewaehlt === String(it.loesung);
    if (liste) {
      liste.querySelectorAll(".wahl-option").forEach(function (b) {
        b.disabled = true;
        var wert = b.getAttribute("data-wert");
        if (wert === String(it.loesung)) b.classList.add("richtig");
        else if (wert === gewaehlt) b.classList.add("falsch");
      });
    }
    return { richtig: richtig,
             text: gewaehlt ? "" : "nichts ausgewählt",
             anhang: it.merke ? '<div class="begruendung"><b>Merke:</b> ' + it.merke + "</div>" : "" };
  }
};

/* ------------------------------------------------------------ */
global.Lernseite = {
  start: start, heuteStr: heuteStr, shuffle: shuffle,
  /* Fuer die Startseite: wann ein gespeicherter Eintrag wieder dran ist. */
  faelligkeit: faelligkeit, istFaellig: istFaellig, LEITER: LEITER.slice(),
  /* Fuer Agenten und Tests: liefert die Baufehler als Liste, leer = alles gut. */
  pruefen: function () { return K ? bauplanPruefen() : ["Lernseite.start wurde nie aufgerufen."]; }
};

})(window);
