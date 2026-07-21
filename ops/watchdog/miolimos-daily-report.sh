#!/usr/bin/env bash
# Taeglichen Betriebsbericht verschicken (#1076).
# Cron: 30 7 * * * /home/hans/bin/miolimos-daily-report.sh
#
# Duenner Wrapper um `rails ops:daily_report`. Er existiert nur, weil der
# Cron-Kontext zwei Dinge nicht hat, die eine interaktive Shell mitbringt:
#   1. die rbenv-Shims im PATH
#   2. das DB-Passwort
# Beides holt sich schon bin/deploy auf demselben Weg — das Passwort aus der
# Umgebung des laufenden systemd-Dienstes, damit es keine zweite Quelle der
# Wahrheit gibt.
set -euo pipefail

cd "$(dirname "$0")/../.."
export RAILS_ENV=production

BUNDLE=${BUNDLE:-/home/hans/.rbenv/shims/bundle}
LOG=${LOG:-/home/hans/log/miolimos-daily-report.log}
mkdir -p "$(dirname "$LOG")"
stamp() { date +"%Y-%m-%d %H:%M:%S"; }

if [[ -z "${MIOLIMOS_SRC_DATABASE_PASSWORD:-}" ]]; then
  pid="$(systemctl show miolimos_src.service --property=MainPID --value 2>/dev/null || true)"
  if [[ -n "$pid" && "$pid" != "0" && -r "/proc/$pid/environ" ]]; then
    pw="$(tr '\0' '\n' < "/proc/$pid/environ" | grep '^MIOLIMOS_SRC_DATABASE_PASSWORD=' | cut -d= -f2-)"
    [[ -n "$pw" ]] && export MIOLIMOS_SRC_DATABASE_PASSWORD="$pw"
  fi
fi

if out="$("$BUNDLE" exec rails ops:daily_report 2>&1)"; then
  echo "[$(stamp)] $out" >> "$LOG"
else
  # Bewusst nur ins Log: Wenn der Bericht nicht rausgeht, ist die Instanz
  # vermutlich ohnehin krank — dann meldet das AUSBLEIBEN der Mail den
  # Zustand, und der Sofortalarm haengt am Waechter, nicht hier.
  echo "[$(stamp)] FEHLGESCHLAGEN: $out" >> "$LOG"
  exit 1
fi
