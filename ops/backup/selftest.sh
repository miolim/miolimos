#!/usr/bin/env bash
# Selbsttest fuer miolimos-db-backup.sh — braucht weder Postgres noch Netz.
#
# Getestet wird die Unterscheidung, die #1064 Nachtrag 2 eingefuehrt hat:
#   - DB fehlt und war noch nie da        -> stiller skip, errors=0
#   - DB fehlt, war aber frueher gesichert -> lautes MISSING, errors=1
# Dazu wird `pg_dump` per PATH durch einen Stub ersetzt, der sich wie Postgres
# bei einer unbekannten Datenbank verhaelt, und das Skript gegen ein
# Wegwerf-Verzeichnis gefahren (BACKUP_DIR/LOG/CONF sind ueberschreibbar).
#
# Verwendung: ops/backup/selftest.sh   (Exit 0 = alles gruen)
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
target="$script_dir/miolimos-db-backup.sh"
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

# pg_dump-Stub: meldet fuer JEDE Datenbank „does not exist" — so wie Postgres
# es tut. Der Wortlaut stammt aus einer echten Fehlermeldung.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/pg_dump" <<'STUB'
#!/usr/bin/env bash
db=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) db="$2"; shift 2 ;;
    *)  shift ;;
  esac
done
echo "pg_dump: error: connection to server failed: FATAL:  database \"$db\" does not exist" >&2
exit 1
STUB
chmod +x "$tmp/bin/pg_dump"

run_backup() { # run_backup <backup-dir> <log>
  BACKUP_DIR="$1" LOG="$2" CONF="$tmp/keine-konfig.conf" \
    PATH="$tmp/bin:$PATH" bash "$target"
}

# ── Fall 1: keine Vorgeschichte — jede fehlende DB ist still ────────────────
echo "Fall 1: fehlende DB ohne frueheren Dump"
d1="$tmp/leer"; l1="$tmp/leer.log"; mkdir -p "$d1"
run_backup "$d1" "$l1"
grep -q "skip miolimos_production (DB existiert nicht)" "$l1"; check "skip wird geloggt" "$?"
! grep -q "MISSING" "$l1"; check "kein MISSING" "$?"
grep -q "backup done (errors=0)" "$l1"; check "errors=0" "$?"

# ── Fall 2: DB war frueher gesichert und fehlt jetzt — muss laut sein ───────
echo "Fall 2: fehlende DB MIT frueherem Dump"
d2="$tmp/mit-vorlauf"; l2="$tmp/mit-vorlauf.log"; mkdir -p "$d2"
: > "$d2/miolimos_production-20260720-043001.dump"
run_backup "$d2" "$l2"
grep -q "MISSING miolimos_production" "$l2"; check "MISSING wird geloggt" "$?"
grep -q "zuletzt miolimos_production-20260720-043001.dump" "$l2"; check "letzter Dump wird benannt" "$?"
grep -q "backup done (errors=1)" "$l2"; check "errors=1" "$?"
grep -q "skip monica_production" "$l2"; check "DB ohne Vorlauf bleibt still" "$?"

# ── Fall 3: der leere Vorlauf darf nicht durch Fall 2 verschmutzt sein ──────
echo "Fall 3: Dump einer ANDEREN DB zaehlt nicht"
d3="$tmp/fremder-dump"; l3="$tmp/fremder-dump.log"; mkdir -p "$d3"
: > "$d3/pan_rp_production-20260720-043001.dump"
run_backup "$d3" "$l3"
! grep -q "MISSING" "$l3"; check "kein MISSING durch fremden Dump" "$?"

echo
if [[ $failures -eq 0 ]]; then
  echo "alle Pruefungen gruen"
else
  echo "$failures Pruefung(en) fehlgeschlagen"
  exit 1
fi
