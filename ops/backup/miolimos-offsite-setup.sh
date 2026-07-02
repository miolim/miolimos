#!/usr/bin/env bash
# Einmaliges Setup der verschluesselten Off-Site-Backups (#545) — B2-Kern.
# Headless-tauglich: Backblaze B2 braucht nur Keys (kein Browser). Google Drive
# (OAuth -> Browser) wird separat per ~/bin/miolimos-add-gdrive.sh nachgezogen.
# Geheimnisse bleiben lokal und landen NIE in der Aufgaben-DB.
#
#   Aufruf:  ~/bin/miolimos-offsite-setup.sh
set -euo pipefail

RCLONE=/home/hans/bin/rclone
CONF=/home/hans/.config/miolimos-backup.conf
PASS_FILE=/home/hans/.miolimos-backup-pass
mkdir -p "$(dirname "$CONF")"

say() { printf "\n\033[1;36m%s\033[0m\n" "$*"; }
[[ -x "$RCLONE" ]] || { echo "rclone fehlt unter $RCLONE"; exit 1; }

# ── 1) Backblaze B2 (headless) ───────────────────────────────────────────────
say "1/4  Backblaze B2"
echo "Im B2-Webinterface unter 'Application Keys' einen Key anlegen (Bucket-Zugriff genuegt)."
read -rp "  B2 keyID:            " B2_ID
read -rsp "  B2 applicationKey:   " B2_KEY; echo
read -rp "  B2 Bucket-Name [miolimos-backups]: " B2_BUCKET
B2_BUCKET=${B2_BUCKET:-miolimos-backups}
"$RCLONE" config create b2 b2 account "$B2_ID" key "$B2_KEY" hard_delete true >/dev/null
"$RCLONE" mkdir "b2:$B2_BUCKET" 2>/dev/null || true
echo "  ✓ rclone-Remote 'b2' angelegt, Bucket '$B2_BUCKET' bereit."

# ── 2) Verschluesselungs-Passphrase ──────────────────────────────────────────
say "2/4  Verschluesselungs-Passphrase"
echo "WICHTIG: im Passwortmanager sichern — ohne sie ist KEIN Restore moeglich."
echo "Sie wird nur lokal in $PASS_FILE (chmod 600) abgelegt."
read -rsp "  Passphrase:         " PP1; echo
read -rsp "  Passphrase (Wdh.):  " PP2; echo
[[ "$PP1" == "$PP2" && -n "$PP1" ]] || { echo "Passphrasen leer/ungleich — Abbruch."; exit 1; }
printf '%s' "$PP1" > "$PASS_FILE"; chmod 600 "$PASS_FILE"
echo "  ✓ Passphrase gespeichert (chmod 600)."

# ── 3) Ausfall-Alarm (optional) ──────────────────────────────────────────────
say "3/4  Ausfall-Alarm (optional)"
echo "Auf healthchecks.io (gratis) einen Check anlegen, Ping-URL hier einfuegen."
read -rp "  HEALTHCHECK_URL (leer = ueberspringen): " HC_URL

# ── 4) Konfig schreiben + Testlauf ───────────────────────────────────────────
say "4/4  Konfiguration schreiben"
umask 077
cat > "$CONF" <<EOF
# miolimOS Off-Site-Backup-Konfig (#545) — von miolimos-offsite-setup.sh erzeugt.
# RCLONE_REMOTES = Leerzeichen-getrennte Liste der Ziel-Wurzeln.
# Google Drive kommt per miolimos-add-gdrive.sh dazu (haengt gdrive:<dir> an).
RCLONE_REMOTES="b2:$B2_BUCKET"
BACKUP_PASSPHRASE_FILE=$PASS_FILE
OFFSITE_RETENTION_DAYS=60
RCLONE_CONFIG=/home/hans/.config/rclone/rclone.conf
EOF
[[ -n "$HC_URL" ]] && echo "HEALTHCHECK_URL=$HC_URL" >> "$CONF"
echo "  ✓ $CONF geschrieben."

say "Testlauf"
/home/hans/bin/miolimos-db-backup.sh
echo; echo "Log (sollte 'offsite ok b2:...' zeigen):"
grep -E "offsite ok|offsite FAILED|backup done" /home/hans/log/miolimos-db-backup.log | tail -6
echo; echo "Inhalt B2:"; "$RCLONE" ls "b2:$B2_BUCKET" 2>/dev/null | tail -6

say "Google Drive nachziehen (wenn du den Token hast)"
echo "Auf dem Windows-Laptop rclone.exe holen (entpacken, kein Installer noetig):"
echo "   https://downloads.rclone.org/rclone-current-windows-amd64.zip"
echo "Dann in der Eingabeaufforderung im entpackten Ordner:"
echo "   rclone authorize \"drive\""
echo "Browser bestaetigen -> rclone gibt eine Token-Zeile {\"access_token\":...} aus."
echo "Diese Zeile kopieren und HIER auf dem Server einspielen:"
echo "   ~/bin/miolimos-add-gdrive.sh"
