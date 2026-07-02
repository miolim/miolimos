class SourceIdentifier < ApplicationRecord
  belongs_to :source

  # Identifier-Schemata mit Validierungs-Regex. Liste erweiterbar.
  # `:any` Schemes (z.B. "juris-id", proprietäre IDs) werden nur auf
  # Anwesenheit geprüft.
  SCHEMES = {
    "DOI"   => /\A10\.\d{4,9}\/.+\z/,
    "ISBN"  => /\A(?:\d{9}[\dX]|\d{13})\z/,           # 10- oder 13-stellig, X erlaubt
    "ISSN"  => /\A\d{4}-\d{3}[\dX]\z/,
    "ECLI"  => /\AECLI:[A-Z]{2}:[A-Z0-9.]+:\d{4}:[A-Z0-9.]+\z/,
    "ORCID" => /\A\d{4}-\d{4}-\d{4}-\d{3}[\dX]\z/,
    "ROR"   => /\A0[a-z0-9]{8}\z/,
    "PMID"  => /\A\d+\z/,
    "arXiv" => /\A\d{4}\.\d{4,5}(?:v\d+)?\z/,
    "URN"   => /\Aurn:[a-z0-9][a-z0-9-]{0,31}:.+\z/i
  }.freeze

  # Web/YouTube-IDs sind kein normierter URN, aber für miolimOS-Sources
  # praktisch — wir tagen sie als eigenes Schema, damit sie im Detail-
  # View nicht als "other" verschwinden. (#124)
  KNOWN_SCHEMES = (SCHEMES.keys + %w[juris-id ELI YouTube TED other]).freeze  # #778: TED-Talk-IDs

  validates :scheme, presence: true, inclusion: { in: KNOWN_SCHEMES }
  validates :value,  presence: true
  validate  :value_matches_scheme_regex

  private

  def value_matches_scheme_regex
    re = SCHEMES[scheme]
    return unless re
    # ISBN: Hyphens für Validation rauspolieren, in der DB bleibt's roh.
    candidate = scheme == "ISBN" ? value.to_s.delete("-") : value.to_s
    errors.add(:value, "passt nicht zum Format #{scheme}") unless candidate.match?(re)
  end
end
