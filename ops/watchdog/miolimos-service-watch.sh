#!/usr/bin/env bash
# Waechter fuer die laufenden Instanzen (#1076).
# Cron: */5 * * * * /home/hans/bin/miolimos-service-watch.sh
#
# ZWECK. `Restart=always` faengt den Absturz, aber nicht den Fall „gestoppt
# und nie wieder gestartet". Genau der ist am 21.07.2026 eingetreten: die
# miolimmo-Produktivinstanz war von 07:34 bis 09:15 aus, und nichts hat
# Alarm geschlagen. Ein Zustand allein sagt das nicht — „antwortet nicht"
# sieht bei einer abgeschalteten Instanz genauso aus wie bei einer, die es
# noch gar nicht gibt. Erkennbar ist nur der UEBERGANG.
#
# REGEL (dieselbe wie beim DB-Backup, eine Ebene hoeher):
#   - hat einmal geantwortet und tut es nicht mehr  -> laut (DOWN)
#   - hat noch nie geantwortet                      -> still
#   - antwortet wieder                              -> laut (RECOVERED)
#   - ist weiterhin unten                           -> still (kein Dauerlaerm)
#
# Der Wächter ist bewusst ein reines Shell-Skript ohne Rails: Er muss auch
# dann laufen, wenn jede Instanz auf dieser Maschine tot ist.
set -euo pipefail

STATE_DIR=${STATE_DIR:-/home/hans/.local/state/miolimos-watch}
EVENT_LOG=${EVENT_LOG:-/home/hans/log/miolimos-service-watch.log}
CONF=${CONF:-/home/hans/.config/miolimos-watch.conf}
PROBE_TIMEOUT=${PROBE_TIMEOUT:-5}

# Instanz-Registry: name|port|pfad|datenverzeichnis
#
# AUSDRUECKLICH eine Liste, kein Portscan. Ein Scan sieht eine verschwundene
# Instanz nicht — er sieht nur weniger offene Ports, und „weniger" ist wieder
# das stille Ereignis. Nur gegen eine benannte Erwartung laesst sich „war da
# und ist weg" ueberhaupt formulieren.
#
# Geprueft wird 127.0.0.1, NICHT der oeffentliche Hostname: sonst mischt der
# Waechter App-Ausfall und Tunnel-Ausfall in dieselbe Meldung, und die erste
# Frage bei jedem Alarm waere „welches von beidem".
#
# Der Name ist der INSTANZname (nicht der Hostname) — er uebersteht eine
# Umbenennung nach aussen. Bei einer Instanz-Umbenennung gehoeren wie bei der
# DB-Liste BEIDE Seiten angefasst: neuer Name rein, alter raus. Bleibt der
# alte stehen, meldet er ab dem naechsten Lauf DOWN.
#
# Das Datenverzeichnis steht hier mit, damit es fuer die Dateisicherung eine
# Quelle gibt statt zweier, die auseinanderlaufen (Vorschlag immoos_builder).
# Leeres Feld heisst „hat kein eigenes": `monica` setzt kein
# MIOLIMOS_DATA_PATH und schreibt darum in den Default ~/miolimos, ist also
# ueber den miolimos-Eintrag abgedeckt. (Bis 21.07. stand hier
# /home/hans/miolimos_monica/data — ein Pfad, den es nie gab. Ich hatte ihn
# aus einer Recherche uebernommen, ohne ihn anzusehen, und zwar in genau der
# Datei, die ich als „die eine Quelle" bezeichnet habe.)
DEFAULT_INSTANCES="\
miolimos|3007|/up|/home/hans/miolimos
monica|3008|/up|
immoos|3105|/up|/home/hans/immoos_data
stocker|3106|/up|/home/hans/stocker_data"

INSTANCES=${WATCH_INSTANCES:-$DEFAULT_INSTANCES}

mkdir -p "$STATE_DIR" "$(dirname "$EVENT_LOG")"
STATE_FILE="$STATE_DIR/state"
touch "$STATE_FILE"

