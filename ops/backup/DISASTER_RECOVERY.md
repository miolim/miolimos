# miolimOS — Disaster Recovery (von Null wiederherstellen)

Dieser Leitfaden beschreibt die vollständige Wiederherstellung, wenn der
Homeserver-Laptop verloren ist und du **nur noch das GitHub-Repository** hast.
Stand: #545 (2026-06-08).

## Was du brauchst (Voraussetzungen)

1. **GitHub-Zugang** zu den beiden privaten Repos:
   - `git@github.com:Rabisnah/miolimos_src.git` — die Rails-App + diese Ops-Skripte
   - das KI-Markdown-Repo (`~/miolimos`, Source-of-Truth-Export der Wissenselemente)
2. **Passwortmanager** mit:
   - Backblaze-B2: `keyID` + `applicationKey` (+ Bucket-Name `miolimOS`)
   - Google-Konto für Drive (Ordner `miolimos-backups`)
   - **Backup-Passphrase** (die GPG-Passphrase der Dumps) — *ohne sie ist kein
     Restore möglich.*
3. Ein **Linux-Rechner** (Ubuntu o.ä.) mit Internet.

## Wie die Sicherung aufgebaut ist (3-3-3)

| Was | Wo |
|-----|-----|
| App-Code + diese Skripte | GitHub `miolimos_src` |
| KI-Markdown | GitHub (KI-Repo) |
| Postgres-Dumps (verschlüsselt) | lokal `~/miolimos-backups/auto/` **+** Backblaze B2 `b2:miolimOS` **+** Google Drive `gdrive:miolimos-backups` |
| AES-Signierschlüssel (verschlüsselt) | in jedem Dump-Satz als `signing-*.tar.gz.gpg` |

Alle Off-Site-Dateien sind **GPG-symmetrisch (AES256)** verschlüsselt. Die
Dumps sind Postgres-Custom-Format (`pg_restore`-fähig). Tägliches Cron-Backup:
`30 4 * * * /home/hans/bin/miolimos-db-backup.sh`.

---

## Wiederherstellung — Schritt für Schritt

### 1. Grundsystem
Ruby (siehe `.ruby-version`), PostgreSQL und die üblichen Build-Abhängigkeiten
installieren. Postgres-Rollen anlegen, die die App erwartet (Owner der DBs):
`miolimos_src` (Haupt-DB) und `miolimos_monica`.

### 2. Repos klonen
```bash
git clone git@github.com:Rabisnah/miolimos_src.git ~/miolimos_src
git clone <KI-REPO-URL> ~/miolimos
```

### 3. rclone holen + ein Off-Site-Ziel einrichten
```bash
# rclone als Single-Binary (ohne sudo):
curl -sL https://downloads.rclone.org/rclone-current-linux-amd64.zip -o /tmp/rc.zip
python3 -c "import zipfile;zipfile.ZipFile('/tmp/rc.zip').extractall('/tmp/rc')"
mkdir -p ~/bin && cp /tmp/rc/rclone-*/rclone ~/bin/ && chmod +x ~/bin/rclone

# B2 (headless, nur Keys aus dem Passwortmanager):
~/bin/rclone config create b2 b2 account <KEY_ID> key <APP_KEY> hard_delete true
# ODER Google Drive (Browser nötig — siehe Hinweis unten):
#   ~/bin/rclone config create gdrive drive   (OAuth im Browser)
```
> **Drive headless?** `rclone authorize "drive"` auf einem Rechner mit Browser
> ausführen und den Token einspielen — oder per SSH-Port-Forward
> `ssh -L 53682:localhost:53682 …` den OAuth-Listener tunneln. Für den Restore
> reicht aber **B2 allein** völlig.

### 4. Neuesten Dump + Signierschlüssel holen
```bash
~/bin/rclone lsf b2:miolimOS | sort        # neueste Dateien unten
~/bin/rclone copy b2:miolimOS /tmp/restore --include "*-NEUESTER-TIMESTAMP*"
```

### 5. Entschlüsseln (Passphrase aus dem Passwortmanager)
```bash
echo "<PASSPHRASE>" > /tmp/pp && chmod 600 /tmp/pp
for f in /tmp/restore/*.gpg; do
  gpg --batch --decrypt --passphrase-file /tmp/pp -o "${f%.gpg}" "$f"
done
rm -f /tmp/pp
```

### 6. Datenbanken zurückspielen
```bash
createdb -h localhost miolimos_production
pg_restore -h localhost -d miolimos_production --no-owner /tmp/restore/miolimos_production-*.dump
createdb -h localhost monica_production
pg_restore -h localhost -d monica_production --no-owner /tmp/restore/monica_production-*.dump
```

### 7. Signierschlüssel zurücklegen
```bash
tar -xzf /tmp/restore/signing-*.tar.gz -C ~   # ergibt ~/miolimos_signing/
chmod 600 ~/miolimos_signing/key.pem
```

### 8. App-Konfig + Start
- Rails-Credentials/Master-Key und `~/.pgpass` (DB-Passwörter) aus dem
  Passwortmanager wiederherstellen.
- `bundle install`, ggf. `bin/rails assets:precompile`, dann den App-Server
  (puma via systemd) starten. Details: `ops/` bzw. Deploy-Skript im Repo.

### 9. Backups wieder scharf schalten
- `~/bin/miolimos-offsite-setup.sh` erneut laufen lassen (legt
  `~/.config/miolimos-backup.conf` + Passphrase-Datei neu an) **oder** die
  Konfig manuell wiederherstellen.
- Cron-Einträge wieder setzen (siehe Kopf dieses Dokuments + `miolimos-push.sh`,
  `miolimos-src-push.sh`).
- Die Skripte selbst liegen in diesem Repo unter `ops/backup/` — `~/bin/*.sh`
  sind Symlinks dorthin.

---

## Schnell-Restore mit dem Helfer

Wenn `~/.config/miolimos-backup.conf` + Passphrase-Datei schon stehen:
```bash
~/bin/miolimos-restore-offsite.sh list  b2:miolimOS
~/bin/miolimos-restore-offsite.sh fetch b2:miolimOS/miolimos_production-<ts>.dump.gpg /tmp
~/bin/miolimos-restore-offsite.sh restore /tmp/miolimos_production-<ts>.dump restore_check
# prüfen, dann:  dropdb restore_check
```

## Wichtig
- **Ohne die Passphrase ist kein Restore möglich.** Sie liegt nur lokal in
  `~/.miolimos-backup-pass` (chmod 600) und im Passwortmanager — nie im Repo,
  nie in den Backups selbst.
- Den Restore **immer zuerst in eine Wegwerf-DB** spielen und prüfen, nie blind
  über eine laufende Prod-DB.
- Regelmäßig (z.B. vierteljährlich) einen Test-Restore machen — ein nie
  zurückgespieltes Backup ist kein Backup.
