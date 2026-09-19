# #1677 (aus immoOS #1658 übernommen; Hans dort): Hilfe-Card zu einer Programm-Card.
#
# Aufgerufen über das Fragezeichen im Card-Rücken; der Schlüssel ist die
# Karten-Art (`property`), optional mit Reiter (`property.settlement`).
#
# Lesen darf jeder, der das Programm bedient. Geschrieben wird getrennt: den
# oberen Bereich alle, den unteren nur Administratoren — das ist der ganze
# Unterschied zwischen „unsere Notiz" und „die Erklärung des Programms".
class HelpCardsController < ApplicationController
  # Die Hilfe gehört keinem Objekt. Autorisiert wird gegen KnowledgeItem-Read —
  # dieselbe Wahl wie bei der Eigentümer-Liste (#841): eine Sicht, kein Bestand.
  def controller_resource_type = "KnowledgeItem"

  before_action :set_help, except: %i[icons bezeichnungen symbole]

  # GET /help/:key — die Adresse EINER Hilfe (#1658 R3, Hans: „Der sollte auf
  # die konkrete Hilfe-Card verweisen."). Sie öffnet den Stapel mit dieser
  # Card; so ist der kopierte Link auch als Text lesbar: /help/property.
  def show
    redirect_to dashboard_path(stack: "help:#{@help.key}")
  end

  # GET /help/icons — die Symbol-Auswahl fürs Schreibfeld (#1658). Lädt erst,
  # wenn jemand sie aufklappt; 130 Symbole gehören nicht in jede Card.
  def icons
    # #1658 R11: Die Karten-Art wandert mit — die Suche nach Beschriftungen
    # gewichtet danach (siehe I18nBeschriftungen.suche).
    @bereich = params[:bereich].to_s.gsub(/[^a-z0-9_:]/, "")
    render "help_cards/icons", layout: false
  end

  # GET /help/bezeichnungen — welcher Schlüssel steckt hinter dieser
  # Beschriftung? (#1658 R6)
  #
  #   ?text=Wohnungsfläche gesamt&bereich=property  → exakt, Karten-Art gewichtet
  #   ?q=fläche                                     → Volltext für die Auswahl
  def bezeichnungen
    # #1658 R10: Vorwärts — der Editor kennt nur den Schlüssel und braucht den
    # Text, um ihn an Ort und Stelle zu zeigen. Nur die angefragten, nicht die
    # ganze Tabelle.
    if params[:keys].present?
      gefragt = params[:keys].to_s.split(",").first(100)
      return render json: { texte: gefragt.index_with { |k| I18nBeschriftungen.text(k) }.compact }
    end

    if params[:text].present?
      schluessel = I18nBeschriftungen.zu_text(params[:text], bereich: params[:bereich])
      render json: { treffer: schluessel.first(5).map { |k| { schluessel: k, text: I18nBeschriftungen.text(k) } },
                     eindeutig: schluessel.size == 1 }
    else
      treffer = I18nBeschriftungen.suche(params[:q], bereich: params[:bereich])
      render json: { treffer: treffer.map { |k, t| { schluessel: k, text: t } }, eindeutig: false }
    end
  end

  # GET /help/symbole?namen=copy,flame — die Zeichnungen zu genau diesen
  # Symbolen (#1658 R10). Der Editor zeigt Marker als Symbol an und hat die
  # SVGs nicht; alle 129 auf Verdacht zu schicken wäre Verschwendung.
  def symbole
    namen = params[:namen].to_s.split(",").first(60).grep(/\A[a-z0-9_-]{1,60}\z/)
    # `:ui:blade_copy:` nennt ein BEDIENELEMENT, nicht eine Bilddatei — welches
    # Symbol es trägt, sagt das Verzeichnis. Deshalb getrennt angefragt und
    # getrennt beantwortet; sonst zeigte der Editor für jedes Bedienelement
    # nichts (gemessen am 18.09.).
    elemente = params[:elemente].to_s.split(",").first(60).grep(UiElemente::SCHLUESSEL_RE)

    render json: { symbole: namen.index_with { |n| svg_inhalt(n) }.compact,
                   elemente: elemente.index_with { |e| svg_inhalt(UiElemente.icon_fuer(e)) }.compact }
  end

  # GET /help/:key/card
  def card
    render partial: "help_cards/blade_card", locals: { help: @help }, layout: false
  end

  # PATCH /help/:key — Autosave eines der beiden Bereiche.
  def update
    bereich = params[:bereich].to_s
    return head(:unprocessable_content) unless %w[user program].include?(bereich)
    # #1658: Der untere Bereich ist die Stimme des Programms. Wer ihn ändern
    # darf, entscheidet die Rolle — nicht die Sichtbarkeit der Card.
    return head(:forbidden) if bereich == "program" && !current_actor.admin?
    # #1677: Gäste lesen nur (#602 S3) — auch die gemeinsame Notiz schreiben sie
    # nicht. Im Fork gibt es die Gast-Rolle an dieser Stelle nicht.
    return head(:forbidden) if current_actor.respond_to?(:guest?) && current_actor.guest?

    @help.assign_attributes(bereich == "program" ? { program_body: params[:text] }
                                                 : { user_body: params[:text] })
    # Eine Hilfe ohne jeden Inhalt braucht keine Zeile — sie entsteht beim
    # ersten Schreiben und verschwindet, wenn beide Bereiche leer sind.
    if @help.inhalt?
      @help.save!
    elsif @help.persisted?
      @help.destroy!
    end
    # Nach dem Speichern steht wieder die Darstellung da — wie bei Aufgaben
    # und Antworten (#1658 R4). Das Ergebnis sehen ist der Sinn des Schreibens.
    render partial: "help_cards/blade_card", locals: { help: @help }, layout: false
  end

  private

  # Das Partial GERENDERT, nicht die Datei gelesen: Die Icon-Dateien beginnen
  # mit einem ERB-Kommentar („lucide: flame"), der sonst als Text im Editor
  # landete (gemessen am 18.09.).
  def svg_inhalt(name)
    return nil if name.blank? || !name.to_s.match?(/\A[a-z0-9_-]{1,60}\z/)
    return nil unless Rails.root.join("app/views/shared/icons/_#{name}.html.erb").exist?

    render_to_string(partial: "shared/icons/#{name}", formats: [:html])
  end

  def set_help
    key = params[:key].to_s
    return head(:bad_request) unless HelpCard::KEY_RE.match?(key)

    @help = HelpCard.fuer(key)
  end
end
