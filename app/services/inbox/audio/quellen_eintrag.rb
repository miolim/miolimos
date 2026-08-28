require "digest"

module Inbox
  module Audio
    # #1492: Bibliographische Quelle für eine Audio-Adresse.
    #
    # Der YouTube-Weg hat dafür einen eigenen Upserter, der auf die
    # Video-ID baut (`yt-<id>`, CSL `motion_picture`). Eine Audiodatei hat
    # keine solche Kennung — hier ist die Adresse selbst die Identität.
    #
    # Warum überhaupt eine Quelle: Ohne sie entsteht ein Wissenselement
    # ohne Herkunft. Bei #1471 war genau das der Fehler, den niemand sah —
    # der Clip war da, die Quelle fehlte, und warum, stand nur im Log.
    #
    # CSL kennt `podcast` als eigenen Typ; das trifft es besser als
    # `webpage` (eine Folge ist keine Seite) und besser als
    # `motion_picture` (es ist kein Film).
    #
    # Hier wird bewusst NICHTS abgefangen. Der YouTube-Upserter verschluckt
    # jeden Fehler zu einem stillen `nil` — und genau das hat mich beim
    # Bauen eine halbe Stunde gekostet: Die Quelle entstand nicht, das
    # Wissenselement war trotzdem fertig, und der Grund stand nirgends.
    # Wer den Fehler auffangen will, tut das dort, wo er ihn auch
    # vermerken kann (siehe AudioTranscribe).
    class QuellenEintrag
      def self.call(meta, url, actor:)
        return nil if url.to_s.strip.empty?

        s = Source.find_or_initialize_by(slug: slug_fuer(url))
        s.assign_attributes(
          csl_type:      "podcast",
          title:         meta["title"].to_s.presence || url,
          publisher:     meta["uploader"].to_s.presence,
          issued_string: meta["upload_date"].to_s.presence,
          issued_date:   datum(meta["upload_date"]),
          accessed:      Date.current,
          language:      meta["language"].to_s.presence,
          url:           url,
          abstract:      meta["description"].to_s.presence,
          creator:       actor
        )
        s.save!
        # Der Herausgeber einer Folge ist die Sendung, nicht eine Person —
        # deshalb als Organisation verknüpft, wie beim YouTube-Kanal.
        Inbox::SourceCreatorLink.link_organization!(s, meta["uploader"].to_s.presence, actor: actor)
        s
      end

      # Die Adresse ist die Identität: Dieselbe Folge zweimal eingeworfen
      # ergibt dieselbe Quelle. Gekürzter Streuwert statt der Adresse
      # selbst, weil die Slug-Prüfung nur Kleinbuchstaben, Bindestriche,
      # Punkte und Unterstriche zulässt — und Feed-Adressen stecken voller
      # Prozentzeichen und Doppelpunkte (daran ist in #1471 schon einmal
      # eine Quelle gescheitert).
      def self.slug_fuer(url)
        "audio-#{Digest::SHA1.hexdigest(url.to_s.strip)[0, 12]}"
      end

      def self.datum(wert)
        return nil if wert.blank?
        Date.parse(wert.to_s)
      rescue Date::Error
        nil
      end
    end
  end
end
