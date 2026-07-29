#!/usr/bin/env bash
# #1220 (Hans): Sammelt die Schluessel aller Instanzen auf dieser Maschine
# in EIN Verzeichnis, sprechend benannt — zum Uebertragen in den
# Passwortmanager.
#
# Warum es das braucht: `config/master.key` und `config/credentials.yml.enc`
# liegen bewusst weder im Git noch im Backup. Laegen sie im Datenarchiv,
# schloesse die eine Backup-Passphrase alles auf — Daten und Schluessel im
# selben Behaelter. Ihre einzige Zweitschrift ist damit die Kopie im
# Passwortmanager, und die muss man von Hand anlegen. Genau dabei hilft
# dieses Skript: Es sucht die Dateien nicht jedes Mal neu zusammen und
# benennt sie so, dass spaeter erkennbar bleibt, wozu sie gehoeren.
#
# Verwendung:
#   ops/export-instance-keys.sh [zielverzeichnis]     # Vorgabe: ~/miolimos-schluessel
#
#   MIOLIMOS_KEY_SEARCH_ROOT=/pfad ops/export-instance-keys.sh
#       durchsucht ein anderes Basisverzeichnis (Vorgabe: das Home-Verzeichnis)
#
# Von einem anderen Rechner aus (das Skript laeuft auf der Instanz-Maschine,
# das Ergebnis holt man sich danach):
#   ssh <host> 'miolimos_src/ops/export-instance-keys.sh /tmp/schluessel'
#   scp -r <host>:/tmp/schluessel ~/Downloads/ && ssh <host> 'rm -rf /tmp/schluessel'
#
# Die Kopien sind Klartext-Geheimnisse. Nach dem Import in den
# Passwortmanager gehoeren sie geloescht — das Skript sagt das am Ende
# nochmal und legt alles nur fuer den Eigentuemer lesbar an.
set -euo pipefail

ziel="${1:-$HOME/miolimos-schluessel}"
suchwurzel="${MIOLIMOS_KEY_SEARCH_ROOT:-$HOME}"

umask 077                       # alles, was jetzt entsteht, ist 600/700
mkdir -p "$ziel"
chmod 700 "$ziel"

# Kurzer Fingerabdruck — dieselbe Rechnung wie im taeglichen Betriebsbericht
# (SHA-256, auf 12 Zeichen gekuerzt). Damit laesst sich spaeter pruefen, ob
# die Kopie im Passwortmanager noch zur Datei auf der Maschine passt.
fingerabdruck() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -c1-12
  else
    shasum -a 256 "$1" | cut -c1-12   # macOS
  fi
}

kopiert=0
uebersicht="$ziel/UEBERSICHT.txt"
: > "$uebersicht"
{
  echo "Schluessel-Export vom $(date '+%Y-%m-%d %H:%M')"
  echo "Quelle: $(hostname):$suchwurzel"
  echo
} >> "$uebersicht"

hole() { # hole <instanzname> <quelldatei> <zielname>
  local instanz="$1" quelle="$2" zielname="$3"
  [[ -f "$quelle" ]] || return 0
  cp "$quelle" "$ziel/$zielname"
  chmod 600 "$ziel/$zielname"
  printf '%-40s %s  (aus %s)\n' "$zielname" "$(fingerabdruck "$quelle")" "$quelle" >> "$uebersicht"
  echo "  $zielname"
  kopiert=$((kopiert + 1))
}

echo "Schluessel werden gesammelt nach: $ziel"

# Eine Instanz ist ein Verzeichnis mit config/master.key ODER
# config/credentials.yml.enc. -maxdepth 3 findet ~/<instanz>/config/<datei>,
# ohne sich in node_modules & Co. zu verlaufen.
while IFS= read -r datei; do
  instanz="$(basename "$(dirname "$(dirname "$datei")")")"
  case "$datei" in
    */master.key)          hole "$instanz" "$datei" "$instanz.master.key" ;;
    */credentials.yml.enc) hole "$instanz" "$datei" "$instanz.credentials.yml.enc" ;;
  esac
done < <(find "$suchwurzel" -maxdepth 3 -type f \
              \( -name master.key -o -name credentials.yml.enc \) \
              -path '*/config/*' 2>/dev/null | sort)

# Sonderfall: Instanzen ohne Rails-Credentials halten ihre Geheimnisse in
# einer .env-Datei (bei uns miolimos_monica). Ohne sie ist auch dort nichts
# wiederherstellbar, also gehoert sie in denselben Export.
while IFS= read -r datei; do
  instanz="$(basename "$(dirname "$(dirname "$datei")")")"
  hole "$instanz" "$datei" "$instanz.env.$(basename "$datei")"
done < <(find "$suchwurzel" -maxdepth 3 -type f -path '*/.env/*' 2>/dev/null | sort)

echo
if [[ "$kopiert" -eq 0 ]]; then
  echo "Nichts gefunden. Stimmt die Suchwurzel? ($suchwurzel)"
  exit 1
fi

echo "$kopiert Dateien. Uebersicht mit Fingerabdruecken: $uebersicht"
echo
echo "Diese Dateien sind Klartext-Geheimnisse:"
echo "  1. in den Passwortmanager uebernehmen (Dateianhang oder Inhalt)"
echo "  2. danach loeschen:  rm -rf \"$ziel\""
