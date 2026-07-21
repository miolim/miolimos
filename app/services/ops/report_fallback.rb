module Ops
  # Ersatzzustellung des Betriebsberichts (#1076).
  #
  # Greift nur, wenn der Mailversand scheitert. Der Bericht landet dann als
  # Wissenselement in miolimOS selbst — dem einzigen Kanal, der noch geht,
  # wenn die Mail steht, und dem, in den Hans ohnehin taeglich schaut.
  #
  # Warum das ueberhaupt noetig ist: Am 21.07.2026 war die Google-Credential
  # seit zehn Tagen abgelaufen. miolimOS konnte keine Mail mehr verschicken —
  # auch keinen Portal-Magic-Link — und niemand hat es bemerkt, weil der
  # Ausfall genau den Kanal betraf, ueber den er haette gemeldet werden
  # muessen. Ein Waechter braucht einen zweiten Weg nach draussen.
  class ReportFallback
    def initialize(report, actor:, reason: nil, now: Time.current)
      @report = report
      @actor  = actor
      @reason = reason
      @now    = now
    end

    def deliver!
      raise ArgumentError, "kein Actor fuer die Ersatzablage" if @actor.nil?

      FileProxy.create(
        actor:     @actor,
        title:     title,
        item_type: "note",
        content:   body,
        tags:      [ "betrieb" ]
      )
    end

    def title
      "Betriebsbericht #{@now.strftime('%d.%m.%Y')} (Mailversand gestoert)"
    end

    def body
      out = []
      out << "Dieser Bericht konnte **nicht per Mail** zugestellt werden und liegt deshalb hier."
      out << ""
      out << "Grund des Versandfehlers: `#{@reason}`" if @reason.present?
      out << ""
      out << "> #{@report.subject}"
      out << ""

      if @report.alerts.any?
        out << "## Auffälligkeiten"
        out << ""
        @report.alerts.each { |a| out << "- #{a}" }
        out << ""
      else
        out << "Ausser dem Versandfehler ist nichts zu berichten."
        out << ""
      end

      @report.sections.each do |section|
        out << "## #{section.title}"
        out << ""
        out << "```"
        out.concat(section.lines)
        out << "```"
        out << ""
      end

      out.join("\n")
    end
  end
end