stamp() { date +"%Y-%m-%d %H:%M:%S"; }
now=$(date +%s)

# Zustand des Vorlaufs lesen: "name status last_ok_epoch"
declare -A prev_status prev_last_ok
while read -r n s l; do
  [[ -n "${n:-}" ]] || continue
  prev_status[$n]="$s"
  prev_last_ok[$n]="$l"
done < "$STATE_FILE"

declare -A new_status new_last_ok
events=()
new_down=0

while IFS='|' read -r name port path _datadir; do
  [[ -n "${name:-}" ]] || continue
  was="${prev_status[$name]:-unseen}"
  last_ok="${prev_last_ok[$name]:-0}"

  if curl -sf -o /dev/null --max-time "$PROBE_TIMEOUT" "http://127.0.0.1:${port}${path}"; then
    new_status[$name]=up
    new_last_ok[$name]=$now
    if [[ "$was" == "down" ]]; then
      down_for=$(( now - last_ok ))
      events+=("RECOVERED $name (Port $port) — war ${down_for}s nicht erreichbar")
    fi
  else
    if [[ "$was" == "up" ]]; then
      # Der Uebergang, auf den es ankommt.
      new_status[$name]=down
      new_last_ok[$name]="$last_ok"
      events+=("DOWN $name (Port $port) — zuletzt erreichbar $(date -d "@$last_ok" +'%Y-%m-%d %H:%M:%S')")
      new_down=1
    elif [[ "$was" == "down" ]]; then
      # Weiterhin unten: kein neuer Alarm, sonst stumpft er ab.
      new_status[$name]=down
      new_last_ok[$name]="$last_ok"
    else
      # Noch nie gesehen: still. Eine Instanz darf hier vorgetragen werden,
      # bevor es sie gibt — genau wie eine noch nicht angelegte DB im Backup.
      new_status[$name]=unseen
      new_last_ok[$name]=0
    fi
  fi
done <<< "$INSTANCES"

# Zustand schreiben (atomar, damit ein Abbruch keine halbe Datei hinterlaesst)
# Registry mitschreiben, damit der taegliche Bericht die Datenverzeichnisse
# gegen die Sicherung halten kann, ohne dieses Skript zu parsen. Eine Quelle,
# zwei Leser.
reg_tmp="$STATE_DIR/registry.$$"
while IFS='|' read -r name port path datadir; do
  [[ -n "${name:-}" ]] || continue
  printf '%s\t%s\t%s\n' "$name" "$port" "${datadir:-}"
done <<< "$INSTANCES" | sort > "$reg_tmp"
mv "$reg_tmp" "$STATE_DIR/registry"

tmp="$STATE_FILE.$$"
for n in "${!new_status[@]}"; do
  echo "$n ${new_status[$n]} ${new_last_ok[$n]}"
done | sort > "$tmp"
mv "$tmp" "$STATE_FILE"

# Ereignisse protokollieren. Ruhige Laeufe schreiben NICHTS — ein Protokoll,
# in dem jede Minute „alles gut" steht, verdeckt die eine Zeile, die zaehlt.
for e in "${events[@]}"; do
  echo "[$(stamp)] $e" >> "$EVENT_LOG"
done

# Sofortalarm nach aussen, nur bei einem NEUEN Ausfall und nur wenn
# konfiguriert. Bewusst derselbe Mechanismus wie beim Backup: ein Dienst
# ausserhalb dieser Maschine, damit die Meldung auch dann rausgeht, wenn hier
# alles steht. Der taegliche Bericht (rails ops:daily_report) ist die zweite,
# unabhaengige Schiene.
if [[ "$new_down" == "1" && -f "$CONF" ]]; then
  # shellcheck disable=SC1090
  source "$CONF"
  if [[ -n "${WATCH_ALERT_URL:-}" ]]; then
    curl -fsS -m 15 --retry 3 "${WATCH_ALERT_URL%/}/fail" -o /dev/null 2>>"$EVENT_LOG" || true
  fi
fi

exit 0
