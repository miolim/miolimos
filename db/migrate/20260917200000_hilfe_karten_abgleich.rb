# immoOS #1658 Stufe 3: Die Programm-Texte gehören zum Programm und sollen
# zwischen den Instanzen wandern (geschrieben wird auf einer, gelesen auf
# beiden). Transportweg ist das Repository: db/help/<schluessel>.md.
#
# `program_digest` merkt sich den Text, wie er zuletzt mit dem Repository
# abgeglichen wurde. Nur solange der Text in der Datenbank noch genau dieser
# ist, darf ein Import ihn ersetzen — sonst stünde eine lokale Änderung auf
# dem Spiel.
class HilfeKartenAbgleich < ActiveRecord::Migration[8.1]
  def change
    add_column :help_cards, :program_digest, :string
  end
end
