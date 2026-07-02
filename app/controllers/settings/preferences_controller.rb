class Settings::PreferencesController < Settings::BaseController
  # #271: Vorlieben des aktuellen Actors. Schmal — Anzeige + Update.
  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def show
    redirect_to settings_path(stack: "list:settings,settings:preferences")
  end

  def update
    # #564: explizite Permit-Liste statt permit! — update_preferences filtert
    # zwar selbst, aber die Schlüssel sollen schon hier benannt sein.
    permitted = params.require(:preferences).permit(
      :locale, :wheel_preset, :sidebar_click_mode,
      :sidebar_recent_topics_count, :person_ki_title, card_widths: {}
    )
    # #768 (Hans): "Das bin ich" — Selbst-KI ist eine DB-Spalte, keine
    # Preference. Titel → Person-KI auflösen (leer = Verknüpfung lösen).
    if permitted.key?(:person_ki_title)
      title = permitted.delete(:person_ki_title).to_s.strip
      ki = title.present? ? KnowledgeItem.persons.where(deleted_at: nil)
                                         .where("LOWER(title) = ?", title.downcase).first : nil
      current_actor.update!(person_ki_uuid: ki&.uuid)
    end
    current_actor.update_preferences(permitted.to_h)
    redirect_to settings_preferences_path, notice: t("preferences.saved")
  end

  private

  def controller_resource_type
    "Actor"
  end

  def controller_action_to_capability
    case action_name
    when "update" then "update"
    else "read"
    end
  end
end
