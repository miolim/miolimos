require "test_helper"

# immoOS #1553: Anschriftfeld nach DIN 5008.
class PostalAddressTest < ActiveSupport::TestCase
  # #1553 (Hans): „In der Absender-Adresse und in der Empfänger-Adresse die
  # Landesbezeichnung, also DE oder Deutschland, weglassen."
  #
  # DIN 5008: Das Bestimmungsland gehört ins Anschriftfeld NUR bei Auslandspost.
  test "#1553: das Inland steht nicht im Anschriftfeld" do
    %w[DE de Deutschland DEUTSCHLAND Germany].each do |land|
      a = PostalAddress.new(line1: "Zum Ukleisee 2", postal_code: "23701", city: "Eutin", country: land)
      assert_equal ["Zum Ukleisee 2", "23701 Eutin"], a.lines, "#{land.inspect} gehört nicht ins Feld"
    end
  end

  test "#1553: das Ausland bleibt stehen" do
    a = PostalAddress.new(line1: "Rue de Rivoli 1", postal_code: "75001", city: "Paris", country: "FR")
    assert_equal ["Rue de Rivoli 1", "75001 Paris", "FR"], a.lines
  end

  test "#1553: ohne Land bleibt alles wie zuvor" do
    a = PostalAddress.new(line1: "Ahornallee 7", postal_code: "23701", city: "Eutin")
    assert_equal ["Ahornallee 7", "23701 Eutin"], a.lines
  end
end
