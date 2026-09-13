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
      :locale, :wheel_preset, :mail_compose, :start_stack,
      :sidebar_recent_topics_count, :person_ki_title, card_widths: {},
      sidebar_layout: {}, topbar_layout: {}
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
    # #1152: der Blade-Stack speichert die Standard-Kartenbreite per fetch —
    # der braucht eine schlanke Antwort statt der Redirect-Kette.
    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_to settings_preferences_path, notice: t("preferences.saved") }
    end
  end

  # #1500 (aus immoos uebernommen, Hans): „Ich würde gern als Admin diesen
  # Standard für neue Nutzer vorher auf meinen aktuellen Stand festlegen
  # können."
  #
  # Übernommen wird der eigene Stand, wie er GESPEICHERT ist — nicht das
  # Formular. Wer den Standard setzen will, speichert vorher; sonst legte man
  # halb Getipptes für alle künftigen Nutzer fest.
  #
  # Was NICHT mitgeht, geht von allein nicht mit: „Das bin ich" ist eine Spalte
  # am Actor, keine Vorliebe.
  def set_default
    Actor.global_defaults = current_actor.preferences
    redirect_to settings_preferences_path, notice: t("preferences.default_saved")
  end

  def reset_default
    Actor.reset_global_defaults!
    redirect_to settings_preferences_path, notice: t("preferences.default_reset")
  end

  private

  def controller_resource_type
    "Actor"
  end

  # #1500: Die beiden Standard-Actions wirken auf ALLE künftigen Nutzer — sie
  # verlangen deshalb das Recht, Nutzer anzulegen, und nicht bloß das Recht,
  # die eigenen Vorlieben zu ändern.
  def controller_action_to_capability
    case action_name
    when "set_default", "reset_default" then "create"
    when "update" then "update"
    else "read"
    end
  end
end
