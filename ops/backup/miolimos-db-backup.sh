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

# Pfade sind ueberschreibbar, damit der Selbsttest (selftest.sh) das Skript
# gegen ein Wegwerf-Verzeichnis laufen lassen kann. Im Cron-Betrieb greifen
# ausnahmslos die Defaults.
BACKUP_DIR=${BACKUP_DIR:-/home/hans/miolimos-backups/auto}
LOG=${LOG:-/home/hans/log/miolimos-db-backup.log}
CONF=${CONF:-/home/hans/.config/miolimos-backup.conf}
RCLONE=${RCLONE:-/home/hans/bin/rclone}
SIGNING_DIR=${SIGNING_DIR:-/home/hans/miolimos_signing}
mkdir -p "$BACKUP_DIR" "$(dirname "$LOG")"

stamp() { date +"%Y-%m-%d %H:%M:%S"; }
ts=$(date +"%Y%m%d-%H%M%S")
had_error=0

# Welche DBs sichern wir? Mapping name => unix-user (Owner).
#
# #1064 (2026-07-20): Instanzen, die es noch nicht gibt, duerfen hier
# schon stehen — fehlende DBs werden uebersprungen (siehe SKIP unten),
# nicht als Fehler gemeldet. Damit faengt das Backup eine neue Instanz
# automatisch ein, sobald ihre DB angelegt ist, statt darauf zu warten,
# dass jemand an diese Liste denkt. Genau das war die Luecke: die
# immoOS-Instanz lief seit Juli ausserhalb jeder Sicherung.
#
# Wird eine Instanz umbenannt, gehoert BEIDE Seiten hierher: der neue Name
# rein, der alte raus. Der alte Name darf nicht einfach stehenbleiben — er
# wuerde ab dem naechsten Lauf als MISSING gemeldet (siehe Schleife unten).
declare -A DBS=(
  [miolimos_production]=miolimos_src
  [monica_production]=miolimos_monica
  [immoos_production]=hans
  [stocker_production]=hans
)

# Verbindungsweg je DB. Die Kern-Instanzen laufen ueber lokalen TCP mit
# ~/.pgpass (die Cron-Identitaet hans ist NICHT auf miolimos_src/
# miolimos_monica gemapt, peer-Auth scheidet aus). Die Fork-Instanzen
# gehoeren dem Unix-User hans selbst — dort greift peer-Auth ueber den
# Socket, und ein .pgpass-Eintrag existiert gar nicht. Wer hier den
# falschen Weg nimmt, bekommt „no password supplied" statt eines Dumps.
declare -A DB_HOST=(
  [immoos_production]=/var/run/postgresql
  [stocker_production]=/var/run/postgresql
)

echo "[$(stamp)] backup start" >> "$LOG"

for db in "${!DBS[@]}"; do
  owner="${DBS[$db]}"
  host="${DB_HOST[$db]:-localhost}"
  out="$BACKUP_DIR/${db}-${ts}.dump"
  # Direkt dumpen und ERST im Fehlerfall unterscheiden. Eine vorgeschaltete
  # Existenz-Probe per `psql -l` waere hier falsch: sie verbindet sich auf die
  # Datenbank `postgres`, fuer die es keinen ~/.pgpass-Eintrag gibt (die
  # Eintraege lauten auf die Ziel-DB) — das Ergebnis war „existiert nicht"
  # fuer die wichtigsten DBs, ein stiller Ausfall mit errors=0. Nur ein
  # ausdrueckliches „does not exist" von Postgres zaehlt als „noch nicht
  # angelegt"; jeder andere Fehler bleibt ein Fehler.
  err="$BACKUP_DIR/.dumperr-$$"
  if pg_dump -h "$host" -U "$owner" -d "$db" -Fc -f "$out" 2>"$err"; then
    cat "$err" >>"$LOG"; rm -f "$err"
    size=$(stat -c%s "$out")
    echo "[$(stamp)] ok $db ($size bytes)" >> "$LOG"
  elif grep -qiE 'database "'"$db"'" does not exist' "$err"; then
    cat "$err" >>"$LOG"; rm -f "$err"; rm -f "$out"
    # #1064 Nachtrag 2 (2026-07-21, Hinweis von immoos_builder): „gibt es noch
    # nicht" und „hiess gestern noch anders" sehen beide wie eine fehlende DB
    # aus — mit stillem Skip faellt eine umbenannte oder geloeschte Produktiv-DB
    # lautlos aus der Sicherung, und die Abschlusszeile meldet weiter errors=0.
    # Genau das ist beim Rename miolimmo_production -> stocker_production
    # passiert. Unterscheidungsmerkmal ist der Vorlauf: Liegt fuer diese DB
    # schon ein frueherer Dump im BACKUP_DIR, war sie einmal da — dann ist ihr
    # Verschwinden ein Fehler. Der Bestand der Dumps ist dabei die Zustands-
    # quelle, keine zusaetzliche Statusdatei: er ueberlebt ein geloeschtes
    # State-File und verstummt von selbst, sobald die Retention den letzten
    # alten Dump abgeraeumt hat.
    if compgen -G "$BACKUP_DIR/${db}-*.dump" > /dev/null; then
      last=$(basename "$(ls -1t "$BACKUP_DIR"/${db}-*.dump | head -1)")
      echo "[$(stamp)] MISSING $db (war frueher gesichert, zuletzt $last) — umbenannt oder geloescht?" >> "$LOG"
      had_error=1
    else
      echo "[$(stamp)] skip $db (DB existiert nicht)" >> "$LOG"
    fi
  else
    cat "$err" >>"$LOG"; rm -f "$err"
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
