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

# `grep -q …; check "$?"` sieht aus wie eine Pruefung, ist aber unter
# `set -e` keine: Schlaegt das grep fehl, bricht das Skript AB, statt FAIL
# zu melden und weiterzulaufen. Man sieht dann nur, wo es aufhoerte, und
# erfaehrt nichts ueber die restlichen Pruefungen. `pruefe` haelt den
# Ausdruck in einer Bedingung fest — dort ist ein Fehlschlag erlaubt.
pruefe() { # pruefe <beschreibung> <shell-ausdruck>
  if eval "$2" >/dev/null 2>&1; then check "$1" 0; else check "$1" 1; fi
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

# ── Fall 4/5: Datenverzeichnisse (#1076) ───────────────────────────────────
# Der Off-Site-Teil laeuft nur mit Konfig, Passphrase und rclone. gpg und tar
# sind echt, rclone wird gestubbt (kein Netz im Test).
cat > "$tmp/bin/rclone" <<'STUB'
#!/usr/bin/env bash
# Nimmt copy/delete entgegen und legt bei copy eine Marke ab, damit der Test
# sieht, WAS hochgeladen worden waere.
if [[ "${1:-}" == "copy" ]]; then
  echo "$(basename "$2")" >> "$RCLONE_SPY"
  [[ -n "${RCLONE_SPY_DIR:-}" ]] && cp "$2" "$RCLONE_SPY_DIR/"
fi
# #1472: Aufraeum-Aufrufe mitschreiben — der Test prueft, WIE lange was
# aufgehoben wird. Die ganze Zeile, damit Filter und Alter sichtbar sind.
if [[ "${1:-}" == "delete" ]]; then
  [[ -n "${RCLONE_DELETE_SPY:-}" ]] && echo "$*" >> "$RCLONE_DELETE_SPY"
  # Nur das Aufraeumen scheitern lassen, nicht den Upload — sonst pruefte
  # der Fehlerfall zwei Dinge auf einmal.
  [[ -n "${RCLONE_DELETE_FAIL:-}" ]] && { echo "rclone: simulierter Fehler" >&2; exit 1; }
fi
exit 0
STUB
chmod +x "$tmp/bin/rclone"

echo "$tmp/passphrase" > /dev/null
echo "testpassphrase" > "$tmp/pass"
cat > "$tmp/offsite.conf" <<CONF
RCLONE_REMOTES="testremote:eimer"
BACKUP_PASSPHRASE_FILE=$tmp/pass
CONF

echo "Fall 4: Datenverzeichnis wird verschluesselt hochgeladen"
d4="$tmp/mit-daten"; l4="$tmp/mit-daten.log"; mkdir -p "$d4"
mkdir -p "$tmp/daten/anhaenge" "$tmp/daten/.git" "$tmp/daten/_test-artifacts"
echo "ein wichtiger Beleg" > "$tmp/daten/anhaenge/rechnung.pdf"
echo "historie" > "$tmp/daten/.git/HEAD"
echo "muell" > "$tmp/daten/_test-artifacts/x.md"
export RCLONE_SPY="$tmp/hochgeladen.txt"; : > "$RCLONE_SPY"
export RCLONE_SPY_DIR="$tmp/hochgeladen"; mkdir -p "$RCLONE_SPY_DIR"
BACKUP_DIR="$d4" LOG="$l4" CONF="$tmp/offsite.conf" RCLONE="$tmp/bin/rclone"   SIGNING_DIR="$tmp/gibtsnicht" BACKUP_DATA_DIRS="testinstanz|$tmp/daten"   PATH="$tmp/bin:$PATH" bash "$target"
grep -q "ok testinstanz-data" "$l4"; check "Datenverzeichnis wird gesichert" "$?"
grep -q "testinstanz-data-.*\.tar\.gz\.gpg" "$RCLONE_SPY"; check "verschluesseltes Archiv wird hochgeladen" "$?"
[[ -z "$(ls "$d4"/*.tar.gz 2>/dev/null)" ]]; check "kein unverschluesseltes Archiv bleibt liegen" "$?"
[[ -z "$(ls "$d4"/*.gpg 2>/dev/null)" ]]; check "kein .gpg bleibt lokal liegen" "$?"

# Inhaltsprobe: entschluesseln und nachsehen, WAS drin ist. Ohne das prueft
# der Test nur, dass irgendein Archiv entstanden ist -- nicht, dass der
# Beleg drin und der Ballast draussen ist.
gpg --batch --yes --quiet --passphrase-file "$tmp/pass" -d \
    "$RCLONE_SPY_DIR"/testinstanz-data-*.tar.gz.gpg > "$tmp/entschluesselt.tar.gz" 2>/dev/null
inhalt="$(tar -tzf "$tmp/entschluesselt.tar.gz" 2>/dev/null)"
grep -q "anhaenge/rechnung.pdf" <<< "$inhalt"; check "der Beleg ist im Archiv" "$?"
! grep -q "\.git/" <<< "$inhalt"; check ".git ist ausgeschlossen" "$?"
! grep -q "_test-artifacts" <<< "$inhalt"; check "_test-artifacts ist ausgeschlossen" "$?"

echo "Fall 5: eingetragenes, aber fehlendes Datenverzeichnis ist ein Fehler"
d5="$tmp/fehlende-daten"; l5="$tmp/fehlende-daten.log"; mkdir -p "$d5"
BACKUP_DIR="$d5" LOG="$l5" CONF="$tmp/offsite.conf" RCLONE="$tmp/bin/rclone"   SIGNING_DIR="$tmp/gibtsnicht" BACKUP_DATA_DIRS="verschwunden|$tmp/niemals"   PATH="$tmp/bin:$PATH" bash "$target"
grep -q "FAILED verschwunden-data" "$l5"; check "fehlendes Verzeichnis wird gemeldet" "$?"
grep -q "backup done (errors=1)" "$l5"; check "errors=1" "$?"

echo "Fall 6: eigene Ausschlussliste je Eintrag (.git soll MITgesichert werden)"
d6="$tmp/eigene-ausschluesse"; l6="$tmp/eigene-ausschluesse.log"; mkdir -p "$d6"
export RCLONE_SPY="$tmp/hochgeladen6.txt"; : > "$RCLONE_SPY"
export RCLONE_SPY_DIR="$tmp/hochgeladen6"; mkdir -p "$RCLONE_SPY_DIR"
BACKUP_DIR="$d6" LOG="$l6" CONF="$tmp/offsite.conf" RCLONE="$tmp/bin/rclone" \
  SIGNING_DIR="$tmp/gibtsnicht" BACKUP_DATA_DIRS="mithistorie|$tmp/daten|_test-artifacts" \
  PATH="$tmp/bin:$PATH" bash "$target"
gpg --batch --yes --quiet --passphrase-file "$tmp/pass" -d \
    "$RCLONE_SPY_DIR"/mithistorie-data-*.tar.gz.gpg > "$tmp/e6.tar.gz" 2>/dev/null
inhalt6="$(tar -tzf "$tmp/e6.tar.gz" 2>/dev/null)"
grep -q "\.git/HEAD" <<< "$inhalt6"; check ".git ist bei eigener Liste DRIN" "$?"
! grep -q "_test-artifacts" <<< "$inhalt6"; check "_test-artifacts bleibt draussen" "$?"
grep -q "anhaenge/rechnung.pdf" <<< "$inhalt6"; check "der Beleg ist weiterhin drin" "$?"

echo "Fall 7: ohne drittes Feld gelten die Vorgabe-Ausschluesse"
d7="$tmp/vorgabe"; l7="$tmp/vorgabe.log"; mkdir -p "$d7"
export RCLONE_SPY="$tmp/hochgeladen7.txt"; : > "$RCLONE_SPY"
export RCLONE_SPY_DIR="$tmp/hochgeladen7"; mkdir -p "$RCLONE_SPY_DIR"
BACKUP_DIR="$d7" LOG="$l7" CONF="$tmp/offsite.conf" RCLONE="$tmp/bin/rclone" \
  SIGNING_DIR="$tmp/gibtsnicht" BACKUP_DATA_DIRS="ohnefeld|$tmp/daten" \
  PATH="$tmp/bin:$PATH" bash "$target"
gpg --batch --yes --quiet --passphrase-file "$tmp/pass" -d \
    "$RCLONE_SPY_DIR"/ohnefeld-data-*.tar.gz.gpg > "$tmp/e7.tar.gz" 2>/dev/null
inhalt7="$(tar -tzf "$tmp/e7.tar.gz" 2>/dev/null)"
! grep -q "\.git/" <<< "$inhalt7"; check "fehlendes drittes Feld schliesst .git aus" "$?"
grep -q "anhaenge/rechnung.pdf" <<< "$inhalt7"; check "der Beleg ist drin" "$?"

# ── Fall 8/9/10: gestaffelte Aufbewahrung (#1472) ──────────────────────────
# Hans: „Storage Cap Reached 100%." Grosse Datenarchive kurz, kleine
# Datenbank-Abzuege lang. Geprueft wird der Aufraeum-Aufruf selbst — was
# rclone loeschen SOLL, mit welchem Filter und ab welchem Alter.
echo "Fall 8: Datenarchive kurz, Dumps lang"
d8="$tmp/staffel"; l8="$tmp/staffel.log"; mkdir -p "$d8"
export RCLONE_SPY="$tmp/hochgeladen8.txt"; : > "$RCLONE_SPY"
export RCLONE_DELETE_SPY="$tmp/geloescht8.txt"; : > "$RCLONE_DELETE_SPY"
BACKUP_DIR="$d8" LOG="$l8" CONF="$tmp/offsite.conf" RCLONE="$tmp/bin/rclone" \
  SIGNING_DIR="$tmp/gibtsnicht" BACKUP_DATA_DIRS="testinstanz|$tmp/daten" \
  PATH="$tmp/bin:$PATH" bash "$target"

pruefe "Datenarchive werden eigens aufgeraeumt" \
       'grep -q -- "--include \*-data-\*.tar.gz.gpg" "$RCLONE_DELETE_SPY"'
pruefe "Datenarchive: 7 Tage" \
       'grep -qE -- "--min-age 7d .*--include" "$RCLONE_DELETE_SPY"'
pruefe "alles andere: 60 Tage" \
       'grep -qE -- "--min-age 60d .*--exclude \*-data-\*.tar.gz.gpg" "$RCLONE_DELETE_SPY"'
# Die Filter muessen komplementaer sein. Faende sich derselbe Filtertyp
# zweimal, fiele eine Gruppe durch beide Raster — und wuerde nie geloescht.
pruefe "genau ein Einschluss und ein Ausschluss" \
       '[ "$(grep -c -- "--include" "$RCLONE_DELETE_SPY")" = 1 ] &&
        [ "$(grep -c -- "--exclude" "$RCLONE_DELETE_SPY")" = 1 ]'
pruefe "Aufraeumen wird vermerkt" 'grep -q "retention ok" "'"$l8"'"'

echo "Fall 9: eigene Aufbewahrungsdauern schlagen durch"
d9="$tmp/staffel-konfig"; l9="$tmp/staffel-konfig.log"; mkdir -p "$d9"
cat > "$tmp/offsite9.conf" <<CONF
RCLONE_REMOTES="testremote:eimer"
BACKUP_PASSPHRASE_FILE=$tmp/pass
OFFSITE_RETENTION_DAYS=90
OFFSITE_DATA_RETENTION_DAYS=3
CONF
export RCLONE_SPY="$tmp/hochgeladen9.txt"; : > "$RCLONE_SPY"
export RCLONE_DELETE_SPY="$tmp/geloescht9.txt"; : > "$RCLONE_DELETE_SPY"
BACKUP_DIR="$d9" LOG="$l9" CONF="$tmp/offsite9.conf" RCLONE="$tmp/bin/rclone" \
  SIGNING_DIR="$tmp/gibtsnicht" BACKUP_DATA_DIRS="testinstanz|$tmp/daten" \
  PATH="$tmp/bin:$PATH" bash "$target"
pruefe "Datenarchive: 3 Tage" 'grep -q -- "--min-age 3d" "$RCLONE_DELETE_SPY"'
pruefe "Dumps: 90 Tage"      'grep -q -- "--min-age 90d" "$RCLONE_DELETE_SPY"'

echo "Fall 10: ein fehlgeschlagenes Aufraeumen ist ein Fehler"
# Vorher stand am Aufraeumen ein `|| true`. Ein Backup, das nicht aufraeumt,
# laeuft in die Speichergrenze — und gemerkt haette man es erst an der Mail
# des Anbieters. Genau daran haengt diese Aufgabe.
d10="$tmp/staffel-fehler"; l10="$tmp/staffel-fehler.log"; mkdir -p "$d10"
export RCLONE_SPY="$tmp/hochgeladen10.txt"; : > "$RCLONE_SPY"
unset RCLONE_DELETE_SPY
RCLONE_DELETE_FAIL=1 BACKUP_DIR="$d10" LOG="$l10" CONF="$tmp/offsite.conf" \
  RCLONE="$tmp/bin/rclone" SIGNING_DIR="$tmp/gibtsnicht" \
  BACKUP_DATA_DIRS="testinstanz|$tmp/daten" PATH="$tmp/bin:$PATH" bash "$target"
pruefe "Fehlschlag wird benannt"  'grep -q "retention FAILED" "'"$l10"'"'
pruefe "und zaehlt als Fehler"    'grep -q "backup done (errors=1)" "'"$l10"'"'
pruefe "der Upload lief trotzdem" 'grep -q "offsite ok" "'"$l10"'"'

echo
if [[ $failures -eq 0 ]]; then
  echo "alle Pruefungen gruen"
else
  echo "$failures Pruefung(en) fehlgeschlagen"
  exit 1
fi
