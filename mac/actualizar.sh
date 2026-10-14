#!/bin/bash
# Updates Fulas Bank on this Mac to the latest version of main:
#   1. makes a backup first, in case something goes wrong;
#   2. downloads the newest scripts and Fulas Bank image;
#   3. restarts the app (on start it applies new migrations by itself);
#   4. updates the «Fulas Bank» app in Applications.
# Your data and passwords (.env) are kept.
#
# Double-click «Actualizar Fulas Bank.command» in ~/FulasBank to run it.
set -euo pipefail
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin"

REPO="${FULAS_REPO:-rafulas/fulas_bank}"
REF="${FULAS_REF:-main}"
DIR="${FULAS_DIR:-$HOME/FulasBank}"
RAW="https://raw.githubusercontent.com/$REPO/$REF/mac"
DMG_URL="https://github.com/$REPO/releases/download/app-mac/FulasBank.dmg"
cd "$DIR"
PORT="$(grep '^PORT=' .env | cut -d= -f2)"
PORT="${PORT:-3000}"

echo "▶ Copia de seguridad antes de actualizar"
"$DIR/copia.sh" || { echo "No se ha podido hacer la copia; no actualizo." >&2; exit 1; }

echo "▶ Descargando la versión nueva"
for f in compose.yml actualizar.sh copia.sh restaurar.sh; do
  curl -fsSL "$RAW/$f" -o "$f.nuevo" && mv "$f.nuevo" "$f"
done
chmod +x actualizar.sh copia.sh restaurar.sh
docker compose pull

echo "▶ Reiniciando"
docker compose up -d --remove-orphans
for _ in $(seq 1 150); do
  curl -fs "http://localhost:$PORT/up" > /dev/null 2>&1 && break
  sleep 2
done
curl -fs "http://localhost:$PORT/up" > /dev/null 2>&1 \
  || { echo "Fulas Bank no responde. Mira: cd ~/FulasBank && docker compose logs web" >&2; exit 1; }

echo "▶ Actualizando la app de Aplicaciones"
tmp="$(mktemp -d)"
if curl -fsSL "$DMG_URL" -o "$tmp/FulasBank.dmg"; then
  osascript -e 'quit app "Fulas Bank"' 2> /dev/null || true
  vol="$(hdiutil attach -nobrowse -readonly "$tmp/FulasBank.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
  app="$(find "$vol" -maxdepth 1 -name '*.app' | head -1)"
  if [[ -n "$app" ]]; then
    rm -rf "/Applications/Fulas Bank.app"
    ditto "$app" "/Applications/Fulas Bank.app"
  fi
  hdiutil detach -quiet "$vol" || true
fi
rm -rf "$tmp"

docker image prune -f > /dev/null 2>&1 || true
echo "Fulas Bank actualizado."
