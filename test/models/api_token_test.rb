require "test_helper"

# #1499 (Hans): „Wie lange gelten die Token und lassen sie sich einzeln
# zurueckziehen?" — vorher: unbegrenzt und nein.
class ApiTokenTest < ActiveSupport::TestCase
  setup do
    @agent = AgentActor.create!(name: "Test-Agent", email: "agent-#{SecureRandom.hex(3)}@test.local",
                                description: "Testzweck", active: true)
  end

  test "ein frisches Token gibt seinen Klartext genau einmal her" do
    t = ApiToken.issue!(actor: @agent, name: "Laptop")
    assert_match(/\A[0-9a-f]{64}\z/, t.token, "32 Byte Zufall als Hex")
    assert_nil ApiToken.find(t.id).token, "nach dem Nachladen ist er weg — auch fuer mich"
    assert_equal Actor.digest_api_token(t.token), t.token_digest,
                 "gespeichert wird nur der Pruefwert"
  end

  test "authenticate findet das Token ueber seinen Klartext" do
    t = ApiToken.issue!(actor: @agent, name: "Laptop")
    assert_equal t, ApiToken.authenticate(t.token)
    assert_nil ApiToken.authenticate("falsch")
    assert_nil ApiToken.authenticate(nil), "ein leeres Token ist kein Token"
    assert_nil ApiToken.authenticate(""),  "und ein leerer String erst recht"
  end

  # Der Kern von Hans' zweiter Frage: EINES zurueckziehen, die anderen
  # laufen weiter.
  test "ein zurueckgezogenes Token faellt aus, die anderen bleiben gueltig" do
    a = ApiToken.issue!(actor: @agent, name: "Laptop")
    b = ApiToken.issue!(actor: @agent, name: "Cron")

    a.revoke!

    assert_nil ApiToken.authenticate(a.token), "das zurueckgezogene gilt nicht mehr"
    assert_equal b, ApiToken.authenticate(b.token), "das andere schon"
    assert a.reload.revoked?
    refute b.reload.revoked?
  end

  test "zweimal zurueckziehen aendert den Zeitpunkt nicht" do
    t = ApiToken.issue!(actor: @agent, name: "Laptop")
    t.revoke!
    erst = t.reload.revoked_at
    t.revoke!
    assert_equal erst.to_i, t.reload.revoked_at.to_i
  end

  # Die erste Frage: Wie lange gilt es?
  test "ein abgelaufenes Token gilt nicht mehr" do
    t = ApiToken.issue!(actor: @agent, name: "Kurz", expires_at: 1.hour.ago)
    assert t.expired?
    assert_nil ApiToken.authenticate(t.token)
  end

  test "ohne Ablaufdatum gilt es weiter — aber sichtbar ohne" do
    t = ApiToken.issue!(actor: @agent, name: "Unbefristet")
    refute t.expired?
    assert_nil t.expires_at, "kein Ablauf ist ein Zustand, kein Versehen"
    assert_equal t, ApiToken.authenticate(t.token)
  end

  test "genau an der Grenze gilt es nicht mehr" do
    t = ApiToken.issue!(actor: @agent, name: "Grenzfall", expires_at: Time.current)
    assert_nil ApiToken.authenticate(t.token),
               "abgelaufen heisst abgelaufen, nicht noch eine Sekunde"
  end

  # Punkt 2: die Benutzungsspur. Ohne sie sieht man weder ein totes Token
  # noch eines, das jemand anderes benutzt.
  test "die Benutzung wird mitgeschrieben, ohne updated_at zu bewegen" do
    t = ApiToken.issue!(actor: @agent, name: "Laptop")
    assert_nil t.last_used_at, "vor der ersten Benutzung: nichts"
    vorher = t.updated_at

    t.benutzt!

    assert t.reload.last_used_at.present?
    assert_equal vorher.to_i, t.updated_at.to_i,
                 "eine Randnotiz darf das Token nicht wie geaendert aussehen lassen"
  end

  test "tage_ungenutzt unterscheidet nie-benutzt von heute-benutzt" do
    t = ApiToken.issue!(actor: @agent, name: "Laptop")
    assert_nil t.tage_ungenutzt, "nie benutzt ist nicht null Tage"

    t.update_column(:last_used_at, 40.days.ago)
    assert_equal 40, t.reload.tage_ungenutzt
  end

  test "ein Token braucht einen Namen — wofuer ist es sonst da?" do
    assert_raises(ActiveRecord::RecordInvalid) do
      ApiToken.create!(actor: @agent, token_digest: "x")
    end
  end
end
