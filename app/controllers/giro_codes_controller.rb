# #625 (Hans, 2026-06-14): Überweisungs-Formular. Kontakt (Empfänger) +
# Betrag + Verwendungszweck → live ein GiroCode (EPC069-12), den jede
# deutsche Banking-App scannen kann. Aufruf v.a. aus dem Personen-/Org-Blade
# (Banknote-Icon, ?contact_uuid=…); die IBAN lässt sich dabei direkt am
# Kontakt hinterlegen. Capability-Gate auf KnowledgeItem (read fürs Anzeigen,
# update fürs IBAN-Hinterlegen) statt einer eigenen Ressource.
class GiroCodesController < ApplicationController
  def show
    iban_uuids = Identifier.where("LOWER(label) LIKE ?", "%iban%")
                           .select(:knowledge_item_uuid)
    @contacts = KnowledgeItem.persons_and_orgs
                             .where(uuid: iban_uuids)
                             .order(:title)

    @contact_uuid = params[:contact_uuid].presence
    @amount       = params[:amount].presence
    @purpose      = params[:purpose].presence

    return if @contact_uuid.blank?

    @contact = KnowledgeItem.find_by(uuid: @contact_uuid)
    unless @contact
      @giro_error = "Kontakt nicht gefunden."
      return
    end

    ids          = @contact.identifiers.to_a
    @name        = @contact.title
    @stored_iban = ids.find { |i| i.label.to_s.downcase.include?("iban") }&.value
    @stored_bic  = ids.find { |i| i.label.to_s.downcase.match?(/\bbic\b|swift/) }&.value
    # Im Feld hat der getippte Wert (params) Vorrang vor dem hinterlegten.
    @iban = params[:iban].presence || @stored_iban
    @bic  = params[:bic].presence  || @stored_bic
    # „IBAN hinterlegen" anbieten, sobald der getippte Wert noch nicht
    # (genau so) am Kontakt gespeichert ist.
    @can_save_iban = @iban.present? && norm_iban(@iban) != norm_iban(@stored_iban)

    return if @iban.blank? # noch keine IBAN → nur das Eingabefeld zeigen

    amt = @amount.to_s.tr(",", ".").to_f
    begin
      @svg = GiroCode.svg(
        name:       @name,
        iban:       @iban,
        bic:        @bic,
        amount:     (amt.positive? ? amt : nil),
        remittance: @purpose,
        module_size: 6
      )
    rescue GiroCode::Error => e
      @giro_error = e.message
    end
  end

  # #625 (Hans): IBAN (und ggf. BIC) direkt aus dem Formular am Kontakt
  # hinterlegen — als Identifier „IBAN"/„BIC". POST → Capability update.
  def save_iban
    contact = KnowledgeItem.find_by(uuid: params[:contact_uuid])
    iban    = norm_iban(params[:iban])
    if contact && iban.present?
      upsert_identifier(contact, "IBAN", iban)
      bic = norm_iban(params[:bic])
      upsert_identifier(contact, "BIC", bic) if bic.present?
    end
    redirect_to giro_code_path(contact_uuid: params[:contact_uuid],
                               amount: params[:amount], purpose: params[:purpose])
  end

  private

  def upsert_identifier(contact, label, value)
    idf = contact.identifiers.find { |i| i.label.to_s.casecmp?(label) }
    if idf
      idf.update!(value: value)
    else
      pos = (contact.identifiers.map(&:position).compact.max || 0) + 1
      contact.identifiers.create!(label: label, value: value, position: pos)
    end
  end

  def norm_iban(v)
    v.to_s.gsub(/\s+/, "").upcase
  end

  # Tool arbeitet nur auf Kontakt-KIs — auf die KnowledgeItem-Capability
  # mappen (read fürs Anzeigen, update fürs save_iban) statt eine eigene
  # Ressource zu registrieren (sonst fail-closed 403, #564).
  def controller_resource_type = "KnowledgeItem"
end
