require "application_system_test_case"

# immoOS #1591 (Hans): „Wenn man sich bei den Jahreszahlen in den Datumfeldern
# vertippt und einfach weitertippt, um die bisherige Eingabe zu überschreiben,
# geht das nicht, weil man anscheinend eine 6-stellige Nummer eingeben kann."
#
# Ohne `max` nimmt das Jahressegment sechs Ziffern an. `lib/date_input_max`
# setzt die Obergrenze zentral — auch an Feldern, die Turbo nachlädt. Ob das
# Tippen sich dann wirklich so verhält, zeigt nur der Browser.
class DatumsfeldJahr1591Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read create update delete])
    grant(@hans, "Actor", %w[read])
    login_as(@hans)
    @invoice = Invoice.create!(kind: :rechnung, direction: :eingehend, status: :entwurf, creator: @hans,
                               document_date: Date.new(2026, 9, 1))
  end

  def feld_wert(name)
    page.evaluate_script("document.querySelector('input[name=#{name}]').value")
  end

  # Capybaras `send_keys` erreicht die Segmente eines Datumsfelds in Cuprite
  # nicht (der Wert blieb in jeder Reihenfolge leer, auch ohne `max`). Die
  # Tastatur des Treibers tippt dagegen Zeichen für Zeichen ins fokussierte Feld.
  def tippe_in(name, text)
    page.execute_script("const f = document.querySelector('input[name=#{name}]'); f.value = ''; f.focus()")
    tastatur = page.driver.browser.keyboard
    text.each_char { |zeichen| tastatur.type(zeichen) }
  end

  test "Datumsfelder tragen die Obergrenze, auch nachgeladene" do
    visit "/invoices?stack=invoice:#{@invoice.id}"
    assert page.has_css?("[data-uuid='invoice:#{@invoice.id}']", wait: 10)

    # Die Card kommt über den Stack nach — also ein nachgeladenes Feld.
    assert page.has_css?("input[name=document_date][max='9999-12-31']", wait: 5),
           "das Datumsfeld der Card hat keine Obergrenze"
    ohne = page.evaluate_script(
      "document.querySelectorAll('input[type=date]:not([max]),input[type=datetime-local]:not([max]),input[type=month]:not([max])').length"
    )
    assert_equal 0, ohne, "Datumsfelder ohne Obergrenze auf der Seite"
  end

  test "ein vertipptes Jahr laesst sich durch Weitertippen ueberschreiben" do
    visit "/invoices?stack=invoice:#{@invoice.id}"
    assert page.has_css?("input[name=document_date][max]", wait: 10)

    # „15.03.2025" tippen — der Cursor steht danach im Jahr — und gleich ein
    # neues Jahr hinterher. Ohne Obergrenze wurde daraus 252027-03-15.
    tippe_in("document_date", "150320252027")

    wert = feld_wert("document_date")
    assert_equal "2027-03-15", wert, "Das zweite Jahr hat das erste nicht ersetzt"
  end
end
