#!/bin/bash
# Updates Fulas Bank on this Mac to the latest version of main:
#   1. makes a backup first, in case something goes wrong;
#   2. downloads the newest scripts and Fulas Bank image;
#   3. restarts the app (on start it applies new migrations by itself);
#   4. updates the «Fulas Bank» app in Applications.
# Your data and passwords (.env) are kept.
#
# Double-click «Actualizar Fulas Bank.command» in ~/FulasBank to run it.
#
# If something looks wrong after an update, «Volver a la versión anterior
# .command» (this script with --volver) undoes it: it loads the copy made just
# before the update and runs the version that was there before, pinned with
# FULAS_IMAGE in .env until the next update.
set -euo pipefail
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin"

REPO="${FULAS_REPO:-rafulas/fulas_bank}"
REF="${FULAS_REF:-main}"
DIR="${FULAS_DIR:-$HOME/FulasBank}"
RAW="https://raw.githubusercontent.com/$REPO/$REF/mac"
DMG_URL="https://github.com/$REPO/releases/download/app-mac/FulasBank.dmg"
cd "$DIR"

# While this runs, the hourly check (aviso.sh) still sees the old version
# running and would offer the update again. This mark tells it to wait.
LOCK="$DIR/registros/actualizando"
mkdir -p "$DIR/registros"
date '+%s' > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

PORT="$(grep '^PORT=' .env | cut -d= -f2)"
PORT="${PORT:-3000}"
IMAGE="ghcr.io/rafulas/fulas_bank"
BEFORE="$DIR/registros/antes-de-actualizar"

# Sets (or, with no argument, removes) FULAS_IMAGE in .env: the exact version
# compose.yml runs instead of the latest one.
set_pinned_image() {
  local tmp_env
  tmp_env="$(mktemp)"
  grep -v '^FULAS_IMAGE=' .env > "$tmp_env" || true
  if [[ -n "${1:-}" ]]; then
    echo "FULAS_IMAGE=$1" >> "$tmp_env"
  fi
  cat "$tmp_env" > .env
  rm -f "$tmp_env"
}

# ------------------------------------------ Going back to the previous version
if [[ "${1:-}" == "--volver" ]]; then
  if [[ ! -f "$BEFORE" ]]; then
    echo "No hay ninguna actualización que deshacer." >&2
    exit 1
  fi
  read -r prev_sha prev_copy < "$BEFORE"
  if [[ -z "${prev_sha:-}" || -z "${prev_copy:-}" || ! -f "$prev_copy" ]]; then
    echo "Falta la versión anterior o su copia (${prev_copy:-ninguna}): no se puede volver atrás." >&2
    exit 1
  fi
  echo "Vas a volver a la versión anterior (${prev_sha:0:7}) y a cargar la copia hecha justo antes de actualizar:"
  echo "  $(basename "$prev_copy")"
  echo "Lo que hayas apuntado en Fulas Bank desde entonces se perderá."
  read -r -p "¿Seguimos? Escribe «si»: " answer < /dev/tty
  if [[ "$answer" != "si" && "$answer" != "sí" ]]; then
    echo "Cancelado: no se ha tocado nada."
    exit 0
  fi

  set_pinned_image "$IMAGE:sha-$prev_sha"
  if ! docker compose pull web worker; then
    set_pinned_image ""
    echo "No se ha podido descargar la versión ${prev_sha:0:7}: no se ha tocado nada." >&2
    exit 1
  fi
  # restaurar.sh stops the app, loads the copy with the old version and starts
  # it again; the copy was made by that same version, so they match.
  "$DIR/restaurar.sh" --sin-preguntar "$prev_copy"
  rm -f "$BEFORE"
  echo "Has vuelto a la versión ${prev_sha:0:7}. Se queda en ella hasta que vuelvas a actualizar."
  exit 0
fi

# The version running now, to go back to if this update goes wrong.
prev_sha="$(docker compose exec -T web printenv BUILD_COMMIT_SHA 2> /dev/null | tr -d '[:space:]' || true)"

echo "▶ Copia de seguridad antes de actualizar"
"$DIR/copia.sh" || { echo "No se ha podido hacer la copia; no actualizo." >&2; exit 1; }
if [[ -n "$prev_sha" && -f "$DIR/registros/ultima-copia" ]]; then
  echo "$prev_sha $(cat "$DIR/registros/ultima-copia")" > "$BEFORE"
fi
# An update always goes to the newest version, even after going back.
set_pinned_image ""

echo "▶ Descargando la versión nueva"
for f in compose.yml actualizar.sh copia.sh restaurar.sh aviso.sh; do
  curl -fsSL "$RAW/$f" -o "$f.nuevo" && mv "$f.nuevo" "$f"
done
chmod +x actualizar.sh copia.sh restaurar.sh aviso.sh
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
  # macOS 26 warns that «hdiutil attach» is deprecated: it still works, and
  # its replacement does not exist on older macOS. Only that warning is hidden.
  vol="$(hdiutil attach -nobrowse -readonly "$tmp/FulasBank.dmg" 2> >(grep -vE 'is deprecated|diskutil image attach' >&2) | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
  app="$(find "$vol" -maxdepth 1 -name '*.app' | head -1)"
  if [[ -n "$app" ]]; then
    rm -rf "/Applications/Fulas Bank.app"
    ditto "$app" "/Applications/Fulas Bank.app"
  fi
  hdiutil detach -quiet "$vol" || true
fi
rm -rf "$tmp"

# Shortcut to undo this update if something does not look right.
cat > "$DIR/Volver a la versión anterior.command" <<EOF
#!/bin/bash
"$DIR/actualizar.sh" --volver
echo
read -n 1 -s -r -p "Pulsa una tecla para cerrar."
EOF
chmod +x "$DIR/Volver a la versión anterior.command"

docker image prune -f > /dev/null 2>&1 || true
rm -f "$DIR/registros/aviso-pospuesto"
# The hourly check is set up again (in case aviso.sh changed) only now: it
# runs once straight away, and must find the new version already running.
"$DIR/aviso.sh" --instalar || true
echo "Fulas Bank actualizado."
# Back to the app, which the update closed to replace it.
if [[ -d "/Applications/Fulas Bank.app" ]]; then
  open "/Applications/Fulas Bank.app"
fi
