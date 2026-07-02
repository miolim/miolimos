# Übersetzt die rohen ParamHashes vom Edit-Formular in saubere
# Keyword-Args für `FileProxy.update`. Insbesondere die drei nested
# Array-Felder (Affiliations / Relationships / Contact-Points) brauchen
# Filterung leerer Zeilen, Key-Stringifizierung und kleine Werte-
# Normalisierung — das Form-Object kapselt dieses Geknete.
#
# Bewusst KEIN ActiveModel::Validations: die Validierung passiert
# weiterhin am KnowledgeItem-Datensatz; das Form-Object ist nur
# Datenmuncher.
class KnowledgeItemUpdateForm
  SCALAR_FIELDS = %i[
    title content item_type source source_url chat_title parent_org
    first_name last_name
  ].freeze

  SLUG_LIST_FIELDS = %i[topics contacts tags].freeze

  def initialize(params)
    @params = params
  end

  # Liefert ein Hash, das 1:1 als `**form.to_update_args` an
  # `FileProxy.update` (zusammen mit actor:/knowledge_item:) gegeben
  # werden kann. Felder, die im Submit nicht enthalten waren, fehlen
  # im Hash — FileProxy.update behandelt fehlende Keys als „nicht
  # ändern".
  def to_update_args
    args = {}
    SCALAR_FIELDS.each do |key|
      args[key] = @params[key] if @params.key?(key)
    end
    SLUG_LIST_FIELDS.each do |key|
      args[key] = split_slugs(@params[key]) if @params.key?(key)
    end
    args[:aliases]        = parse_aliases(@params[:aliases]) if @params.key?(:aliases)
    args[:affiliations]   = normalize_affiliations(@params[:affiliations])     if @params.key?(:affiliations)
    args[:contact_points] = normalize_contact_points(@params[:contact_points]) if @params.key?(:contact_points)
    args[:relationships]  = normalize_relationships(@params[:relationships])   if @params.key?(:relationships)
    # #532: Aussteller-Checkbox (Rails sendet Hidden "0" + Checkbox "1").
    args[:issuer] = ActiveModel::Type::Boolean.new.cast(@params[:issuer]) if @params.key?(:issuer)
    args
  end

  private

  def parse_aliases(value)
    return nil if value.nil?
    return value.reject(&:blank?) if value.is_a?(Array)
    value.to_s.split(/\s*,\s*/).reject(&:blank?)
  end

  def split_slugs(value)
    return nil if value.nil?
    return value.reject(&:blank?) if value.is_a?(Array)
    value.to_s.split(/[,\s]+/).reject(&:blank?)
  end

  def normalize_affiliations(arr)
    return nil if arr.nil?
    Array(arr).filter_map do |row|
      row = permit_to_hash(row, %i[org role from to primary])
      next nil if row["org"].to_s.strip.empty?
      {
        "org"     => row["org"].to_s.strip,
        "role"    => row["role"].to_s.strip,
        "from"    => row["from"].presence,
        "to"      => row["to"].presence,
        "primary" => row["primary"].in?(["1", "true", true])
      }.compact
    end
  end

  def normalize_relationships(arr)
    return nil if arr.nil?
    Array(arr).filter_map do |row|
      row = permit_to_hash(row, %i[to kind from to_at])
      next nil if row["to"].to_s.strip.empty? || row["kind"].to_s.strip.empty?
      {
        "to"    => row["to"].to_s.strip,
        "kind"  => row["kind"].to_s.strip,
        "from"  => row["from"].presence,
        "to_at" => row["to_at"].presence
      }.compact
    end
  end

  def normalize_contact_points(arr)
    return nil if arr.nil?
    Array(arr).filter_map do |row|
      row   = permit_to_hash(row, %i[kind label value])
      kind  = row["kind"].to_s.strip.downcase.presence || "email"
      value = row["value"].to_s.strip
      next nil if value.empty?
      {
        "kind"  => kind,
        "label" => row["label"].to_s.strip,
        "value" => value
      }
    end
  end

  def permit_to_hash(row, keys)
    h = row.respond_to?(:permit) ? row.permit(*keys).to_h : row
    h.transform_keys(&:to_s)
  end
end
