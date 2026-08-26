#!/usr/bin/env bash
# Taeglich pg_dump fuer alle miolimOS-Prod-DBs + verschluesselte Off-Site-Kopie,
# dazu die Datenverzeichnisse (Anhaenge!) im selben Lauf und Zeitstempel.
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

# Datenverzeichnisse je Instanz (#1076, Hinweis von immoos_builder).
#
# WARUM DAS HIERHER GEHOERT UND NICHT IN EIN EIGENES SKRIPT: Die Datenbank
# kennt von einem Anhang nur den Pfad, die Datei liegt im Dateisystem. Werden
# beide zu verschiedenen Zeitpunkten gesichert, passt der wiederhergestellte
# Dateibestand nicht zum wiederhergestellten Datenbestand — und der Fehler
# faellt beim Restore nicht auf, weil aus Sicht der DB alles vollstaendig ist.
# Deshalb: derselbe Lauf, derselbe Zeitstempel.
#
# Bis 21.07.2026 war dieser Teil GAR NICHT gesichert. Die DB ging
# verschluesselt nach B2 und Drive, die zugehoerigen Belege nirgendwohin —
# ein Restore haette eine Datenbank voller Verweise auf Dateien ergeben, die
# es nicht mehr gibt.
#
# `miolimos_monica` fehlt hier nicht: die Instanz setzt kein
# MIOLIMOS_DATA_PATH und schreibt darum in den Default ~/miolimos, ist ueber
# den ersten Eintrag also mit abgedeckt.
# Zeilen: "name|pfad|ausschluss,ausschluss" — das dritte Feld ist optional.
# Ueberschreibbar fuer den Selbsttest, im Cron-Betrieb greift die Vorgabe.
#
# Ohne drittes Feld gelten DEFAULT_EXCLUDES. Diese Richtung ist Absicht: Ein
# vergessener Eintrag sichert dann WENIGER als gedacht, nicht mehr — und das
# faellt beim naechsten Blick auf die Archivgroesse auf, waehrend ein
# stillschweigend zu grosses Archiv niemandem auffiele.
#
# `.git` je Verzeichnis verschieden (2026-07-21, nach Gegenrede von
# immoos_builder — ich hatte es global ausgeschlossen):
#
#   miolimos  — ausgeschlossen. Die Historie liegt vollstaendig auf GitHub
#               (Rabisnah/miolimos); ein Restore holt sie mit `git clone` und
#               packt das Archiv darueber. Waeren rund 530 MB taeglich fuer
#               etwas, das schon zweimal woanders liegt.
#   immoos    — ausgeschlossen. 99 der 231 MB sind die Historie eines
#               Demo-Bestands aus synth:docs-Laeufen und einem gut gefuellten
#               Papierkorb; ihr Verlust ist folgenlos.
#   stocker   — MITGESICHERT. Kein Remote, und die Historie ist dort ein
#               benutztes Feature, kein Nebenprodukt: KnowledgeVersionsController
#               (…/history, …/version, …/restore_version) liest sie ueber
#               KiHistory per `git log` aus dem Daten-Repo. Ohne sie waere ein
#               Restore zwar datenvollstaendig, aber die Versionsansicht leer
#               und der Wiederherstellen-Knopf funktionslos — ein Verlust, den
#               man erst bemerkt, wenn jemand wissen will, was vorher in einer
#               Notiz stand. Kostet heute nichts (ein leerer Root-Commit) und
#               waechst mit genau dem Bestand, den man sichern will.
DEFAULT_EXCLUDES=".git,_test-artifacts"

DEFAULT_DATA_DIRS="\
miolimos|/home/hans/miolimos|
immoos|/home/hans/immoos_data|
stocker|/home/hans/stocker_data|_test-artifacts"

declare -A DATA_DIRS=() DATA_EXCLUDES=()
while IFS='|' read -r _name _path _excl; do
  [[ -n "${_name:-}" ]] || continue
  DATA_DIRS[$_name]="$_path"
  DATA_EXCLUDES[$_name]="${_excl:-$DEFAULT_EXCLUDES}"
