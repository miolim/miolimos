# #1677 (aus immoOS #1658 übernommen; Hans dort): Hilfe-Cards — das Fragezeichen im Card-Rücken und die
# Zuordnung Card → Hilfe.
module HilfeHelper
  # Karten-Arten, die keine Hilfe brauchen: die Hilfe selbst (sie erklärt sich)
  # und die PDF-Vollansicht (sie ist ein Betrachter, keine Programmfunktion).
  OHNE_HILFE = %w[help pdfcard].freeze

  # Der Hilfe-Schlüssel einer Card: ihre ART, nicht der einzelne Datensatz.
  # Die Hilfe zur Grundstücks-Card gilt für jedes Grundstück.
  #
  #   "property:63"        → "property"
  #   "list:persons"       → "list:persons"
  #   "settlementdata:17"  → "settlementdata"
  #
  # Reiter-genaue Schlüssel („property.settlement") kommen in Stufe 2 dazu; das
  # Format ist schon darauf ausgelegt.
  def hilfe_schluessel(stack_id)
    id = stack_id.to_s
    return id if id.start_with?("list:") && id.count(":") == 1

    art = id.split(":").first.to_s
    # Eine UUID als erster Teil heißt: Wissens-Card ohne eigene Art.
    art = "ki" if art.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-/)
    art.presence
  end

  # Das Fragezeichen im Rücken — nil, wo es nichts zu erklären gibt.
  #
  # #1658 (Hans): „Vielleicht kann man das Icon noch etwas anders anzeigen, wenn
  # tatsächlich Text enthalten ist — damit man nicht ständig umsonst nach der
  # Hilfe schaut." Mit Inhalt kräftig und farbig, ohne blass. Weggelassen wird
  # es NICHT: Sonst gäbe es keinen Ort, an dem die Hilfe entstehen kann.
  def hilfe_spine_button(stack_id)
    key = hilfe_schluessel(stack_id)
    return nil if key.blank? || OHNE_HILFE.include?(key.split(".").first)

    gefuellt = hilfe_schluessel_mit_inhalt.include?(key)
    klasse = gefuellt ? "text-sky-600 hover:text-sky-700 hover:bg-sky-50" : "text-slate-300 hover:text-slate-500 hover:bg-slate-200"
    titel = t(gefuellt ? "hilfe.spine_vorhanden" : "hilfe.spine_leer")

    button_tag(type: "button", title: titel, "aria-label": titel,
               data: { controller: "help-link", "help-link-kind-value": "help",
                       "help-link-id-value": key, action: "click->help-link#append" },
               class: "spine-hilfe-icon shrink-0 p-0.5 rounded cursor-pointer bg-transparent border-0 #{klasse} [&_svg]:w-3.5 [&_svg]:h-3.5") do
      ui_icon(:hilfe)
    end
  end

  # Eine Abfrage je Seitenaufbau statt einer je Card.
  #
  # Auf Karten-Arten zusammengezogen: Der Server rendert das Fragezeichen, ohne
  # zu wissen, welcher Reiter gerade offen ist (das weiß nur der Browser). Also
  # heißt „gefüllt" hier: Zu dieser Karte gibt es Hilfe — allgemein oder zu
  # einem ihrer Reiter.
  def hilfe_schluessel_mit_inhalt
    @hilfe_schluessel_mit_inhalt ||=
      HelpCard.schluessel_mit_inhalt.map { |k| HelpCard.basis_schluessel(k) }.to_set
  end

  # Der Reiter heißt in der Hilfe, wie er auf der Karte heißt:
  # `hilfe.reiter.<art>.<reiter>`. Fehlt der Eintrag, steht der technische
  # Reitername da — ein Fork ergänzt seine Karten im selben Namensraum (im
  # immoOS-Fork stand hier eine Auflösung über dessen Immobilien-Schlüssel).
  def hilfe_reiter_label(reiter, art = nil)
    t("hilfe.reiter.#{art.to_s.tr(":", "_")}.#{reiter}", default: reiter.to_s.humanize)
  end

  # Alle Symbole, die das Programm kennt — für die Auswahl am Schreibfeld.
  # Gelesen wird das Verzeichnis der Icon-Partials; eine zweite Liste, die man
  # pflegen müsste, gäbe es sonst.
  def hilfe_icon_namen
    @hilfe_icon_namen ||= Dir.glob(Rails.root.join("app/views/shared/icons/_*.html.erb"))
                             .map { |p| File.basename(p, ".html.erb").delete_prefix("_") }
                             .select { |n| n.match?(/\A[a-z0-9_-]+\z/) }
                             .sort
  end

  # Wozu die Hilfe gehört — in der Hilfe-Card unter der Überschrift.
  def hilfe_bezug_label(key)
    basis = HelpCard.basis_schluessel(key)
    reiter = key.to_s.split(".")[1]
    name = t("hilfe.arten.#{basis.tr(":", "_")}", default: basis)
    return name if reiter.blank?

    t("hilfe.bezug_mit_reiter", art: name, reiter: hilfe_reiter_label(reiter, basis))
  end
end
