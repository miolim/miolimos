#!/usr/bin/env bash
# Haelt yt-dlp aktuell (miolimOS #1492).
#
# WARUM DAS EIN EIGENER LAUF IST: YouTube aendert regelmaessig, wie es
# Tonspuren ausliefert; yt-dlp zieht binnen Tagen nach. Wer nicht
# aktualisiert, bekommt irgendwann `HTTP Error 403: Forbidden` — und die
# Meldung sagt nicht, dass das Werkzeug alt ist. Genau daran ist Folge 15
# des Podcasts gescheitert: acht Wochen alte Fassung, YouTube hatte
# umgestellt, das Transkript kam nie.
#
# Cron:  0 5 1 * *  /home/hans/bin/miolimos-ytdlp-update.sh
#
# `--break-system-packages` ist noetig, weil Debian/Ubuntu die
# System-Python-Installation seit PEP 668 schuetzt. Der Schalter gilt hier
# nur fuer das Nutzerverzeichnis (~/.local), nicht fuer Systempakete.
set -euo pipefail

LOG=${LOG:-/home/hans/log/yt-dlp-update.log}
PIP=${PIP:-python3}
BIN=${BIN:-/home/hans/.local/bin/yt-dlp}
mkdir -p "$(dirname "$LOG")"

stamp() { date +"%Y-%m-%d %H:%M:%S"; }
version() { "$BIN" --version 2>/dev/null || echo "(nicht installiert)"; }

vorher="$(version)"

if ! "$PIP" -m pip install --user --upgrade --quiet --break-system-packages yt-dlp >>"$LOG" 2>&1; then
  # Laut sein: Ein stiller Fehlschlag heisst, dass das naechste Video
  # irgendwann nicht mehr laedt und niemand weiss, warum.
  echo "[$(stamp)] FEHLGESCHLAGEN — yt-dlp blieb bei $vorher" >>"$LOG"
  exit 1
fi

nachher="$(version)"

if [ "$vorher" = "$nachher" ]; then
  echo "[$(stamp)] unveraendert ($nachher)" >>"$LOG"
else
  echo "[$(stamp)] aktualisiert: $vorher -> $nachher" >>"$LOG"
fi

# Kurze Funktionsprobe: Metadaten eines Videos abrufen. Sie kostet nichts
# (kein Download) und faellt genau dann um, wenn YouTube wieder etwas
# geaendert hat — dann steht es im Log, bevor Hans es an einem
# fehlgeschlagenen Transkript merkt.
PROBE_URL=${PROBE_URL:-https://www.youtube.com/watch?v=jNQXAC9IVRw}
if "$BIN" --js-runtimes node --no-warnings --skip-download \
          --print "%(title)s" "$PROBE_URL" >/dev/null 2>>"$LOG"; then
  echo "[$(stamp)] Probe ok" >>"$LOG"
else
  echo "[$(stamp)] PROBE FEHLGESCHLAGEN — YouTube-Abruf klappt nicht mehr" >>"$LOG"
  exit 1
fi
