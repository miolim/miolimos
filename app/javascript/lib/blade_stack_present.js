// #1496 (aus immoos #1302 uebernommen). Hans dort, im vierten Anlauf: „Ich
// kann die einzelnen Zeilen nicht so anklicken, dass sie in einer neuen Card
// geoeffnet werden. Auch ein Karten-Refresh hilft nichts. Erst ein Neuladen
// der gesamten Seite ermoeglicht es."
//
// Die Klick-Pfade (blade-link, Suche, Wikilink-Recherche) fragten bisher die
// BODY-KLASSE `has-blade-stack`, um zu entscheiden, ob diese Seite ueberhaupt
// einen Card-Stapel hat. Die Klasse ist aber ein MERKER, den der
// blade-stack-Controller beim Verbinden setzt und beim Trennen entfernt —
// gemeinsamer Zustand mit genau einem Schreiber zu viel. Trennt sich eine
// zweite (alte) Instanz, nachdem die lebende sich verbunden hat, ist die
// Klasse weg, obwohl der Stapel steht.
//
// Das Schadensbild ist dann genau das beschriebene: Zeilenklicks tun nichts,
// alles andere lebt weiter — der Poll, der Versions-Waechter, sogar der
// Aktualisieren-Knopf der Card (eine Aktion desselben, lebenden Controllers).
// Ein Karten-Refresh hilft nicht, weil er die Klasse nicht anfasst; nur ein
// Neuladen setzt sie neu.
//
// Deshalb fragen die Klick-Pfade jetzt die TATSACHE statt des Merkers: Steht
// ein Stack-Container im Dokument? Das wird bei jedem Klick frisch gelesen und
// laesst sich von keiner Trennung verstellen. Die Klasse bleibt fuer die
// CSS-Regeln, wo ein falscher Wert hoechstens ein Icon zu viel oder zu wenig
// zeigt.
export function stackVorhanden() {
  const da = !!document.querySelector('[data-blade-stack-target="container"]')
  if (da && !document.body.classList.contains("has-blade-stack")) {
    // Der Merker ist verlorengegangen, obwohl der Stapel steht. Die
    // Klick-Pfade haengen nicht mehr daran, die CSS-Regeln schon: also
    // zurechtruecken. Und EINMAL melden — beim naechsten Auftreten steht dann
    // der Ausloeser in der Konsole statt wieder nur die Wirkung.
    //
    // Der Fork meldet das an einen eigenen Befund-Sammler; den haben wir
    // hier nicht. Eine Konsolenzeile ist das ehrliche Minimum: besser als
    // still zurechtruecken, und sie kostet nichts.
    document.body.classList.add("has-blade-stack")
    if (!window.__stackMerkerGemeldet) {
      window.__stackMerkerGemeldet = true
      console.warn("has-blade-stack fehlte, obwohl ein Stack-Container im Dokument steht")
    }
  }
  return da
}
