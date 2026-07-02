# Hilfs-Concern für Controller, die Slug-Felder als komma-getrennte Strings
# entgegennehmen (Task-Mentions, KnowledgeItem-Topics/Mentions, …).
#
# Akzeptiert:
#   - nil          → nil (Feld nicht gesetzt → nicht anfassen)
#   - String       → Split an Komma/Whitespace, Leerstrings raus
#   - Array        → wie-ist, Leerstrings raus
module SlugListParams
  extend ActiveSupport::Concern

  private

  def split_slugs(value)
    return nil if value.nil?
    return value.reject(&:blank?) if value.is_a?(Array)
    value.to_s.split(/[,\s]+/).reject(&:blank?)
  end
end
