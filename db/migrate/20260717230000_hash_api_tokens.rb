# #1052: API-Bearer-Tokens nur noch als SHA256-Digest speichern (wie
# GitHub-PATs). Bestehende Klartext-Tokens werden beim Hochziehen gehasht —
# die Agenten senden weiter ihr Klartext-Token, der Server vergleicht
# Digests; für laufende Integrationen ändert sich nichts. Danach fliegt
# die Klartext-Spalte. Irreversibel (Hash lässt sich nicht zurückrechnen);
# beim Rollback müssten alle Tokens rotiert werden.
class HashApiTokens < ActiveRecord::Migration[8.1]
  def up
    add_column :actors, :api_token_digest, :string
    add_index  :actors, :api_token_digest, unique: true

    say_with_time "backfill api_token_digest from plaintext tokens" do
      select_rows("SELECT id, api_token FROM actors WHERE api_token IS NOT NULL").each do |id, token|
        digest = Digest::SHA256.hexdigest(token)
        update("UPDATE actors SET api_token_digest = #{connection.quote(digest)} WHERE id = #{id.to_i}")
      end
    end

    remove_column :actors, :api_token
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
