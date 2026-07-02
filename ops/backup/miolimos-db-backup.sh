#!/usr/bin/env bash
# Taeglich pg_dump fuer beide miolimOS-Prod-DBs + verschluesselte Off-Site-Kopie.
# Cron: 30 4 * * * /home/hans/bin/miolimos-db-backup.sh
#
# - Lokal: /home/hans/miolimos-backups/auto/<db>-YYYYMMDD-HHMMSS.dump
#   Custom-Format (pg_restore-faehig). Retention: 14 taeglich + 8 woechentlich.
# - Off-Site (#545, opt-in via ~/.config/miolimos-backup.conf): jeder Dump +
#   der AES-Signierschluessel werden gpg-symmetrisch (AES256) verschluesselt
#   und per rclone auf ein oder mehrere Remotes (Backblaze B2, Google Drive)
#   geladen. Fehlt die Konfig/rclone/Passphrase, wird der Off-Site-Teil still
#   uebersprungen — der lokale Teil laeuft unveraendert weiter.
# - Dead-Man-Switch (optional): HEALTHCHECK_URL wird am Ende gepingt (bzw.
#   .../fail bei Fehler), damit ein ausbleibendes/fehlerhaftes Backup auffaellt.
set -euo pipefail

BACKUP_DIR=/home/hans/miolimos-backups/auto
LOG=/home/hans/log/miolimos-db-backup.log
CONF=/home/hans/.config/miolimos-backup.conf
RCLONE=/home/hans/bin/rclone
SIGNING_DIR=/home/hans/miolimos_signing
mkdir -p "$BACKUP_DIR" "$(dirname "$LOG")"

stamp() { date +"%Y-%m-%d %H:%M:%S"; }
ts=$(date +"%Y%m%d-%H%M%S")
had_error=0

# Welche DBs sichern wir? Mapping name => unix-user (Owner).
declare -A DBS=(
  [miolimos_production]=miolimos_src
  [monica_production]=miolimos_monica
)

echo "[$(stamp)] backup start" >> "$LOG"

for db in "${!DBS[@]}"; do
  owner="${DBS[$db]}"
  out="$BACKUP_DIR/${db}-${ts}.dump"
  # Auth ueber ~/.pgpass (chmod 600). Lokaler TCP zwingt md5-Auth statt
  # peer-Auth, fuer die Cron-User-Identitaet hans nicht zur Service-User-
  # Identitaet (miolimos_src/miolimos_monica) gemapt ist.
  if pg_dump -h localhost -U "$owner" -d "$db" -Fc -f "$out" 2>>"$LOG"; then
    size=$(stat -c%s "$out")
    echo "[$(stamp)] ok $db ($size bytes)" >> "$LOG"
  else
    echo "[$(stamp)] FAILED $db" >> "$LOG"
    had_error=1
  fi
done

# Retention (lokal):
#  - taeglich: behalte 14 neueste pro DB
#  - woechentlich: zusaetzlich alle Sonntags-Dumps NICHT loeschen (<= 8 Wochen)
for db in "${!DBS[@]}"; do
  i=0
  while IFS= read -r f; do
    i=$((i+1))
    if [[ $i -le 14 ]]; then
      continue
    fi
    age_days=$(( ( $(date +%s) - $(stat -c%Y "$f") ) / 86400 ))
    name=$(basename "$f")
    if [[ $name =~ ${db}-([0-9]{8})- ]]; then
      d="${BASH_REMATCH[1]}"
      dow=$(date -d "${d:0:4}-${d:4:2}-${d:6:2}" +%u)  # 1=Mo..7=So
      if [[ "$dow" == "7" && $age_days -le 56 ]]; then
        continue
      fi
    fi
    rm -f "$f"
    echo "[$(stamp)] retention rm $(basename "$f")" >> "$LOG"
  done < <(ls -1t "$BACKUP_DIR"/${db}-*.dump 2>/dev/null || true)
done

