# #271: Per-Actor User-Vorlieben (Card-Breiten, Wheel-Geschwindigkeit,
# Sidebar-Klick-Verhalten u.a.). jsonb statt Spalten-pro-Setting, damit
# Hinzufuegen weiterer Settings keine Migration mehr braucht.
class AddPreferencesToActors < ActiveRecord::Migration[8.1]
  def change
    add_column :actors, :preferences, :jsonb, default: {}, null: false
  end
end
