require "zip"

# #536 P4: statischer Export des Kundenportals — die Übergabe. Rendert
# DIESELBEN Templates wie das Live-Portal (Portal::Content als gemeinsame
# Quelle) ohne Login in selbst-enthaltene HTML-Seiten (CSS inline, kein JS)
# und packt sie mit den freigegebenen PDFs in eine versionierte ZIP.
# Läuft auf jedem statischen Host/Kundenserver ohne irgendwas.
class PortalExporter
  PAGES = {
    "index.html"       => "portal/pages/home",
    "roadmap.html"     => "portal/pages/roadmap",
    "termine.html"     => "portal/pages/termine",
    "dokumente.html"   => "portal/pages/dokumente",
    "nachrichten.html" => "portal/pages/nachrichten"
  }.freeze

  def self.zip(topic) = new(topic).zip
  def self.filename(topic)
    "portal-#{topic.slug}-#{Time.current.strftime('%Y-%m-%d-%H%M')}.zip"
  end

  def initialize(topic)
    @topic = topic
  end

  def zip
    files = render_pages
    Zip::OutputStream.write_buffer do |z|
      files.each do |name, content|
        z.put_next_entry(name)
        z.write(content)
      end
      Portal::Content.shared_artifacts(@topic).includes(:document).each do |art|
        z.put_next_entry("dokumente/#{artifact_filename(art)}")
        z.write(art.pdf)
      end
    end.string
  end

  # name => html für alle Seiten (auch einzeln testbar).
  def render_pages
    milestones = Portal::Content.milestones(@topic).to_a
    events     = Portal::Content.events(@topic).to_a
    artifacts  = Portal::Content.shared_artifacts(@topic).includes(document: :topic).to_a
    messages   = Portal::Content.messages(@topic).to_a

    assigns_by_page = {
      "index.html"       => { milestones: milestones, artifacts: artifacts.first(5),
                              messages: messages.last(3),
                              updated_at: [ milestones.map(&:updated_at).max,
                                            artifacts.map(&:created_at).max,
                                            messages.map(&:created_at).max ].compact.max },
      "roadmap.html"     => { milestones: milestones },
      "termine.html"     => { dated: milestones.select(&:due_date).sort_by(&:due_date), events: events },
      "dokumente.html"   => { artifacts: artifacts },
      "nachrichten.html" => { messages: messages }
    }

    PAGES.to_h do |name, template|
      html = renderer.render(
        template: template, layout: "layouts/portal",
        assigns: { export: true, export_topic: @topic }.merge(assigns_by_page[name])
      )
      [ name, html ]
    end
  end

  private

  def renderer
    @renderer ||= Portal::PagesController.renderer.new(
      http_host: ENV.fetch("PORTAL_HOST", "portal.miolim.de"), https: true
    )
  end

  def artifact_filename(art)
    base = (art.document.display_name.presence || "dokument-#{art.document_id}")
             .gsub(/\s+/, "-").gsub(/[^\p{Alnum}\-_.]/u, "")
    "#{base}-#{art.id}.pdf"
  end
end
