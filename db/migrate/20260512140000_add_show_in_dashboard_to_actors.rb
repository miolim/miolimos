class AddShowInDashboardToActors < ActiveRecord::Migration[8.1]
  def change
    # #153 Follow-up: Pro Agent steuerbar, ob er als Sektion im Dashboard
    # erscheint. Default true (neue Agents tauchen direkt auf), Hans
    # haut Hintergrund-Bots (Email Classifier, TestBot) in der Daten-
    # Migration unten explizit aus.
    add_column :actors, :show_in_dashboard, :boolean, default: true, null: false

    reversible do |dir|
      dir.up do
        execute(<<~SQL)
          UPDATE actors
          SET show_in_dashboard = FALSE
          WHERE type = 'AgentActor'
            AND (LOWER(name) LIKE '%classifier%' OR LOWER(name) LIKE '%testbot%')
        SQL
      end
    end
  end
end
