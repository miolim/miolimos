# #384 Phase 2 (Hans, 2026-05-27): @-Mention-Resolver fuer App-Nutzer.
# Findet `@<slug>`-Patterns im KI-Body, loest sie zu Actor-Records auf
# und persistiert Mentions in `actor_mentions`. Render-Pfad ersetzt die
# Mention-Tokens durch klickbare Pills (`<a class="actor-mention">`).
#
# Slug-Konvention: `@<name-parameterized>`, z.B. `@hans-groth` fuer
# „Hans Groth". Whitespace + Sonderzeichen sind verboten; Slug-Match
# greift case-insensitive ueber Actor#name oder Email-Local-Part.
class KnowledgeMarkdown
  module ActorMentions
    # `@slug` — Slug ist `[a-z][a-z0-9_-]{1,40}`. Vorher MUSS Whitespace
    # oder Zeilenanfang stehen — KEINE Klammer (sonst kollidiert mit
    # Citations `[@source]` und Markdown-Links `(@…)`). Hinter dem Slug
    # darf nichts mehr stehen das slugfaehig waere.
    #
    # #519 (Hans, 2026-06-05): `>` ins Lookbehind — resolve() läuft auf dem
    # GERENDERTEN HTML; eine Mention am Absatz-Anfang steht dann direkt hinter
    # `<p>` (Zeichen `>`, kein Whitespace) und wurde sonst nicht gerendert.
    MENTION_RE = /(?:^|(?<=[\s>]))@([a-zA-Z][a-zA-Z0-9_-]{1,40})(?![a-zA-Z0-9_\-@.])/

    module_function

    # Extrahiert alle @-Mentions aus dem Body, loest sie zu Actor-IDs auf.
    # Returnt eine Array of Actor-Objects (eindeutig).
    def extract_actors(body)
      return [] if body.blank?
      slugs = body.scan(MENTION_RE).flatten.uniq
      return [] if slugs.empty?
      slugs.filter_map { |slug| Actor.find_by_mention_slug(slug) }.uniq(&:id)
    end

    # Render-Helper: ersetzt @-Mentions im (bereits gerenderten) HTML
    # durch klickbare Pills. Wird in KnowledgeMarkdown#render nach
    # Wikilinks aufgerufen — analog zu Citations / References.
    def resolve(html)
      # #519: außerhalb von Code UND Links — `@Name` in einem Personen-
      # Wikilink (`<a …>@Name</a>`) ist kein Actor-Mention.
      HtmlSpans.outside_code_and_links(html) do |segment|
      segment.gsub(MENTION_RE) do |match|
        slug   = Regexp.last_match(1)
        actor  = Actor.find_by_mention_slug(slug)
        if actor
          %(<span class="actor-mention" data-actor-id="#{actor.id}" ) +
            %(title="#{CGI.escapeHTML(actor.name)}">@#{CGI.escapeHTML(slug)}</span>)
        else
          # Nicht-aufloesbare Mentions: rot-dashed (analog Missing-Wikilink).
          %(<span class="actor-mention actor-mention-missing" ) +
            %(title="Kein App-Nutzer mit Slug @#{CGI.escapeHTML(slug)}">@#{CGI.escapeHTML(slug)}</span>)
        end
      end
      end
    end

    # Synct die `actor_mentions`-Join-Tabelle fuer ein KI: extrahiert
    # @-Mentions aus dem aktuellen Body und gleicht den DB-Stand ab.
    # Aufruf-Stelle: nach jedem KI-Save in FileProxy::Writer.
    # #587: Rueckgabe = die NEU hinzugekommenen Actor-IDs, damit der
    # Writer frisch erwaehnte Agenten poken kann (genau einmal pro
    # Mention, nicht bei jedem weiteren Edit desselben Bodies).
    def sync_for(item, body)
      return [] unless item&.persisted?
      desired_actor_ids = extract_actors(body).map(&:id)
      existing = ActorMention.where(knowledge_item_uuid: item.uuid)
      existing_ids = existing.pluck(:actor_id)

      (existing_ids - desired_actor_ids).each do |obsolete_id|
        existing.where(actor_id: obsolete_id).delete_all
      end

      (desired_actor_ids - existing_ids).filter_map do |new_id|
        ActorMention.create!(knowledge_item_uuid: item.uuid, actor_id: new_id)
        new_id
      rescue ActiveRecord::RecordNotUnique
        nil   # Race-Condition: jemand anders war schneller.
      end
    end
  end
end
