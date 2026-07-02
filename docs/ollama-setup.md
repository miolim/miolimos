# Phase 6a Setup — Email Classifier (bge-m3 + Ollama)

Der Classifier läuft lokal über **Ollama** mit dem multilingualen
Embedding-Modell **bge-m3**. Solange Ollama nicht installiert ist,
verhält sich der Sync genau wie bisher (Classifier-Calls fallen still
durch). Sobald Ollama steht, werden neue Mails und der Bestand
klassifiziert.

## Install

```bash
# einmal auf dem Server:
curl -fsSL https://ollama.com/install.sh | sh
ollama pull bge-m3

# Service sollte danach laufen:
systemctl is-active ollama      # → active
curl -s http://localhost:11434/api/tags | head -c 200
```

## Bestand retro klassifizieren

```bash
cd /path/to/miolimos
RAILS_ENV=production bundle exec rails communications:classify_all
```

Output:
```
Klassifiziere 140 Mails ohne Thema …
  10/140  auto=2  suggest=5  skip=3
  ...
Fertig. auto=NN  suggest=MM  skip=PP
```

- **auto**: Score ≥ 0.70 und Margin ≥ 0.08 zum 2. Platz →
  Topic direkt verknüpft, `decided_at` gesetzt.
- **suggest**: Score ≥ 0.45 → Vorschlag im Detail-View, User
  entscheidet mit Übernehmen/Ablehnen.
- **skip**: darunter — keine Aktion, bleibt "Ohne Thema".

## Schwellwerte tunen

`app/services/classifiers/email_topic_suggester.rb`:

```ruby
AUTO_THRESHOLD    = 0.70
AUTO_MARGIN       = 0.08
SUGGEST_THRESHOLD = 0.45
```

## Environment-Überschreibung

```
OLLAMA_HOST=http://localhost:11434
OLLAMA_EMBED_MODEL=bge-m3
```

## Caching

Topic-Embeddings werden über `Rails.cache` gecacht. Key enthält
`topic.updated_at`, d.h. Änderungen am Themen-Namen oder der
Beschreibung invalidieren automatisch.

Mail-Embeddings werden nicht persistent gespeichert (zu viele
Vektoren, geringer Wiederverwendungs-Nutzen bei Hans' Volumen).
