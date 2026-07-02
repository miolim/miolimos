# #203 Phase E.6: Actor-Avatare (Initials + Farbpalette).
module ActorsHelper
  # Initials-Bubble für Actor-Avatare. Ein bis zwei Buchstaben aus dem
  # Namen, in einem eingefärbten Kreis. Verwendet als Default, solange
  # AgentActor kein echtes Avatar-Feld hat.
  AVATAR_PALETTE = [
    %w[bg-indigo-100  text-indigo-700],
    %w[bg-emerald-100 text-emerald-700],
    %w[bg-amber-100   text-amber-700],
    %w[bg-rose-100    text-rose-700],
    %w[bg-sky-100     text-sky-700],
    %w[bg-fuchsia-100 text-fuchsia-700]
  ].freeze

  def actor_initials(actor)
    actor.name.to_s.split(/\s+/).map { |w| w[0] }.compact.first(2).join.upcase.presence || "?"
  end

  def actor_avatar_classes(actor)
    AVATAR_PALETTE[actor.id.to_i % AVATAR_PALETTE.size].join(" ")
  end
end
