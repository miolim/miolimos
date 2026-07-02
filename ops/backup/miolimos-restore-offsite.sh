#!/usr/bin/env bash
# Restore aus einem verschluesselten Off-Site-Backup (#545).
# Holt eine .gpg-Datei vom Remote, entschluesselt sie und (bei DB-Dumps)
# spielt sie optional in eine WEGWERF-DB zurueck — niemals direkt ueber Prod.
#
#   Liste:    ~/bin/miolimos-restore-offsite.sh list [b2:bucket|gdrive:dir]
#   Holen:    ~/bin/miolimos-restore-offsite.sh fetch <remote/datei.gpg> [zielordner]
#   Restore:  ~/bin/miolimos-restore-offsite.sh restore <datei.dump> <wegwerf_db>
set -euo pipefail

RCLONE=/home/hans/bin/rclone
CONF=/home/hans/.config/miolimos-backup.conf
[[ -f "$CONF" ]] && source "$CONF"
: "${BACKUP_PASSPHRASE_FILE:=/home/hans/.miolimos-backup-pass}"
: "${RCLONE_CONFIG:=/home/hans/.config/rclone/rclone.conf}"
export RCLONE_CONFIG
cmd=${1:-help}

case "$cmd" in
  list)
    remote=${2:?"remote angeben, z.B. b2:miolimos-backups"}
    "$RCLONE" lsl "$remote" | sort -k4
    ;;
  fetch)
    src=${2:?"Quelle angeben, z.B. b2:miolimos-backups/miolimos_production-YYYYMMDD-HHMMSS.dump.gpg"}
    dest=${3:-/tmp}
    base=$(basename "$src")
    "$RCLONE" copyto "$src" "$dest/$base"
    out="$dest/${base%.gpg}"
    gpg --batch --yes --decrypt --passphrase-file "$BACKUP_PASSPHRASE_FILE" -o "$out" "$dest/$base"
    rm -f "$dest/$base"
    echo "entschluesselt: $out"
    [[ "$out" == *.dump ]] && { echo "Inhalt:"; pg_restore -l "$out" | head -5; }
    ;;
  restore)
    dump=${2:?".dump-Datei angeben"}
    db=${3:?"WEGWERF-DB-Name angeben (wird angelegt!)"}
    echo "Lege DB '$db' an und spiele '$dump' zurueck (NICHT ueber Prod) …"
    createdb -h localhost "$db"
    pg_restore -h localhost -d "$db" --no-owner "$dump"
    echo "fertig — pruefe '$db', danach ggf.  dropdb $db"
    ;;
  *)
    grep -E "^#( |$)" "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
