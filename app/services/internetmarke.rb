# #995: Frankierung per Deutsche-Post-Internetmarke. Die Marke (PNG mit
# Matrixcode) wird über die REST-API gekauft und ins DIN-Anschriftfeld
# gedruckt — sichtbar im Kuvert-Fenster, keine gesonderte Frankierung nötig.
module Internetmarke
  # Portoprodukte (national, Preise fest bis Ende 2026). Die productCodes
  # entsprechen dem ProdWS-Katalog; vor dem ersten Echt-Kauf per
  # Client#catalog gegen den Live-Katalog verifizieren (siehe Task #995).
  PRODUCTS = [
    { code: 1,  label: "Standardbrief", cents: 95 },
    { code: 11, label: "Kompaktbrief",  cents: 110 },
    { code: 21, label: "Großbrief",     cents: 180 },
    { code: 31, label: "Maxibrief",     cents: 290 }
  ].freeze

  def self.product(code) = PRODUCTS.find { |p| p[:code] == code.to_i }

  # Dummy-Marke zum Testen von Layout/Fensterposition ohne Portokasse.
  # Bewusst OHNE Post-Branding und mit quergestelltem MUSTER-Vermerk,
  # damit sie nie mit einer gültigen Frankierung verwechselt wird.
  module DummyStamp
    # Deterministisches Pseudo-Matrixmuster (kein echter Code).
    def self.matrix_rects
      cells = +""
      seed = 41
      8.times do |y|
        8.times do |x|
          seed = (seed * 75 + 74) % 65537
          next unless seed.odd?
          cells << %(<rect x="#{6 + x * 4}" y="#{6 + y * 4}" width="3.2" height="3.2"/>)
        end
      end
      cells
    end

    def self.svg(product)
      price = format("%.2f EUR", product[:cents] / 100.0).tr(".", ",")
      <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 170 44">
          <rect x="0.5" y="0.5" width="169" height="43" fill="#fff" stroke="#000" stroke-width="1" stroke-dasharray="3 2"/>
          <g fill="#000">#{matrix_rects}</g>
          <text x="44" y="16" font-family="Helvetica,Arial,sans-serif" font-size="9" fill="#000">INTERNETMARKE</text>
          <text x="44" y="27" font-family="Helvetica,Arial,sans-serif" font-size="7" fill="#000">#{product[:label]}</text>
          <text x="44" y="38" font-family="Helvetica,Arial,sans-serif" font-size="9" font-weight="bold" fill="#000">#{price}</text>
          <text x="118" y="27" font-family="Helvetica,Arial,sans-serif" font-size="11" font-weight="bold" fill="#b91c1c"
                transform="rotate(-12 118 27)">MUSTER</text>
          <text x="98" y="40" font-family="Helvetica,Arial,sans-serif" font-size="5.5" fill="#b91c1c">NICHT GÜLTIG — TESTDRUCK</text>
        </svg>
      SVG
    end

    def self.data_uri(product)
      "data:image/svg+xml;base64,#{Base64.strict_encode64(svg(product))}"
    end
  end
end
