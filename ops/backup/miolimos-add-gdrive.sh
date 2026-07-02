#!/usr/bin/env bash
# Google Drive als zweites Off-Site-Ziel nachziehen (#545), headless.
# Voraussetzung: auf einem Rechner MIT Browser (z.B. Windows-Laptop) einmal
#   rclone authorize "drive"
# laufen lassen und die ausgegebene Token-Zeile {"access_token":...} kopieren.
# Dieses Skript spielt den Token hier ein (kein Browser noetig) und haengt
# gdrive:<ordner> an RCLONE_REMOTES in der Backup-Konfig an.
#
#   Aufruf:  ~/bin/miolimos-add-gdrive.sh
set -euo pipefail

RCLONE=/home/hans/bin/rclone
CONF=/home/hans/.config/miolimos-backup.conf
[[ -f "$CONF" ]] || { echo "Konfig $CONF fehlt — erst ~/bin/miolimos-offsite-setup.sh laufen lassen."; exit 1; }

read -rp "Drive-Ordnername [miolimos-backups]: " GD_DIR
GD_DIR=${GD_DIR:-miolimos-backups}
echo "Token-Zeile (komplette {...}) einfuegen, dann Enter:"
read -r GD_TOKEN
[[ -n "$GD_TOKEN" ]] || { echo "kein Token — Abbruch."; exit 1; }

"$RCLONE" config create gdrive drive config_token "$GD_TOKEN" >/dev/null
echo "Pruefe Drive-Zugriff …"
"$RCLONE" lsd gdrive: >/dev/null || { echo "Drive-Zugriff fehlgeschlagen — Token pruefen."; exit 1; }
"$RCLONE" mkdir "gdrive:$GD_DIR" 2>/dev/null || true
echo "  ✓ Drive-Remote 'gdrive' aktiv, Ordner '$GD_DIR' bereit."

# gdrive an RCLONE_REMOTES anhaengen (idempotent).
if grep -q "gdrive:$GD_DIR" "$CONF"; then
  echo "  (gdrive:$GD_DIR steht schon in der Konfig.)"
else
  cur=$(grep '^RCLONE_REMOTES=' "$CONF" | sed -E 's/^RCLONE_REMOTES="?([^"]*)"?/\1/')
  sed -i "s#^RCLONE_REMOTES=.*#RCLONE_REMOTES=\"$cur gdrive:$GD_DIR\"#" "$CONF"
  echo "  ✓ RCLONE_REMOTES erweitert: $cur gdrive:$GD_DIR"
fi

echo; echo "Testlauf …"
/home/hans/bin/miolimos-db-backup.sh
echo; grep -E "offsite ok|offsite FAILED|backup done" /home/hans/log/miolimos-db-backup.log | tail -8
echo; echo "Inhalt Drive:"; "$RCLONE" ls "gdrive:$GD_DIR" 2>/dev/null | tail -6
