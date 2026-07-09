# #926 Stufe 2 (Hans, 2026-07-09): {{key}}-Platzhalter im Vorlagen-/Body-Text
# einer druckbaren Entität. Wird VOR KnowledgeMarkdown.render auf dem
# Markdown-ROHTEXT ausgeführt (kollidiert so nicht mit [[…]]/((…))/[@…],
# die der KI-Renderer belegt). Keys matchen case-insensitiv und
# whitespace-tolerant gegen den merge_context der Entität — also auch
# gegen die Labels der freien Infoblock-Felder ("Kaltmiete" → {{kaltmiete}}).
#
# Unaufgelöste Platzhalter bleiben LITERAL stehen ({{key}} ist im gerenderten
# Dokument sichtbar) statt still zu Leerstring zu verschwinden — genau die
# „Wert verschwindet im Vertrag"-Angst aus #926. Der Editor zeigt sie
# zusätzlich als Warnung (unresolved).
class TemplateMerge
  PLACEHOLDER = /\{\{\s*([^{}\n]+?)\s*\}\}/

  # Label/Key auf die Vergleichsform bringen: getrimmt, lowercase,
  # Binnen-Whitespace kollabiert.
  def self.normalize_key(raw)
    raw.to_s.strip.downcase.gsub(/\s+/, " ")
  end

  # Platzhalter im Text aus dem Kontext füllen. context: {key => value}
  # mit bereits normalisierten Keys (siehe Printable#merge_context).
  def self.merge(text, context)
    return text.to_s if text.blank? || context.blank?
    text.to_s.gsub(PLACEHOLDER) do |match|
      value = context[normalize_key(Regexp.last_match(1))]
      value.nil? ? match : value.to_s
    end
  end

  # Die Platzhalter-Keys, die der Kontext NICHT füllt (für die Editor-Warnung).
  def self.unresolved(text, context)
    keys(text).reject { |k| context.key?(k) }
  end

  # Alle im Text vorkommenden Platzhalter-Keys (normalisiert, unique).
  def self.keys(text)
    text.to_s.scan(PLACEHOLDER).map { |(k)| normalize_key(k) }.uniq
  end
end