# ── Off-Site (#545) ──────────────────────────────────────────────────────────
# Opt-in: nur wenn die Konfig existiert. Source-bar sind:
#   RCLONE_REMOTES="b2:miolimos-backups gdrive:miolimos-backups" (Leerz.-getrennt)
#   BACKUP_PASSPHRASE_FILE=/home/hans/.miolimos-backup-pass        (chmod 600)
#   OFFSITE_RETENTION_DAYS=60   (optional; Remote-Aufbewahrung)
#   HEALTHCHECK_URL=https://hc-ping.com/<uuid>  (optional)
offsite() {
  [[ -f "$CONF" ]] || { echo "[$(stamp)] offsite: keine Konfig ($CONF) — uebersprungen" >>"$LOG"; return 0; }
  # shellcheck disable=SC1090
  source "$CONF"
  : "${RCLONE_CONFIG:=/home/hans/.config/rclone/rclone.conf}"
  export RCLONE_CONFIG
  if [[ ! -x "$RCLONE" ]]; then echo "[$(stamp)] offsite: rclone fehlt — uebersprungen" >>"$LOG"; return 0; fi
  if [[ -z "${BACKUP_PASSPHRASE_FILE:-}" || ! -f "${BACKUP_PASSPHRASE_FILE:-/nonexistent}" ]]; then
    echo "[$(stamp)] offsite: Passphrase-Datei fehlt — uebersprungen" >>"$LOG"; return 0
  fi
  if [[ -z "${RCLONE_REMOTES:-}" ]]; then echo "[$(stamp)] offsite: RCLONE_REMOTES leer — uebersprungen" >>"$LOG"; return 0; fi

  local enc_files=() enc src sigtar
  # 1) heutige Dumps verschluesseln
  for db in "${!DBS[@]}"; do
    src="$BACKUP_DIR/${db}-${ts}.dump"
    [[ -f "$src" ]] || continue
    enc="$src.gpg"
    if gpg --batch --yes --symmetric --cipher-algo AES256 \
           --passphrase-file "$BACKUP_PASSPHRASE_FILE" -o "$enc" "$src" 2>>"$LOG"; then
      enc_files+=("$enc")
    else
      echo "[$(stamp)] offsite: gpg FAILED $db" >>"$LOG"; had_error=1
    fi
  done
  # 1b) Signierschluessel (#547) mit sichern: tar -> gpg (nur verschluesselt)
  if [[ -d "$SIGNING_DIR" ]]; then
    sigtar="$BACKUP_DIR/signing-${ts}.tar.gz"
    if tar -czf "$sigtar" -C "$(dirname "$SIGNING_DIR")" "$(basename "$SIGNING_DIR")" 2>>"$LOG" \
       && gpg --batch --yes --symmetric --cipher-algo AES256 \
              --passphrase-file "$BACKUP_PASSPHRASE_FILE" -o "$sigtar.gpg" "$sigtar" 2>>"$LOG"; then
      enc_files+=("$sigtar.gpg")
    else
      echo "[$(stamp)] offsite: signing-key gpg/tar FAILED" >>"$LOG"; had_error=1
    fi
    rm -f "$sigtar"
  fi

  # 2) zu jedem Remote hochladen + Remote-Retention
  local remote f
  for remote in $RCLONE_REMOTES; do
    for f in "${enc_files[@]}"; do
      if "$RCLONE" copy "$f" "$remote/" 2>>"$LOG"; then
        echo "[$(stamp)] offsite ok $remote <= $(basename "$f")" >>"$LOG"
      else
        echo "[$(stamp)] offsite FAILED $remote <= $(basename "$f")" >>"$LOG"; had_error=1
      fi
    done
    "$RCLONE" delete "$remote/" --min-age "${OFFSITE_RETENTION_DAYS:-60}d" 2>>"$LOG" || true
  done

  # 3) lokale .gpg wieder entfernen (unverschluesselte .dump bleiben lokal)
  for f in "${enc_files[@]}"; do rm -f "$f"; done
}
offsite

# ── Dead-Man-Switch ──────────────────────────────────────────────────────────
if [[ -f "$CONF" ]]; then
  # shellcheck disable=SC1090
  source "$CONF"
  if [[ -n "${HEALTHCHECK_URL:-}" ]]; then
    if [[ "$had_error" == "0" ]]; then
      curl -fsS -m 15 --retry 3 "$HEALTHCHECK_URL" -o /dev/null 2>>"$LOG" || true
    else
      curl -fsS -m 15 --retry 3 "${HEALTHCHECK_URL%/}/fail" -o /dev/null 2>>"$LOG" || true
    fi
  fi
fi

echo "[$(stamp)] backup done (errors=$had_error)" >> "$LOG"
