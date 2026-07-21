#!/usr/bin/env bash
# Testlauf in einem FRISCHEN Klon — beantwortet die eine Frage, die ein Lauf
# im Arbeitsverzeichnis grundsaetzlich nicht beantworten kann.
#
# Aufruf: ops/fresh-clone-check.sh [remote]     (Vorgabe: origin)
#
# WOZU. Das Deploy-Gate laeuft im Arbeits-Checkout: mit `config/master.key`,
# mit gewachsenem `tmp/`, mit der Umgebung der aufrufenden Shell, mit einem
# `~/miolimos`, das seit Monaten benutzt wird. Ein Test, der stillschweigend
# eine dieser Eigenschaften voraussetzt, ist dort immer gruen — und rot, sobald
# jemand das Repo klont. Fuer ein Projekt, das sich als selbst-hostbar
# beschreibt, ist genau das der Fall, der zaehlt.
#
# Zwei Beispiele vom 21.07.2026, beide an einem Vormittag:
#   - Die Suite hing an MIOLIMOS_HOST aus der aufrufenden Shell. Unsichtbar,
#     weil der Host dieser Installation zufaellig dem Testwert entspricht.
#   - Ein Mailer-Test war nur gruen, weil im Checkout ein master.key lag; die
#     Datei ist gitignoriert und fehlt in jedem frischen Klon.
# Beide waeren hier aufgefallen, keiner im Deploy-Gate.
#
# Ersetzt die CI NICHT — die prueft zusaetzlich auf einer fremden Maschine mit
# frisch installierten Paketen. Dies ist das, was man selbst tun kann, und es
# kostet ein paar Minuten.
set -euo pipefail

REMOTE=${1:-origin}
SRC="$(cd "$(dirname "$0")/.." && pwd)"
URL="$(git -C "$SRC" remote get-url "$REMOTE")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "── Klon-Probe gegen $REMOTE ($URL)"
GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}" \
  git clone -q --depth 1 "$URL" "$TMP/klon"

cd "$TMP/klon"

# Die gitignorierten Dateien duerfen hier NICHT auftauchen — sonst prueft die
# Probe nichts. Ausdruecklich nachsehen statt annehmen.
for f in config/master.key config/credentials.yml.enc; do
  if [[ -e "$f" ]]; then
    echo "   FEHLER: $f liegt im Klon — dann ist es nicht gitignoriert, und"
    echo "           diese Probe waere wertlos. Abbruch."
    exit 1
  fi
done
echo "   ok: keine Schluessel im Klon"

# Gems aus dem Arbeitsverzeichnis mitbenutzen. Das ist bewusst KEIN frisches
# `bundle install`: geprueft werden soll die Abhaengigkeit vom Checkout-Zustand,
# nicht die Installierbarkeit der Pakete — die deckt die CI ab, und ein
# vollstaendiger Neuaufbau dauert ein Vielfaches.
if [[ -d "$SRC/vendor/bundle" ]]; then
  bundle config set --local path "$SRC/vendor/bundle" >/dev/null
  echo "   Gems aus $SRC/vendor/bundle"
fi

echo "── Suite"
RAILS_ENV=test bin/rails db:test:prepare
RAILS_ENV=test bin/rails test

echo "── Klon-Probe gruen"
