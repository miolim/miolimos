# #203 Phase E.6: Wann-Stufen (Eingang/Heute/Demnaechst/Spaeter).
module CommitmentsHelper
  # Wann-Stufen: Reihenfolge, Icon-Name, Label, Farbklassen.
  COMMITMENTS = [
    { key: "inbox", icon: "inbox",  label: "Eingang",   color: "text-slate-500"   },
    { key: "today", icon: "today",  label: "Heute",     color: "text-emerald-600" },
    { key: "soon",  icon: "soon",   label: "Demnächst", color: "text-blue-600"    },
    { key: "later", icon: "later",  label: "Später",    color: "text-violet-600"  }
  ].freeze
  COMMITMENT_BY_KEY = COMMITMENTS.each_with_object({}) { |c, h| h[c[:key]] = c }.freeze

  def commitment_meta(commitment)
    COMMITMENT_BY_KEY[commitment.to_s.presence || "inbox"] || COMMITMENT_BY_KEY["inbox"]
  end
end
