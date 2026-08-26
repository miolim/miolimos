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
   - **`config/master.key`** (32 Zeichen) und **`config/credentials.yml.enc`**
     der Instanz — *ohne sie startet die wiederhergestellte Instanz überhaupt
     nicht.*

   > **Diese beiden Dateien liegen bewusst NICHT im Backup.** Sie sind
   > gitignoriert und existieren nur im Checkout auf der Maschine. Sie gehören
   > auch nicht ins Datenarchiv: Dann schlösse die eine Backup-Passphrase alles
   > auf — Daten und Schlüssel im selben Behälter. So ist ein entwendetes
   > Archiv ohne den Schlüssel nur teilweise verwertbar.
   >
   > **Prüfe jetzt, nicht im Ernstfall, ob beide im Passwortmanager liegen.**
   > Fehlt der Master-Key, bootet `production` nicht (`lockbox.rb` bricht mit
   > `LOCKBOX_MASTER_KEY missing` ab), und alle mit `has_encrypted` abgelegten
   > Felder sind dauerhaft unlesbar: Gmail-Zugangstoken, Internetmarke-Zugang,
   > 2FA-Geheimnisse der Nutzer. Die **Fachdaten** sind davon nicht betroffen —
   > Personen, Aufgaben, Rechnungen sind unverschlüsselt und nach einem
   > Neuschlüsseln wieder lesbar. Der Preis ist also kein Datenverlust, sondern:
   > Instanz neu schlüsseln, alle hinterlegten Zugänge neu einrichten, 2FA für
   > alle Nutzer neu aufsetzen.
   >
   > Ändert sich der Master-Key später, wird die Kopie im Passwortmanager
   > stillschweigend wertlos. Der tägliche Betriebsbericht meldet deshalb einen
   > Wechsel (Abschnitt „Schlüssel"); wenn er das tut, gehört die Kopie
   > aufgefrischt.
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

**Wie weit zurück du kommst** (#1472, seit 26.08.2026 gestaffelt):

| | Off-Site | Warum |
|---|---|---|
| Datenbank-Abzüge, Signierschlüssel | **60 Tage** | klein (96 MB/Tag) und das eigentlich Kritische — hier zählt Tiefe |
| Datenverzeichnisse (`*-data-*.tar.gz.gpg`) | **7 Tage** | groß (385 MB/Tag) und von Tag zu Tag fast unverändert |

Das heißt für einen Restore: Ein Datenbestand, der **älter als eine Woche**
ist, lässt sich off-site nicht mehr vollständig herstellen — die Datenbank
schon, die zugehörigen Anhänge nicht. Wer weiter zurück muss, braucht die
lokale Kopie oder das KI-Repo auf GitHub. Steuerbar über
`OFFSITE_RETENTION_DAYS` und `OFFSITE_DATA_RETENTION_DAYS` in
`~/.config/miolimos-backup.conf`.

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

> **Diese Schritte wurden am 21.07.2026 einmal vollständig durchgespielt.** Die
> vorherige Fassung führte zu einer Instanz, die nicht lesen konnte und keine
> Hintergrundaufträge ausführen konnte — beides fiel erst nach dem Restore auf.
> Was unten steht, ist die geprüfte Fassung.

**Es sind drei Datenbanken je Instanz, nicht eine.** Gesichert wird nur die
Hauptdatenbank; `…_cache` und `…_queue` enthalten nichts Erhaltenswertes, die
Anwendung braucht sie aber. Fehlen sie, startet die Instanz trotzdem und
antwortet auf `/up` — und scheitert erst beim ersten Hintergrundauftrag
(`ActiveRecord::NoDatabaseError`). Man hält den Restore dann längst für
gelungen.

**Der Besitzer ist entscheidend.** `pg_restore --no-owner` legt die Tabellen
dem an, der den Befehl ausführt. Ist das nicht der Benutzer, mit dem sich die
Anwendung verbindet (`miolimos_src`), bekommt sie beim ersten Zugriff
`PG::InsufficientPrivilege: permission denied for table knowledge_items` — die
Daten sind vollständig da und trotzdem unerreichbar.

```bash
# 1. Alle drei Datenbanken anlegen, dem App-Benutzer gehoerend.
#    Braucht Rechte zum Anlegen — der App-Benutzer selbst hat sie NICHT
#    (`permission denied to create database`), also als DB-Admin ausfuehren.
for db in miolimos_production miolimos_production_cache miolimos_production_queue; do
  createdb -O miolimos_src "$db"
done

# 2. Hauptdatenbank zurueckspielen — ALS miolimos_src, nicht als Admin.
PGPASSWORD='<aus dem Passwortmanager>' \
  pg_restore -h localhost -U miolimos_src -d miolimos_production --no-owner \
             /tmp/restore/miolimos_production-*.dump

# 3. Schemata fuer cache/queue anlegen (die sind leer und brauchen nur Struktur)
RAILS_ENV=production bin/rails db:prepare

# 4. Gegenprobe: gehoeren die Tabellen dem richtigen Benutzer?
psql -tA -d miolimos_production \
  -c "select tableowner, count(*) from pg_tables where schemaname='public' group by 1"
#    -> muss `miolimos_src|69` liefern, nicht den Namen des Admins.
```

Für **monica** analog (`monica_production` + `_cache` + `_queue`, Benutzer
`miolimos_monica`), für die miolimmo-Instanzen mit deren eigenen Namen und dem
Unix-Benutzer `hans`.

### 7. Signierschlüssel zurücklegen
```bash
tar -xzf /tmp/restore/signing-*.tar.gz -C ~   # ergibt ~/miolimos_signing/
chmod 600 ~/miolimos_signing/key.pem
```

### 7b. Datenverzeichnisse zurückspielen (#1076)

Die Datenbank kennt von einem Anhang nur den Pfad — Rechnungsbelege,
Abrechnungen, Zählerstandsfotos und Profilbilder liegen im Dateisystem. Ohne
diesen Schritt bekommst du eine **vollständig aussehende** Datenbank, hinter
deren Verweisen nichts steht, und zwar ohne jede Fehlermeldung.

Die Archive tragen denselben Zeitstempel wie die Dumps — **nimm denselben**,
sonst passt der Dateibestand nicht zum Datenbestand:

```bash
gpg --batch --passphrase-file ~/.miolimos-backup-pass \
    -o /tmp/restore/miolimos-data.tar.gz -d /tmp/restore/miolimos-data-*.tar.gz.gpg
tar -xzf /tmp/restore/miolimos-data.tar.gz -C ~     # ergibt ~/miolimos/
```

Ebenso für `immoos-data` (→ `~/immoos_data`) und `stocker-data`
(→ `~/stocker_data`).

**Reihenfolge bei `~/miolimos` beachten.** Dieses Archiv enthält *kein*
`.git` — die Historie liegt auf GitHub. Erst klonen, dann das Archiv
darüberpacken, sonst überschreibt der Klon die untracked Anhänge nicht,
sondern das Archiv fehlt:

```bash
git clone git@github.com:Rabisnah/miolimos.git ~/miolimos
tar -xzf /tmp/restore/miolimos-data.tar.gz -C ~     # legt die Anhänge dazu
```

`~/stocker_data` bringt sein `.git` dagegen mit (es gibt dort kein Remote, und
die Anwendung bietet die Versionshistorie einer Notiz aktiv an) — dort genügt
das Auspacken. `~/immoos_data` ist eine Testinstanz und kommt ohne Historie
zurück; das ist Absicht.

**Gegenprobe, die sich lohnt:** Dateizahl im Archiv gegen Dateizahl auf der
Platte — und zwar die *Listen*, nicht nur die Anzahl. Gleich viele Dateien ist
nicht dasselbe wie dieselben Dateien.

```bash
tar -tzf /tmp/restore/miolimos-data.tar.gz | grep -v '/$' | sed 's|^miolimos/||' | sort > /tmp/a
cd ~/miolimos && find . -type f -not -path "./.git/*" | sed 's|^\./||' | sort > /tmp/b
diff /tmp/a /tmp/b && echo "deckungsgleich"
```

> **Das `-not -path "./.git/*"` gehört nur hierher — nicht in die Gegenprobe der
> anderen Instanzen.** Es steht da, weil das miolimos-Archiv kein `.git`
> enthält (die Historie kam oben aus dem Klon); ohne den Ausschluss meldete der
> Vergleich die gesamte Historie als Überschuss. Bei **`stocker_data` ist es
> genau umgekehrt** — dort steckt `.git` im Archiv und muss auf beiden Seiten
> mitgezählt werden:
>
> ```bash
> tar -tzf /tmp/restore/stocker-data.tar.gz | grep -v '/$' | sed 's|^stocker_data/||' | sort > /tmp/a
> cd ~/stocker_data && find . -type f | sed 's|^\./||' | sort > /tmp/b
> diff /tmp/a /tmp/b && echo "deckungsgleich"
> ```
>
> Beim Übertragen des Befehls von einer Instanz auf die andere entsteht sonst
> eine Abweichung, die keine ist — genau in dem Moment, in dem man nach einer
> Katastrophe wissen will, ob die Wiederherstellung vollständig war. (Gefunden
> am 21.07.2026, indem der Ablauf einmal ausgeführt statt gelesen wurde.)

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

## Probelauf auf der laufenden Maschine (vierteljährlich)

Die Anleitung oben ist für eine **nackte** Maschine geschrieben. Für den
regelmäßigen Probelauf auf dem laufenden System gilt zusätzlich:

- **Wegwerf-Namen verwenden.** `createdb miolimos_production` würde hier auf
  die echte Datenbank treffen. Stattdessen z. B. `probe_miolimos` samt
  `_cache`/`_queue`, und am Ende `dropdb`.
- **`database.yml` ist beim Namen fest verdrahtet.** Ein Restore lässt sich
  deshalb nicht ohne Weiteres neben der laufenden Instanz starten; dafür
  braucht es einen eigenen Checkout mit angepasster `database.yml`
  (`git clone`, `config/master.key` und `credentials.yml.enc` dazulegen).
- **Ohne Hintergrundarbeiter starten.** `SOLID_QUEUE_IN_PUMA` NICHT setzen.
  Sonst beginnt die wiederhergestellte Instanz, die mitgesicherten Aufträge
  abzuarbeiten — und verschickt echte Mails an echte Empfänger.
- **Auf einem freien Port binden**, nie auf 3007.
- **Aufräumen:** Datenbanken löschen, Checkout und `/tmp/restore*` entfernen.

Was der Probelauf beantworten soll, in dieser Reihenfolge:

1. Lassen sich die Archive vom Remote holen und entschlüsseln?
2. Spielt der Dump fehlerfrei zurück?
3. Kann die Anwendung die Daten **lesen** (Besitzverhältnisse)?
4. Kommt der Webserver hoch (`/up` → 200)?
5. Laufen Hintergrundaufträge (`SolidQueue::Job.count` ohne Fehler)?
6. **Finden die Verweise aus der Datenbank ihre Dateien?**

Punkt 6 ist der eigentliche Grund für die Dateisicherung und lässt sich
maschinell prüfen — jeder `file_path` aus `task_attachments` und
`knowledge_items` gegen den wiederhergestellten Baum. Am 21.07.2026 ergab das:
31 von 31 Anhängen auflösbar, und die 2.554 toten Verweise unter den
Wissenselementen fehlen **auch im Live-Bestand** — die Sicherung ist also treu,
der Dateispiegel weicht schon vorher von der Datenbank ab.

## Wichtig
- **Ohne die Passphrase ist kein Restore möglich.** Sie liegt nur lokal in
  `~/.miolimos-backup-pass` (chmod 600) und im Passwortmanager — nie im Repo,
  nie in den Backups selbst.
- Den Restore **immer zuerst in eine Wegwerf-DB** spielen und prüfen, nie blind
  über eine laufende Prod-DB.
- Regelmäßig (z.B. vierteljährlich) einen Test-Restore machen — ein nie
  zurückgespieltes Backup ist kein Backup.
