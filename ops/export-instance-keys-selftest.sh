#!/usr/bin/env bash
# Selbsttest fuer export-instance-keys.sh — laeuft gegen ein Wegwerf-
# Verzeichnis, fasst also keine echten Schluessel an.
#
# Geprueft wird, worauf es bei einem Schluessel-Export ankommt:
#   - alle Instanzen werden gefunden (auch die ohne master.key)
#   - die Namen sagen, wozu die Datei gehoert
#   - die Kopien sind nur fuer den Eigentuemer lesbar
#   - ein leerer Suchbaum meldet sich, statt still nichts zu tun
#
# Verwendung: ops/export-instance-keys-selftest.sh   (Exit 0 = alles gruen)
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
target="$script_dir/export-instance-keys.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
check() { # check <beschreibung> <bedingung-als-exitcode>
  if [[ "$2" == "0" ]]; then
    echo "  ok   $1"
  else
    echo "  FAIL $1"
    failures=$((failures + 1))
  fi
}

# Zwei Rails-Instanzen (eine davon ohne credentials) plus eine, die ihre
# Geheimnisse in .env haelt — das Bild einer gewachsenen Maschine.
quelle="$tmp/quelle"
mkdir -p "$quelle/alpha/config" "$quelle/beta/config" "$quelle/gamma/.env"
echo "alpha-key"  > "$quelle/alpha/config/master.key"
echo "alpha-enc"  > "$quelle/alpha/config/credentials.yml.enc"
echo "beta-key"   > "$quelle/beta/config/master.key"
echo "SECRET=x"   > "$quelle/gamma/.env/production"

ziel="$tmp/ziel"
MIOLIMOS_KEY_SEARCH_ROOT="$quelle" "$target" "$ziel" > "$tmp/ausgabe" 2>&1

echo "Export:"
check "master.key der ersten Instanz, sprechend benannt"  "$([[ -f "$ziel/alpha.master.key" ]] && echo 0 || echo 1)"
check "credentials der ersten Instanz"                    "$([[ -f "$ziel/alpha.credentials.yml.enc" ]] && echo 0 || echo 1)"
check "Instanz ohne credentials wird nicht uebersprungen"  "$([[ -f "$ziel/beta.master.key" ]] && echo 0 || echo 1)"
check ".env-Instanz kommt mit"                            "$([[ -f "$ziel/gamma.env.production" ]] && echo 0 || echo 1)"
check "Uebersicht wird geschrieben"                       "$([[ -s "$ziel/UEBERSICHT.txt" ]] && echo 0 || echo 1)"

inhalt="$(cat "$ziel/alpha.master.key")"
check "Inhalt kommt unveraendert an"                      "$([[ "$inhalt" == "alpha-key" ]] && echo 0 || echo 1)"

rechte="$(stat -c '%a' "$ziel/alpha.master.key" 2>/dev/null || stat -f '%A' "$ziel/alpha.master.key")"
check "Kopie ist nur fuer den Eigentuemer lesbar (600)"    "$([[ "$rechte" == "600" ]] && echo 0 || echo 1)"

verz="$(stat -c '%a' "$ziel" 2>/dev/null || stat -f '%A' "$ziel")"
check "Zielverzeichnis ist zu (700)"                      "$([[ "$verz" == "700" ]] && echo 0 || echo 1)"

check "Loesch-Hinweis steht in der Ausgabe"               "$(grep -q 'loeschen' "$tmp/ausgabe" && echo 0 || echo 1)"

# Ein leerer Suchbaum ist ein Fehler, kein stiller Erfolg: Wer nichts
# exportiert bekommt und es nicht merkt, glaubt, er haette eine Sicherung.
echo "Leerer Suchbaum:"
mkdir -p "$tmp/leer"
if MIOLIMOS_KEY_SEARCH_ROOT="$tmp/leer" "$target" "$tmp/ziel2" > "$tmp/ausgabe2" 2>&1; then
  check "meldet sich mit Exit != 0" 1
else
  check "meldet sich mit Exit != 0" 0
fi

echo
if [[ "$failures" -eq 0 ]]; then
  echo "alles gruen"
else
  echo "$failures Fehler"
  exit 1
fi