done <<< "${BACKUP_DATA_DIRS:-$DEFAULT_DATA_DIRS}"

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
#   OFFSITE_RETENTION_DAYS=60        (optional; Datenbank-Abzuege, #1472)
#   OFFSITE_DATA_RETENTION_DAYS=7    (optional; Datenarchive, #1472)
#   HEALTHCHECK_URL=https://hc-ping.com/<uuid>  (optional)
#
# #1472 (Hans, 2026-08-26): „Storage Cap Reached 100%" bei Backblaze.
# Nichts war kaputt — die Menge war rechnerisch zwingend. 481 MB pro Tag mal
# 60 Tage Aufbewahrung sind rund 28 GB, das Dreifache der kostenlosen Grenze.
#
# Deshalb wird nicht mehr pauschal nach OFFSITE_RETENTION_DAYS aufgeraeumt,
# sondern nach Wichtigkeit gestaffelt:
#
#   Datenbank-Abzuege (96 MB/Tag)  — 60 Tage. Klein und das eigentlich
#                                    Kritische; hier zaehlt Tiefe.
#   Datenarchive     (385 MB/Tag)  — 7 Tage. Gross und von Tag zu Tag fast
#                                    unveraendert; 60 Vollkopien desselben
#                                    Verzeichnisses sind keine 60-fache
#                                    Sicherheit, nur 60-facher Platz.
#
# Beharrungszustand danach: rund 8,5 GB statt 28.
#
# Das Muster trifft die Archive aus der Datenverzeichnis-Schleife oben
# (`${inst}-data-${ts}.tar.gz.gpg`). Der Signierschluessel heisst
# `signing-…tar.gz.gpg` und faellt bewusst NICHT darunter: winzig, und ohne
# ihn ist ein Restore wertlos.
DATEN_MUSTER="*-data-*.tar.gz.gpg"

# Aufraeumen mit Vermerk. Frueher stand hier `|| true` — ein fehlgeschlagenes
# Aufraeumen war damit unsichtbar, und das Einzige, woran man es gemerkt
# haette, ist genau die Mail, die diese Aufgabe ausgeloest hat. Ein Backup,
# das nicht aufraeumt, laeuft in die Grenze und dann irgendwann ins Leere.
# Deshalb zaehlt der Fehlschlag jetzt als Fehler und geht ueber den
# Dead-Man-Switch hinaus in die Welt.
verfallen() { # verfallen <remote> <was> <tage> <rclone-filter...>
  local remote="$1" was="$2" tage="$3"; shift 3
  if "$RCLONE" delete "$remote/" --min-age "${tage}d" "$@" 2>>"$LOG"; then
    echo "[$(stamp)] retention ok $remote $was (aelter als ${tage}d)" >>"$LOG"
  else
    echo "[$(stamp)] retention FAILED $remote $was (${tage}d)" >>"$LOG"
    had_error=1
  fi
}

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
  # 0) Datenverzeichnisse einpacken (#1076). Bewusst NUR off-site: die
  #    Dateien liegen ja schon lokal, eine zweite lokale Kopie schuetzt vor
  #    gar nichts und kostet nur Platz. Das fertige .gpg wird nach dem Upload
  #    wieder entfernt, genau wie beim Signierschluessel.
  local dtar
  for inst in "${!DATA_DIRS[@]}"; do
    dir="${DATA_DIRS[$inst]}"
    if [[ ! -d "$dir" ]]; then
      # Anders als bei den DBs gilt hier: eingetragen = muss existieren. Ein
      # Datenverzeichnis legt der Betreiber beim Einrichten der Instanz an,
      # es entsteht nicht von selbst beim ersten Start. Ein Eintrag ohne
      # Verzeichnis ist deshalb immer ein Fehler und nie ein Vorgriff.
      echo "[$(stamp)] FAILED $inst-data (Verzeichnis $dir fehlt)" >>"$LOG"
      had_error=1
      continue
    fi
    dtar="$BACKUP_DIR/${inst}-data-${ts}.tar.gz"
    local -a ex=(); local _p
    IFS=',' read -ra _parts <<< "${DATA_EXCLUDES[$inst]}"
    for _p in "${_parts[@]}"; do [[ -n "$_p" ]] && ex+=(--exclude="$_p"); done
    if tar -czf "$dtar" "${ex[@]}" -C "$(dirname "$dir")" "$(basename "$dir")" 2>>"$LOG" \
       && gpg --batch --yes --symmetric --cipher-algo AES256 \
              --passphrase-file "$BACKUP_PASSPHRASE_FILE" -o "$dtar.gpg" "$dtar" 2>>"$LOG"; then
      echo "[$(stamp)] ok $inst-data ($(stat -c%s "$dtar.gpg") bytes verschluesselt)" >>"$LOG"
      enc_files+=("$dtar.gpg")
    else
      echo "[$(stamp)] FAILED $inst-data (tar/gpg)" >>"$LOG"; had_error=1
    fi
    rm -f "$dtar"
  done

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
    # #1472: gestaffelt statt pauschal. Reihenfolge egal, die Filter sind
    # zueinander komplementaer — was der eine Aufruf einschliesst, schliesst
    # der andere aus. Kein Objekt faellt durch beide Raster.
    verfallen "$remote" "Datenarchive" "${OFFSITE_DATA_RETENTION_DAYS:-7}"  --include "$DATEN_MUSTER"
    verfallen "$remote" "Dumps"        "${OFFSITE_RETENTION_DAYS:-60}"      --exclude "$DATEN_MUSTER"
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
