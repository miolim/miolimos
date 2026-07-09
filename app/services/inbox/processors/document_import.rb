module Inbox
  module Processors
    # #934 (Hans, 2026-07-09): Eingehende Dokumente (Scans, Dateien,
    # E-Mail-Anhänge) verarbeiten. Zweiphasig:
    #
    # Phase 1 (Analyse): ZUGFeRD-XML deterministisch lesen (ZugferdReader);
    # sonst das PDF direkt an Claude mit schema-erzwungenem JSON
    # (Typ-Erkennung + Rechnungsfelder + Aufgaben-Vorschläge). Ergebnis
    # landet via NeedsConfirmation im Review-Banner des Inbox-Blades —
    # bei Finanzdaten gehört ein Mensch vor die Persistenz.
    #
    # Phase 2 (nach Bestätigung, payload.confirm_import): Original-PDF als
    # Transcript-KI ablegen; bei Rechnungen zusätzlich eine Eingangsrechnung
    # (Invoice direction:eingehend) mit Positionen, gematchten/angelegten
    # Parteien und dem Original als Artefakt; gewählte Aufgaben anlegen.
    class DocumentImport < ProcessorBase
      def self.kind        = "document_import"
      def self.label       = "Dokument-Eingang (Rechnung/Anschreiben)"
      def self.description = "Erkennt den Dokumententyp (ZUGFeRD deterministisch, sonst LLM), extrahiert Rechnungsdaten und legt nach Review Beleg-KI + Eingangsrechnung + Aufgaben an."

      def self.applies?(item)
        %w[pdf_upload upload].include?(item.source_kind)
      end

      # Structured-Outputs-Schema für die LLM-Extraktion. Alle Objekte mit
      # additionalProperties:false + vollständigem required (API-Anforderung);
      # optionale Werte sind nullable via type-Array.
      EXTRACTION_SCHEMA = {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[doc_type title sender recipient_name invoice task_suggestions confidence],
        "properties" => {
          "doc_type" => { "type" => "string", "enum" => %w[rechnung anschreiben vertrag sonstiges] },
          "title" => { "type" => "string", "description" => "Kurzer Ablage-Titel: Absender + Gegenstand, z.B. 'Stadtwerke — Abschlagsrechnung Juli 2026'" },
          "sender" => {
            "type" => "object", "additionalProperties" => false,
            "required" => %w[name vat_id iban city],
            "properties" => {
              "name" => { "type" => %w[string null] },
              "vat_id" => { "type" => %w[string null], "description" => "USt-IdNr des Absenders, falls angegeben" },
              "iban" => { "type" => %w[string null], "description" => "IBAN des Absenders ohne Leerzeichen" },
              "city" => { "type" => %w[string null] }
            }
          },
          "recipient_name" => { "type" => %w[string null] },
          "invoice" => {
            "anyOf" => [
              { "type" => "null" },
              {
                "type" => "object", "additionalProperties" => false,
                "required" => %w[number issue_date due_date service_start service_end net_total gross_total payment_terms lines],
                "properties" => {
                  "number" => { "type" => %w[string null] },
                  "issue_date" => { "type" => %w[string null], "description" => "YYYY-MM-DD" },
                  "due_date" => { "type" => %w[string null], "description" => "Fälligkeit YYYY-MM-DD, falls angegeben" },
                  "service_start" => { "type" => %w[string null], "description" => "YYYY-MM-DD" },
                  "service_end" => { "type" => %w[string null], "description" => "YYYY-MM-DD" },
                  "net_total" => { "type" => %w[number null] },
                  "gross_total" => { "type" => %w[number null] },
                  "payment_terms" => { "type" => %w[string null], "description" => "Zahlungsbedingungen im Wortlaut, inkl. Skonto (z.B. '2% Skonto bei Zahlung binnen 10 Tagen, sonst 30 Tage netto')" },
                  "lines" => {
                    "type" => "array",
                    "items" => {
                      "type" => "object", "additionalProperties" => false,
                      "required" => %w[description quantity unit unit_price tax_rate],
                      "properties" => {
                        "description" => { "type" => "string" },
                        "quantity" => { "type" => %w[number null] },
                        "unit" => { "type" => %w[string null] },
                        "unit_price" => { "type" => %w[number null], "description" => "Netto-Einzelpreis" },
                        "tax_rate" => { "type" => %w[number null], "description" => "USt-Satz in Prozent" }
                      }
                    }
                  }
                }
              }
            ]
          },
          "task_suggestions" => { "type" => "array", "items" => { "type" => "string" },
                                  "description" => "Konkrete Folge-Aufgaben aus dem Dokument (max 3), z.B. 'Rechnung 4711 bis 15.08. zahlen'" },
          "confidence" => { "type" => "string", "enum" => %w[hoch mittel niedrig] }
        }
      }.freeze

      def process!(item, actor:)
        path = item.external_path.to_s
        raise "Dokument-Pfad fehlt am InboxItem" if path.empty?
        raise "Datei nicht gefunden: #{path}" unless File.exist?(path)

        if item.payload["confirm_import"]
          create_records!(item, actor: actor)
        else
          extraction = analyze(item, path, actor: actor)
          suggest_topic(item, extraction)
          if extraction["source"] == "zugferd"
            # #934 Stufe 2: deterministisch gelesene E-Rechnungen laufen ohne
            # Review durch — kein LLM-Risiko, die Invoice bleibt editierbar.
            # Standard-Prüf-/Zahl-Aufgabe kommt automatisch mit.
            item.update!(
              payload: item.payload.merge("confirmed_task_titles" => [default_invoice_task_title(extraction)]),
              result:  item.result.merge("confirmation" => { "reason" => "document_review", "extraction" => extraction, "auto" => true })
            )
            create_records!(item, actor: actor)
          else
            raise NeedsConfirmation.new(
              reason:     "document_review",
              extraction: extraction
            )
          end
        end
      end

      private

      # ── Phase 1: Analyse ────────────────────────────────────────────────

      def analyze(item, path, actor:)
        if pdf?(path) && ZugferdReader.available? && (data = ZugferdReader.extract(path))
          from_zugferd(data)
        else
          from_llm(item, path, actor: actor)
        end
      end

      def pdf?(path) = File.extname(path).downcase == ".pdf" || item_head_pdf?(path)

      def item_head_pdf?(path)
        File.open(path, "rb") { |f| f.read(5) } == "%PDF-"
      rescue
        false
      end

      # ZUGFeRD-Kernfelder in die einheitliche Extraktions-Struktur bringen.
      def from_zugferd(data)
        seller = data["seller"] || {}
        {
          "source"         => "zugferd",
          "doc_type"       => "rechnung",
          "title"          => [seller["name"], "Rechnung", data["number"]].compact_blank.join(" — "),
          "sender"         => { "name" => seller["name"], "vat_id" => seller["vat_id"],
                                "iban" => data["iban"], "city" => seller["city"] },
          "recipient_name" => data.dig("buyer", "name"),
          "invoice" => {
            "number"        => data["number"],
            "issue_date"    => data["issue_date"],
            "due_date"      => data["due_date"],
            "service_start" => data["service_start"],
            "service_end"   => data["service_end"],
            "net_total"     => data["net_total"],
            "gross_total"   => data["gross_total"],
            "payment_terms" => data["payment_terms"],
            "lines" => Array(data["lines"]).map do |l|
              { "description" => l["description"].to_s, "quantity" => l["quantity"],
                "unit" => l["unit"], "unit_price" => l["unit_price"], "tax_rate" => l["tax_rate"] }
            end
          },
          "task_suggestions" => [],
          "confidence"       => "hoch"
        }
      end

      def from_llm(item, path, actor:)
        raise "LLM-Extraktion für Nicht-PDF-Uploads noch nicht unterstützt (#{File.extname(path)})" unless pdf?(path)
        result = LlmActivity.track(
          kind:        :inbox_document_extract,
          actor:       actor,
          source_kind: "inbox_item",
          source_id:   item.id.to_s,
          input_summary: "PDF #{File.basename(path)} (#{File.size(path)} bytes)",
          model:       Llm::ChatClient::DEFAULT_ANTHROPIC_MODEL
        ) do |activity|
          output = Llm::ChatClient.complete(
            prompt:    extraction_prompt,
            system:    "Du bist ein präziser Dokumenten-Erfassungs-Assistent für ein deutsches Büro. Antworte ausschließlich mit dem geforderten JSON.",
            pdf_bytes: File.binread(path),
            schema:    EXTRACTION_SCHEMA,
            max_tokens: 4096,
            activity:  activity
          )
          raise "LLM lieferte leere Antwort" if output.blank?
          { output: output, result_kind: "inbox_item", result_id: item.id.to_s }
        end
        JSON.parse(result[:output]).merge("source" => "llm")
      end

      def extraction_prompt
        <<~PROMPT
          Analysiere das angehängte Dokument (eingegangener Scan/Brief/Beleg).
          Erfasse: Dokumententyp, Absender (mit USt-IdNr und IBAN, falls angegeben),
          Empfänger und — falls es eine Rechnung ist — alle Rechnungsfelder inklusive
          der einzelnen Positionen und die Zahlungsbedingungen im Wortlaut (Skonto,
          Zahlungsziel). Beträge als Dezimalzahlen (Punkt als Dezimaltrenner),
          Daten als YYYY-MM-DD. Werte, die im Dokument nicht vorkommen, sind null —
          nichts raten. Schlage maximal 3 konkrete Folge-Aufgaben vor (deutsch, kurz).
        PROMPT
      end

      # ── Phase 2: Anlage nach Bestätigung ────────────────────────────────

      def create_records!(item, actor:)
        extraction = (item.result.dig("confirmation", "extraction") || {})
        raise "Keine Extraktion am Item — bitte neu analysieren (Re-Run ohne Bestätigung)" if extraction.blank?

        ki = create_document_ki(item, extraction, actor: actor)
        record_result(item, knowledge_item: ki)

        invoice = nil
        if extraction["doc_type"] == "rechnung" && extraction["invoice"].present?
          invoice = create_incoming_invoice(item, extraction, actor: actor)
          item.update_column(:result, item.result.merge(
            "invoice" => { "id" => invoice.id, "display_name" => invoice.display_name }
          ))
        end

        create_tasks(item, extraction, ki, invoice, actor: actor)
      end

      def create_document_ki(item, extraction, actor:)
        title = extraction["title"].presence || item.display_title
        # #934 Stufe 2: gescannten PDFs ohne Textlayer für die Ablage-Kopie
        # einen unsichtbaren OCR-Textlayer verpassen (Strg+F im Viewer);
        # ohne ocrmypdf-Setup läuft der Schritt still als No-Op.
        Dir.mktmpdir("docimport") do |dir|
          source = (pdf?(item.external_path) && PdfOcr.add_text_layer(item.external_path, dir: dir)) ||
                   item.external_path
          File.open(source, "rb") do |io|
            FileProxy.create_with_file(actor: actor, title: title,
                                       uploaded_io: io, item_type: :transcript)
          end
        end
      end

      # #934 Stufe 2: Themen-Vorschlag für Dokumente ohne Mail-Kontext —
      # dieselbe Embedding-Klassifikation wie bei E-Mails, gegen Titel/
      # Absender/Typ der Extraktion. Nur der sichere AUTO-Fall wird
      # übernommen; ohne Ollama (oder bei vorgepflegten Themen) No-Op.
      def suggest_topic(item, extraction)
        return if item.topics.any?
        text = [extraction["title"], extraction.dig("sender", "name"),
                extraction["doc_type"]].compact_blank.join("\n")
        result = Classifiers::EmailTopicSuggester.new.suggest_text(text)
        return unless result[:decision] == :auto_assign && result[:top]
        InboxItemTopic.find_or_create_by!(inbox_item: item, topic: result[:top][:topic])
      rescue => e
        Rails.logger.warn("DocumentImport: Topic-Vorschlag fehlgeschlagen: #{e.class} #{e.message}")
      end

      # Titel der Standard-Aufgabe (identisch zum Review-UI, s. Locale-Key).
      def default_invoice_task_title(extraction)
        inv    = extraction["invoice"] || {}
        sender = extraction["sender"] || {}
        I18n.t("inbox_items.document_review.default_invoice_task",
               name: [sender["name"].presence, inv["number"].presence].compact.join(" "),
               due:  inv["due_date"].presence || "—")
      end

      def create_incoming_invoice(item, extraction, actor:)
        inv    = extraction["invoice"] || {}
        sender = extraction["sender"] || {}

        issuer    = match_or_create_org(sender, actor: actor)
        recipient = match_org(extraction["recipient_name"])   # uns nie automatisch anlegen

        invoice = Invoice.create!(
          kind:           :rechnung,
          direction:      :eingehend,
          status:         :entwurf,
          creator:        actor,
          issuer_uuid:    issuer&.uuid,
          recipient_uuid: recipient&.uuid,
          number:         inv["number"].presence,
          document_date:  parse_date(inv["issue_date"]),
          due_date:       parse_date(inv["due_date"]),
          service_start:  parse_date(inv["service_start"]),
          service_end:    parse_date(inv["service_end"]),
          topic_id:       item.topics.first&.id
        )
        Array(inv["lines"]).each_with_index do |l, i|
          invoice.invoice_lines.create!(
            description: l["description"].to_s,
            quantity:    decimal(l["quantity"], default: 1),
            unit:        l["unit"].to_s.presence,
            unit_price:  decimal(l["unit_price"]),
            tax_rate:    decimal(l["tax_rate"], default: 19),
            position:    i
          )
        end
        # #934 Stufe 2: Zahlungsbedingungen/Skonto als freies Infoblock-Feld —
        # strukturiert genug für Anzeige + {{merge}}, ohne verfrühtes Schema.
        if inv["payment_terms"].to_s.strip.present?
          invoice.document_fields.create!(label: "Zahlungsbedingungen",
                                          value: inv["payment_terms"].to_s.strip, position: 0)
        end
        # Original-PDF als Artefakt — der Beleg ist die Urkunde (#926-Schicht).
        invoice.document_artifacts.create!(pdf: File.binread(item.external_path),
                                           signed: false, creator: actor)
        invoice
      end

      # Absender matchen: erst über starke Identifier (USt-IdNr, IBAN),
      # dann Titel (case-insensitive); sonst Org-KI + Identifier anlegen.
      def match_or_create_org(sender, actor:)
        name = sender["name"].to_s.strip
        if (ki = match_by_identifier("USt-IdNr", sender["vat_id"]) ||
                 match_by_identifier("IBAN", sender["iban"]) ||
                 match_org(name))
          return ki
        end
        return nil if name.blank?
        ki = FileProxy.create(actor: actor, title: name, item_type: :organization, content: "")
        pos = 0
        { "USt-IdNr" => sender["vat_id"], "IBAN" => sender["iban"] }.each do |label, value|
          next if value.to_s.strip.blank?
          ki.identifiers.create!(label: label, value: value.to_s.strip, position: pos += 1)
        end
        ki
      end

      def match_by_identifier(label_pattern, value)
        v = value.to_s.gsub(/\s+/, "")
        return nil if v.blank?
        # #941: DB-seitig ebenfalls Leerzeichen strippen — IBANs werden oft
        # gruppiert gepflegt ("DE89 3704 …") und matchten sonst nie.
        ident = Identifier.where("REPLACE(value, ' ', '') ILIKE ?", v)
                          .detect { |i| i.knowledge_item&.item_type.in?(%w[person organization]) }
        ident&.knowledge_item
      end

      def match_org(name)
        n = name.to_s.strip
        return nil if n.blank?
        KnowledgeItem.persons_and_orgs.by_title_ci(n).first
      end

      def create_tasks(item, extraction, ki, invoice, actor:)
        titles = Array(item.payload["confirmed_task_titles"]).map(&:to_s).map(&:strip).reject(&:blank?)
        titles.each do |title|
          task = Task.create!(
            title:       title,
            description: "Beleg: [[#{ki.title}]]",
            creator:     actor,
            assignee:    actor,
            due_date:    invoice&.due_date
          )
          record_result(item, task: task)
        end
      end

      def parse_date(raw)
        Date.parse(raw.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def decimal(raw, default: 0)
        return BigDecimal(default.to_s) if raw.nil? || raw.to_s.strip.empty?
        BigDecimal(raw.to_s)
      rescue ArgumentError
        BigDecimal(default.to_s)
      end
    end
  end
end
