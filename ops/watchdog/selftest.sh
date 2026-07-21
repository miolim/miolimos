#!/usr/bin/env bash
# Selbsttest fuer miolimos-service-watch.sh (#1076).
#
# Spielt die vier Uebergaenge mit einem ECHTEN kleinen HTTP-Server durch —
# kein Stub, kein Mock: hochfahren, abschiessen, wieder hochfahren. Genau der
# Ablauf, den der Waechter erkennen soll. Dazu eine zweite „Instanz" auf einem
# Port, an dem nie etwas lauscht: die muss still bleiben.
#
# Verwendung: ops/watchdog/selftest.sh   (Exit 0 = alles gruen)
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
target="$script_dir/miolimos-service-watch.sh"
tmp="$(mktemp -d)"
srv_pid=""
cleanup() { [[ -n "$srv_pid" ]] && kill "$srv_pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT

failures=0
check() {
  if [[ "$2" == "0" ]]; then echo "  ok   $1"; else echo "  FAIL $1"; failures=$((failures + 1)); fi
}

# Zwei freie Ports besorgen, ohne zu raten.
free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }
port_live=$(free_port)
port_never=$(free_port)

# Der Server liefert eine Datei namens „up" aus -> GET /up ergibt 200.
mkdir -p "$tmp/www"
: > "$tmp/www/up"

start_server() {
  ( cd "$tmp/www" && exec python3 -m http.server "$port_live" --bind 127.0.0.1 >/dev/null 2>&1 ) &
  srv_pid=$!
  for _ in $(seq 1 50); do
    curl -sf -o /dev/null --max-time 1 "http://127.0.0.1:$port_live/up" && return 0
    sleep 0.1
  done
  echo "  FAIL Testserver kam nicht hoch"; exit 1
}
stop_server() {
  [[ -n "$srv_pid" ]] || return 0
  kill "$srv_pid" 2>/dev/null || true
  wait "$srv_pid" 2>/dev/null || true
  srv_pid=""
  for _ in $(seq 1 50); do
    curl -sf -o /dev/null --max-time 1 "http://127.0.0.1:$port_live/up" || return 0
    sleep 0.1
  done
  echo "  FAIL Testserver ging nicht aus"; exit 1
}

log="$tmp/events.log"
run_watch() {
  STATE_DIR="$tmp/state" EVENT_LOG="$log" CONF="$tmp/keine.conf" PROBE_TIMEOUT=2 \
  WATCH_INSTANCES="testdienst|$port_live|/up|$tmp/daten
niedagewesen|$port_never|/up|" \
    bash "$target"
}
events() { if [[ -f "$log" ]]; then wc -l < "$log"; else echo 0; fi; }

echo "Lauf 1: Dienst laeuft, erstmalig gesehen"
start_server
run_watch
check "keine Ereignisse bei gesundem Erstlauf" "$([[ $(events) -eq 0 ]] && echo 0 || echo 1)"
grep -q "^testdienst up" "$tmp/state/state"; check "Zustand: testdienst up" "$?"
grep -q "^niedagewesen unseen" "$tmp/state/state"; check "Zustand: niedagewesen unseen" "$?"

echo "Lauf 2: Dienst abgeschaltet — MUSS laut werden"
stop_server
run_watch
grep -q "DOWN testdienst" "$log"; check "DOWN wird gemeldet" "$?"
grep -q "zuletzt erreichbar" "$log"; check "letzter Erfolgszeitpunkt steht dabei" "$?"
! grep -q "niedagewesen" "$log"; check "nie dagewesener Dienst bleibt still" "$?"
check "genau ein Ereignis" "$([[ $(events) -eq 1 ]] && echo 0 || echo 1)"

echo "Lauf 3: weiterhin aus — darf NICHT nachlegen"
run_watch
check "kein zweiter Alarm" "$([[ $(events) -eq 1 ]] && echo 0 || echo 1)"

echo "Lauf 4: Dienst wieder da"
start_server
run_watch
grep -q "RECOVERED testdienst" "$log"; check "RECOVERED wird gemeldet" "$?"
check "genau zwei Ereignisse insgesamt" "$([[ $(events) -eq 2 ]] && echo 0 || echo 1)"

echo "Lauf 5: wieder ruhig"
run_watch
check "gesunder Lauf schreibt nichts nach" "$([[ $(events) -eq 2 ]] && echo 0 || echo 1)"

echo
if [[ $failures -eq 0 ]]; then
  echo "alle Pruefungen gruen"
else
  echo "$failures Pruefung(en) fehlgeschlagen"
  exit 1
fi
