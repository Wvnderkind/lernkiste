// Die Oberflaeche der Lernkiste: Seitenleiste mit allen Lernseiten, Kopfzeile
// und ein Rahmen, in dem die Lernseite laeuft. Rahmen und Oberflaeche liegen
// auf demselben Ursprung — so teilen sie sich den localStorage, aus dem der
// Lernstand gelesen und als Datei gesichert wird.
(function () {
  'use strict';

  var tauri = window.__TAURI__;
  var invoke = tauri.core.invoke;
  var listen = tauri.event.listen;

  // Fehler der Oberflaeche ins Log der Lernkiste schreiben.
  function protokoll(text) {
    try { invoke('protokoll', { text: String(text) }).catch(function () {}); } catch (e) {}
  }
  window.addEventListener('error', function (e) {
    protokoll((e.message || 'Fehler') + ' @ ' + (e.filename || '') + ':' + (e.lineno || 0));
  });
  window.addEventListener('unhandledrejection', function (e) {
    protokoll('Promise: ' + (e.reason && e.reason.message || e.reason));
  });

  var $ = function (id) { return document.getElementById(id); };
  var rahmen = $('rahmen');
  var baumEl = $('baum');
  var sucheEl = $('suche');
  var startEl = $('start');
  var kopfEl = $('kopf');
  var sternEl = $('stern');
  var updateEl = $('update');
  var infoEl = $('info');
  var neuEl = $('neu');
  var kontextEl = $('kontext');

  var ARCHIV = 'Fürs Physikum';
  var daten = { faecher: [], erledigt: [], favoriten: [], zuletzt: [], theme: 'dark' };
  var aktuell = null;          // offene Seite, null = Startseite
  var mix = null;              // laufende Fehlerkiste/Probeklausur: {titel, fach, seiten}
  var suchtext = '';
  var offen = {};              // Schluessel → aufgeklappt?

  // MARK: Daten

  function alleSeiten() {
    var liste = [];
    daten.faecher.forEach(function (f) {
      f.themen.forEach(function (t) { t.seiten.forEach(function (s) { liste.push(s); }); });
    });
    return liste;
  }
  function seiteMitId(id) {
    var alle = alleSeiten();
    for (var i = 0; i < alle.length; i++) if (alle[i].id === id) return alle[i];
    return null;
  }
  function istErledigt(id) { return daten.erledigt.indexOf(id) >= 0; }
  function istFavorit(id) { return daten.favoriten.indexOf(id) >= 0; }

  function laden(neu) {
    return invoke(neu ? 'neu_einlesen' : 'bibliothek').then(function (d) {
      daten = d;
      themaAnwenden();
      if (aktuell) aktuell = seiteMitId(aktuell.id);
      leistenAbdruck = abdruck(d);
      baumBauen();
      kopfSetzen();
    });
  }

  // MARK: Seitenleiste

  function el(tag, klasse, text) {
    var e = document.createElement(tag);
    if (klasse) e.className = klasse;
    if (text != null) e.textContent = text;
    return e;
  }
  function svg(pfad, klasse) {
    var ns = 'http://www.w3.org/2000/svg';
    var s = document.createElementNS(ns, 'svg');
    s.setAttribute('viewBox', '0 0 16 16');
    s.setAttribute('class', klasse);
    s.setAttribute('aria-hidden', 'true');
    var p = document.createElementNS(ns, 'path');
    p.setAttribute('d', pfad);
    s.appendChild(p);
    return s;
  }
  var PFEIL = 'M4.5 6.2 8 9.8l3.5-3.6';
  var HAKEN = 'M3.4 8.4 6.5 11.4 12.6 4.8';

  function seitenZeile(seite, tiefe) {
    var z = el('div', 'zeile seite');
    z.style.setProperty('--tiefe', tiefe);
    z.tabIndex = -1;
    z.dataset.id = seite.id;
    z.title = seite.titel + '\n' + seite.fach + ' · ' + seite.thema;
    z.appendChild(el('span', 'platz'));
    z.appendChild(el('span', 'name', seite.titel));
    if (istErledigt(seite.id)) z.appendChild(svg(HAKEN, 'haken'));
    if (aktuell && aktuell.id === seite.id) z.classList.add('aktiv');
    z.addEventListener('click', function () {
      if (!aktuell || aktuell.id !== seite.id) oeffnen(seite);
    });
    kontextAn(z, { was: 'Seite', name: seite.titel, seiten: [seite], ebene: 0 });
    return z;
  }

  function gruppe(schluessel, kopfzeile, kinder, standardOffen) {
    var hülle = el('div', 'gruppe');
    var auf = schluessel in offen ? offen[schluessel] : standardOffen;
    var inhalt = el('div', 'kinder' + (auf ? '' : ' zu'));
    kinder.forEach(function (k) { inhalt.appendChild(k); });
    if (!auf) kopfzeile.classList.add('zu');
    kopfzeile.addEventListener('click', function () {
      var jetztAuf = inhalt.classList.contains('zu');
      inhalt.classList.toggle('zu', !jetztAuf);
      kopfzeile.classList.toggle('zu', !jetztAuf);
      offen[schluessel] = jetztAuf;
    });
    hülle.appendChild(kopfzeile);
    hülle.appendChild(inhalt);
    return hülle;
  }

  function ordnerZeile(klasse, name, tiefe) {
    var z = el('div', 'zeile ' + klasse);
    z.style.setProperty('--tiefe', tiefe);
    z.appendChild(svg(PFEIL, 'pfeil'));
    z.appendChild(el('span', 'name', name));
    z.title = name;
    return z;
  }

  // Themen mit nur einer Seite bekommen keine eigene Ebene — das spart in der
  // schmalen Leiste eine Einrueckung und damit Platz fuer den Titel.
  function fachKnoten(bereich, fach, standardOffen) {
    var kinder = [];
    fach.themen.forEach(function (t) {
      if (t.seiten.length === 1) {
        kinder.push(seitenZeile(t.seiten[0], 1));
      } else {
        var schluessel = bereich + '/' + fach.name + '/' + t.name;
        var themaZeile = ordnerZeile('thema', t.name, 1);
        kontextAn(themaZeile, { was: 'Thema', name: t.name, paket: fach.name + ' – ' + t.name, seiten: t.seiten, ebene: 1 });
        kinder.push(gruppe(schluessel, themaZeile,
          t.seiten.map(function (s) { return seitenZeile(s, 2); }), standardOffen));
      }
    });
    var fachZeile = ordnerZeile('fach', fach.name, 0);
    var alleImFach = [];
    fach.themen.forEach(function (t) { alleImFach = alleImFach.concat(t.seiten); });
    kontextAn(fachZeile, { was: 'Fach', name: fach.name, seiten: alleImFach, ebene: 2 });
    return gruppe(bereich + '/' + fach.name, fachZeile, kinder, standardOffen);
  }

  function bereich(name, kinder) {
    var kopf = el('div', 'bereich klappbar');
    kopf.appendChild(el('span', 'name', name));
    kopf.appendChild(svg(PFEIL, 'pfeil'));
    return gruppe('#' + name, kopf, kinder, true);
  }

  function baumBauen() {
    var scroll = baumEl.scrollTop;
    baumEl.textContent = '';
    var suche = suchtext.trim().toLowerCase();

    if (suche) {
      var treffer = alleSeiten().filter(function (s) {
        return s.titel.toLowerCase().indexOf(suche) >= 0
          || s.fach.toLowerCase().indexOf(suche) >= 0
          || s.thema.toLowerCase().indexOf(suche) >= 0;
      });
      baumEl.appendChild(el('div', 'bereich', treffer.length ? 'Treffer' : 'Nichts gefunden'));
      treffer.forEach(function (s) { baumEl.appendChild(seitenZeile(s, 0)); });
      markieren();
      return;
    }

    var favoriten = daten.favoriten.map(seiteMitId).filter(Boolean);
    if (favoriten.length) {
      baumEl.appendChild(bereich('Angepinnt', favoriten.map(function (s) { return seitenZeile(s, 0); })));
    }
    var aktiv = daten.faecher.filter(function (f) { return !f.archiv; });
    if (aktiv.length) {
      baumEl.appendChild(bereich('Aktuell', aktiv.map(function (f) { return fachKnoten('Aktuell', f, true); })));
    }
    // Das Physikum-Archiv bleibt zugeklappt, bis man es braucht.
    var archiv = daten.faecher.filter(function (f) { return f.archiv; });
    if (archiv.length) {
      baumEl.appendChild(bereich(ARCHIV, archiv.map(function (f) { return fachKnoten(ARCHIV, f, false); })));
    }
    baumEl.scrollTop = scroll;
    markieren();
  }

  // Zeigt in der Leiste, wo man gerade ist.
  function markieren() {
    startEl.classList.toggle('aktiv', !aktuell);
    var zeilen = baumEl.querySelectorAll('.zeile.seite');
    for (var i = 0; i < zeilen.length; i++) {
      zeilen[i].classList.toggle('aktiv', !!aktuell && zeilen[i].dataset.id === aktuell.id);
    }
  }

  // Die offene Seite soll in der Leiste sichtbar sein: Eltern aufklappen.
  function sichtbarMachen(id) {
    var zeile = null;
    var zeilen = baumEl.querySelectorAll('.zeile.seite');
    for (var i = 0; i < zeilen.length; i++) {
      if (zeilen[i].dataset.id !== id) continue;
      // Bevorzugt die Zeile unter „Aktuell"/Archiv, nicht die angepinnte.
      zeile = zeilen[i];
      if (zeile.closest('.gruppe .gruppe')) break;
    }
    if (!zeile) return;
    var k = zeile.parentElement;
    var geaendert = false;
    while (k && k !== baumEl) {
      if (k.classList.contains('kinder') && k.classList.contains('zu')) {
        k.previousElementSibling && k.previousElementSibling.click();
        geaendert = true;
      }
      k = k.parentElement;
    }
    if (geaendert || zeile.getBoundingClientRect().bottom > baumEl.getBoundingClientRect().bottom) {
      zeile.scrollIntoView({ block: 'nearest' });
    }
  }

  // MARK: Kopfzeile

  function kopfSetzen() {
    if (aktuell) {
      $('titel').textContent = aktuell.titel;
      $('unter').textContent = aktuell.fach + ' · ' + aktuell.thema;
      sternEl.hidden = false;
      var an = istFavorit(aktuell.id);
      sternEl.classList.toggle('an', an);
    } else if (mix) {
      $('titel').textContent = mix.titel;
      $('unter').textContent = mix.fach || 'Übersicht';
      sternEl.hidden = true;
    } else {
      $('titel').textContent = 'Lernkiste';
      $('unter').textContent = 'Übersicht';
      sternEl.hidden = true;
    }
  }
  function trenner(zeigen) { kopfEl.classList.toggle('trenner', !!zeigen); }

  function updateKnopf(z) {
    if (!z || !z.text) { updateEl.hidden = true; return; }
    updateEl.hidden = false;
    updateEl.textContent = z.text;
    updateEl.disabled = !z.klickbar;
  }

  // MARK: Navigation

  function adresse(seite) {
    return '/seite/' + seite.relativerPfad.split('/').map(encodeURIComponent).join('/');
  }

  function oeffnen(seite) {
    return sichern().then(function () {
      mix = null;
      aktuell = seite;
      invoke('seite_besucht', { id: seite.id }).catch(function () {});
      rahmen.src = adresse(seite);
      kopfSetzen();
      markieren();
      sichtbarMachen(seite.id);
      // Ab hier gehoert die Tastatur der Lernseite, nicht dem Suchfeld.
      rahmen.focus();
    });
  }
  function oeffnenPerId(id) {
    var s = seiteMitId(id);
    if (s) oeffnen(s);
  }

  function startseite() {
    return sichern().then(function () {
      mix = null;
      aktuell = null;
      rahmen.src = '/start';
      kopfSetzen();
      markieren();
    });
  }

  // Was steht gerade im Rahmen? (Auch Links innerhalb einer Seite fuehren
  // zu einer anderen Lernseite — dann zieht die Leiste mit.)
  function rahmenGeladen() {
    var pfad = '';
    try { pfad = rahmen.contentWindow.location.pathname; } catch (e) {}
    // Aus einer Fehlerkiste/Probeklausur heraus: deren Seiten noch sichern.
    if (mix && pfad !== '/mix') {
      var alte = mix;
      mix = null;
      mixSichern(alte.seiten);
      kopfSetzen();
    }
    if (pfad === '/mix') {
      var q = new URLSearchParams(rahmen.contentWindow.location.search);
      var pfade = q.getAll('p'), modus = q.get('modus');
      aktuell = null;
      mix = {
        titel: modus === 'klausur' ? 'Probeklausur' : modus === 'wackler' ? 'Wackelkandidaten' : 'Heute fällig',
        fach: q.get('titel') || '',
        seiten: alleSeiten().filter(function (x) { return pfade.indexOf(x.relativerPfad) >= 0; })
      };
      kopfSetzen();
      markieren();
    } else if (pfad.indexOf('/seite/') === 0) {
      var rel = pfad.slice(7).split('/').map(function (t) {
        try { return decodeURIComponent(t); } catch (e) { return t; }
      }).join('/');
      var s = alleSeiten().filter(function (x) { return x.relativerPfad === rel; })[0];
      if (s && (!aktuell || aktuell.id !== s.id)) {
        aktuell = s;
        invoke('seite_besucht', { id: s.id }).catch(function () {});
        kopfSetzen();
        markieren();
      }
    } else if (pfad === '/start' || pfad === '/') {
      if (aktuell) { aktuell = null; kopfSetzen(); markieren(); }
      startMerken();
    }
    themaInRahmen();
    trenner(false);   // jede Seite faengt oben an
    // Kurz warten, bis die Seite ihren Stand geladen/geschrieben hat.
    setTimeout(sichern, 1200);
  }

  // MARK: Fortschritt

  var sichernLaeuft = null;
  // Liest alle "lern:"-Eintraege und laesst sie als Datei ablegen.
  function lernRoh() {
    var roh = {};
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      if (k && k.indexOf('lern:') === 0) roh[k] = localStorage.getItem(k);
    }
    return roh;
  }
  // Nach einer Mischung: alle beteiligten Seiten auf einmal ablegen.
  function mixSichern(seiten) {
    var roh;
    try { roh = lernRoh(); } catch (e) { return Promise.resolve(); }
    return invoke('sichern_mix', { ids: seiten.map(function (s) { return s.id; }), roh: roh })
      .then(function () { return laden(false); })
      .then(function () { baumBauen(); })
      .catch(function () {});
  }
  function sichern() {
    if (!aktuell) return mix ? mixSichern(mix.seiten) : Promise.resolve();
    var seite = aktuell;
    var roh;
    try { roh = lernRoh(); } catch (e) { return Promise.resolve(); }
    var auftrag = invoke('sichern', { id: seite.id, roh: roh }).then(function (erledigt) {
      var war = istErledigt(seite.id);
      if (erledigt && !war) daten.erledigt.push(seite.id);
      if (!erledigt && war) daten.erledigt = daten.erledigt.filter(function (x) { return x !== seite.id; });
      if (erledigt !== war) baumBauen();
    }).catch(function () {});
    sichernLaeuft = auftrag;
    return auftrag;
  }
  setInterval(sichern, 25000);

  // MARK: Aussehen

  function themaAnwenden() {
    document.documentElement.dataset.theme = daten.theme;
    themaInRahmen();
  }
  function themaInRahmen() {
    try {
      var w = rahmen.contentWindow;
      w.document.documentElement.dataset.theme = daten.theme;
      if (w.Lernkiste) w.Lernkiste.theme = daten.theme;
    } catch (e) {}
  }
  function themaUmschalten() {
    var neu = daten.theme === 'dark' ? 'light' : 'dark';
    invoke('thema_setzen', { theme: neu }).then(function (t) {
      daten.theme = t;
      themaAnwenden();
      // Die Startseite wird mit ihren Farben gebaut — neu laden.
      if (!aktuell && !mix) rahmen.src = '/start';
    });
  }

  // MARK: Rueckfrage „Wohin gehoert die Seite?"

  var ortFaecher = [];
  function ortFragen(n) {
    ortFaecher = n.faecher || [];
    $('orttext').textContent = n.text || '';
    var liste = $('ortfaecher');
    liste.textContent = '';
    ortFaecher.forEach(function (f) { var o = el('option'); o.value = f.name; liste.appendChild(o); });
    var erstes = ortFaecher[0];
    $('ortfach').value = erstes ? erstes.name : '';
    $('ortthema').value = erstes && erstes.themen[0] ? erstes.themen[0] : '';
    ortThemen();
    $('ort').hidden = false;
    $('ortfach').focus();
    $('ortfach').select();
  }
  function ortThemen() {
    var name = $('ortfach').value.trim();
    var f = ortFaecher.filter(function (x) { return x.name === name; })[0];
    var liste = $('ortthemen');
    liste.textContent = '';
    (f ? f.themen : []).forEach(function (t) { var o = el('option'); o.value = t; liste.appendChild(o); });
  }
  function ortSchliessen(fach, thema) {
    $('ort').hidden = true;
    invoke('ort_antwort', { fach: fach, thema: thema }).catch(function () {});
    rahmen.focus();
  }
  $('ortfach').addEventListener('input', ortThemen);
  $('ortform').addEventListener('submit', function (e) {
    e.preventDefault();
    ortSchliessen($('ortfach').value, $('ortthema').value);
  });
  $('ortab').addEventListener('click', function () { ortSchliessen(null, null); });
  $('ort').addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { e.preventDefault(); ortSchliessen(null, null); }
  });

  // MARK: Tastatur

  function taste(aktion) {
    if (aktion === 'suchen') { sucheFokus(); return; }
    invoke('menue_aktion', { name: aktion }).catch(function () {});
  }
  function sucheFokus() {
    sucheEl.focus();
    sucheEl.select();
  }
  // Strg-Kuerzel landen im WebView, nicht im Fenstermenue — hier abfangen.
  document.addEventListener('keydown', function (e) {
    if (!e.ctrlKey || e.altKey || e.metaKey) return;
    var k = (e.key || '').toLowerCase(), aktion = null;
    if (k === 'r' && !e.shiftKey) aktion = 'neu_einlesen';
    else if (k === 'f' && !e.shiftKey) aktion = 'suchen';
    else if (k === 'o' && !e.shiftKey) aktion = 'importieren';
    else if (k === 'v' && e.shiftKey) aktion = 'zwischenablage';
    else if (k === 'e' && !e.shiftKey) aktion = 'exportieren';
    if (!aktion) return;
    e.preventDefault();
    e.stopPropagation();
    taste(aktion);
  }, true);

  // MARK: Nachrichten aus der Lernseite

  window.addEventListener('message', function (e) {
    if (e.source !== rahmen.contentWindow || e.origin !== location.origin) return;
    var n = e.data || {};
    switch (n.art) {
      case 'fertig': sichern(); break;
      case 'oeffnen': if (typeof n.id === 'string') oeffnenPerId(n.id); break;
      case 'scroll': trenner(!n.oben); break;
      case 'extern': if (typeof n.url === 'string') invoke('extern_oeffnen', { url: n.url }).catch(function () {}); break;
      case 'taste': if (typeof n.aktion === 'string') taste(n.aktion); break;
      case 'melden':
        if (n.eintrag && typeof n.eintrag === 'object') invoke('melden', { eintrag: n.eintrag }).catch(function () {});
        break;
      case 'anleitungWeg':
        invoke('anleitung_ausblenden').then(function () { if (!aktuell && !mix) rahmen.src = '/start'; }).catch(function () {});
        break;
    }
  });

  // MARK: Ereignisse aus dem Programm

  listen('neu_laden', function (e) {
    var ziel = e.payload && e.payload.oeffnen;
    laden(false).then(function () {
      if (ziel && seiteMitId(ziel)) oeffnenPerId(ziel);
      else if (!aktuell) startseite();
    });
  });
  listen('seite_oeffnen', function (e) { if (typeof e.payload === 'string') oeffnenPerId(e.payload); });
  listen('ort_fragen', function (e) { ortFragen(e.payload || {}); });
  listen('suche_fokus', sucheFokus);
  listen('exportieren_bitte', function () {
    invoke('exportieren', { ids: aktuell ? [aktuell.id] : [], name: aktuell ? aktuell.titel : '' }).catch(function () {});
  });
  listen('update', function (e) { updateKnopf(e.payload); });
  listen('sichern_bitte', function () {
    sichern().then(function () { return invoke('gesichert'); }).catch(function () {});
  });
  listen('schliessen', function () {
    sichern().then(function () { return invoke('beenden'); }).catch(function () { invoke('beenden'); });
  });

  // MARK: Bedienelemente

  sucheEl.addEventListener('input', function () {
    suchtext = sucheEl.value;
    baumBauen();
  });
  sucheEl.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { sucheEl.value = ''; suchtext = ''; baumBauen(); rahmen.focus(); }
    if (e.key === 'Enter') {
      var erste = baumEl.querySelector('.zeile.seite');
      if (erste) erste.click();
    }
  });
  startEl.addEventListener('click', function () { startseite(); });
  $('thema').addEventListener('click', themaUmschalten);
  sternEl.addEventListener('click', function () {
    if (!aktuell) return;
    invoke('favorit_umschalten', { id: aktuell.id }).then(function (liste) {
      daten.favoriten = liste;
      kopfSetzen();
      baumBauen();
    });
  });
  updateEl.addEventListener('click', function () {
    invoke('update_installieren').catch(function () {});
  });
  rahmen.addEventListener('load', rahmenGeladen);

  // Breite der Leiste ziehen (230–340 px), pro Rechner gemerkt.
  (function () {
    var leiste = $('leiste'), griff = $('griff'), startX = 0, startB = 0;
    try {
      var b = parseInt(localStorage.getItem('app:leistenbreite'), 10);
      if (b >= 230 && b <= 340) leiste.style.width = b + 'px';
    } catch (e) {}
    function zieh(e) {
      var b = Math.max(230, Math.min(340, startB + e.clientX - startX));
      leiste.style.width = b + 'px';
    }
    function los() {
      document.removeEventListener('pointermove', zieh);
      document.removeEventListener('pointerup', los);
      rahmen.style.pointerEvents = '';
      try { localStorage.setItem('app:leistenbreite', parseInt(leiste.style.width, 10)); } catch (e) {}
    }
    griff.addEventListener('pointerdown', function (e) {
      startX = e.clientX;
      startB = leiste.getBoundingClientRect().width;
      rahmen.style.pointerEvents = 'none';   // sonst schluckt der Rahmen die Maus
      document.addEventListener('pointermove', zieh);
      document.addEventListener('pointerup', los);
      e.preventDefault();
    });
  })();

  // Kein Browser-Kontextmenue auf der Oberflaeche selbst (Felder ausgenommen).
  document.addEventListener('contextmenu', function (e) {
    if (!e.target.closest('input, textarea')) e.preventDefault();
  });

  // MARK: Rechtsklick in der Leiste: Exportieren / Im Explorer zeigen

  function kontextAn(zeile, ziel) {
    zeile.addEventListener('contextmenu', function (e) {
      e.preventDefault();
      e.stopPropagation();
      kontextZeigen(e.clientX, e.clientY, ziel);
    });
  }

  function kontextZeigen(x, y, ziel) {
    blaseZu();
    kontextEl.textContent = '';
    var ids = ziel.seiten.map(function (s) { return s.id; });
    var titel = ziel.was === 'Seite' ? 'Seite exportieren …'
      : ziel.was + ' „' + ziel.name + '“ exportieren …';
    kontextEintrag(titel, function () {
      invoke('exportieren', { ids: ids, name: ziel.paket || ziel.name }).catch(function () {});
    });
    if (ids.length) {
      kontextEintrag('Im Explorer zeigen', function () {
        invoke('im_explorer_zeigen', { id: ids[0], ebene: ziel.ebene }).catch(function () {});
      });
    }
    kontextEl.hidden = false;
    var b = kontextEl.offsetWidth, h = kontextEl.offsetHeight;
    kontextEl.style.left = Math.max(4, Math.min(x, innerWidth - b - 4)) + 'px';
    kontextEl.style.top = Math.max(4, Math.min(y, innerHeight - h - 4)) + 'px';
    var erster = kontextEl.querySelector('button');
    if (erster) erster.focus();
  }

  function kontextEintrag(text, tun) {
    var k = el('button', 'eintrag', text);
    k.type = 'button';
    k.setAttribute('role', 'menuitem');
    k.addEventListener('click', function () { kontextZu(); tun(); });
    kontextEl.appendChild(k);
  }

  function kontextZu() { kontextEl.hidden = true; }

  // MARK: ⓘ — was mit den letzten Updates neu kam

  function neuigkeitenLaden() {
    return invoke('neuigkeiten').then(function (n) {
      infoEl.querySelector('.punkt').hidden = !n.ungelesen;
      return n;
    });
  }

  function datumLesbar(iso) {
    var d = new Date(iso + 'T12:00:00');
    if (isNaN(d)) return iso;
    return d.toLocaleDateString('de-DE', { day: 'numeric', month: 'long', year: 'numeric' });
  }

  function blaseZeigen() {
    kontextZu();
    neuigkeitenLaden().then(function (n) {
      neuEl.textContent = '';
      neuEl.appendChild(el('h2', null, 'Neu in der Lernkiste'));
      if (!n.eintraege.length) {
        neuEl.appendChild(el('p', 'leise', 'Hier steht nach dem nächsten Update, was sich geändert hat.'));
      }
      n.eintraege.forEach(function (e) {
        neuEl.appendChild(el('div', 'wann', datumLesbar(e.datum)));
        var liste = el('ul');
        e.punkte.forEach(function (p) { liste.appendChild(el('li', null, p)); });
        neuEl.appendChild(liste);
      });
      var r = infoEl.getBoundingClientRect();
      neuEl.style.top = (r.bottom + 6) + 'px';
      neuEl.style.right = Math.max(8, innerWidth - r.right - 8) + 'px';
      neuEl.hidden = false;
      neuEl.scrollTop = 0;
      infoEl.querySelector('.punkt').hidden = true;
      return invoke('neuigkeiten_gelesen');
    }).catch(function () {});
  }

  function blaseZu() { neuEl.hidden = true; }

  infoEl.addEventListener('click', function (e) {
    e.stopPropagation();
    if (neuEl.hidden) blaseZeigen(); else blaseZu();
  });

  // Klick daneben, Esc oder ein Klick in die Lernseite (das Fenster verliert
  // dann den Fokus an den Rahmen) schliesst Menue und ⓘ-Fenster.
  document.addEventListener('mousedown', function (e) {
    if (!kontextEl.hidden && !kontextEl.contains(e.target)) kontextZu();
    if (!neuEl.hidden && !neuEl.contains(e.target) && !infoEl.contains(e.target)) blaseZu();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { kontextZu(); blaseZu(); }
  });
  window.addEventListener('blur', function () { kontextZu(); blaseZu(); });
  window.addEventListener('resize', function () { kontextZu(); blaseZu(); });
  baumEl.addEventListener('scroll', kontextZu);

  // MARK: Von selbst auffrischen
  // Alle 30 Minuten, direkt nach Mitternacht und beim Zurueckkehren ins
  // Fenster: neue Seiten erscheinen, der Gruss wechselt, die Haken vom Vortag
  // verschwinden. Neu gezeichnet wird nur, was sich wirklich geaendert hat —
  // eine offene Lernseite bleibt unberuehrt.

  var leistenAbdruck = '';
  var startInhalt = null;
  var zuletztAufgefrischt = Date.now();

  function heute() {
    var d = new Date();
    return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate();
  }
  var angezeigterTag = heute();

  function abdruck(d) {
    var teile = [heute(), (d.favoriten || []).join(',')];
    (d.faecher || []).forEach(function (f) {
      f.themen.forEach(function (t) {
        t.seiten.forEach(function (s) {
          teile.push([s.id, s.titel, f.name, t.name, f.archiv ? 1 : 0,
            (d.erledigt || []).indexOf(s.id) >= 0 ? 1 : 0].join('|'));
        });
      });
    });
    return teile.join('\n');
  }

  function startMerken() {
    fetch('/start', { cache: 'no-store' }).then(function (r) { return r.text(); })
      .then(function (t) { startInhalt = t; }).catch(function () {});
  }

  function auffrischen() {
    zuletztAufgefrischt = Date.now();
    angezeigterTag = heute();
    // Nicht mitten in eine Frage oder ein offenes Menue hineinzeichnen.
    if (!$('ort').hidden || !kontextEl.hidden) return;
    invoke('neu_einlesen').then(function (d) {
      var neu = abdruck(d);
      if (neu !== leistenAbdruck) {
        daten = d;
        if (aktuell) aktuell = seiteMitId(aktuell.id) || aktuell;
        leistenAbdruck = neu;
        baumBauen();
        kopfSetzen();
      }
      if (!aktuell && !mix && startInhalt !== null) {
        return fetch('/start', { cache: 'no-store' }).then(function (r) { return r.text(); })
          .then(function (t) { if (!aktuell && !mix && t !== startInhalt) rahmen.src = '/start'; });
      }
    }).catch(function (e) { protokoll('Auffrischen: ' + (e && e.message || e)); });
    neuigkeitenLaden().catch(function () {});
  }

  setInterval(auffrischen, 30 * 60 * 1000);
  setInterval(function () { if (heute() !== angezeigterTag) auffrischen(); }, 60 * 1000);
  window.addEventListener('focus', function () {
    if (Date.now() - zuletztAufgefrischt > 60 * 1000) auffrischen();
  });

  // MARK: Start

  laden(false).then(function () {
    startseite();
    neuigkeitenLaden().catch(function () {});
    return invoke('bereit');
  }).then(updateKnopf).catch(function (e) {
    protokoll('Start: ' + (e && e.message || e));
  });
})();
