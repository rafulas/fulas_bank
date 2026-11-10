#!/bin/bash
# Updates Fulas Bank on the server to the latest version of main:
#   1. makes a backup first;
#   2. downloads the newest scripts and Fulas Bank image;
#   3. restarts the app (it applies new migrations by itself).
# Data and passwords (.env) are kept. Nothing updates on its own: the Mac
# warns when there is a new version and «Actualizar ahora» runs this here.
#
# «actualizar.sh --volver» undoes the last update: it loads the copy made
# just before it and runs the version that was there before, pinned with
# FULAS_IMAGE in .env until the next update. «--volver --sin-preguntar»
# does not ask first: the app asked already (peticiones.sh).
#
# It also keeps peticiones.sh set up, which lets the app itself ask for an
# update from any device (Ajustes › Autoalojamiento).
set -euo pipefail

REPO="${FULAS_REPO:-rafulas/fulas_bank}"
REF="${FULAS_REF:-main}"
DIR="${FULAS_DIR:-$HOME/FulasBank}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"
IMAGE="ghcr.io/rafulas/fulas_bank"
BEFORE="$DIR/registros/antes-de-actualizar"
cd "$DIR"
mkdir -p registros

set_pinned_image() {
  local tmp_env
  tmp_env="$(mktemp)"
  grep -v '^FULAS_IMAGE=' .env > "$tmp_env" || true
  [[ -n "${1:-}" ]] && echo "FULAS_IMAGE=$1" >> "$tmp_env"
  cat "$tmp_env" > .env
  rm -f "$tmp_env"
}

wait_for_app() {
  for _ in $(seq 1 150); do
    curl -fs "http://127.0.0.1:3000/up" > /dev/null 2>&1 && return 0
    sleep 2
  done
  echo "Fulas Bank no responde. Mira: cd ~/FulasBank && docker compose logs web" >&2
  return 1
}

if [[ "${1:-}" == "--volver" ]]; then
  [[ -f "$BEFORE" ]] || { echo "No hay ninguna actualización que deshacer." >&2; exit 1; }
  read -r prev_sha prev_copy < "$BEFORE"
  if [[ -z "${prev_sha:-}" || -z "${prev_copy:-}" || ! -f "$prev_copy" ]]; then
    echo "Falta la versión anterior o su copia: no se puede volver atrás." >&2
    exit 1
  fi
  echo "Vas a volver a la versión anterior (${prev_sha:0:7}) y a cargar la copia hecha justo antes de actualizar."
  echo "Lo que hayas apuntado en Fulas Bank desde entonces se perderá."
  if [[ "${2:-}" != "--sin-preguntar" ]]; then
    read -r -p "¿Seguimos? Escribe «si»: " answer < /dev/tty
    [[ "$answer" == "si" || "$answer" == "sí" ]] || { echo "Cancelado: no se ha tocado nada."; exit 0; }
  fi
  set_pinned_image "$IMAGE:sha-$prev_sha"
  if ! docker compose pull web worker; then
    set_pinned_image ""
    echo "No se ha podido descargar la versión ${prev_sha:0:7}: no se ha tocado nada." >&2
    exit 1
  fi
  "$DIR/restaurar.sh" --sin-preguntar "$prev_copy"
  rm -f "$BEFORE"
  echo "Has vuelto a la versión ${prev_sha:0:7}. Se queda en ella hasta que vuelvas a actualizar."
  exit 0
fi

prev_sha="$("$DIR/version.sh" || true)"

echo "▶ Copia de seguridad antes de actualizar"
"$DIR/copia.sh" || { echo "No se ha podido hacer la copia; no actualizo." >&2; exit 1; }
[[ -n "$prev_sha" ]] && echo "$prev_sha $(cat registros/ultima-copia)" > "$BEFORE"
set_pinned_image ""

echo "▶ Descargando la versión nueva"
curl -fsSL "$RAW/mac/compose.yml" -o compose.yml.nuevo && mv compose.yml.nuevo compose.yml
for f in actualizar.sh copia.sh restaurar.sh version.sh peticiones.sh; do
  curl -fsSL "$RAW/servidor/$f" -o "$f.nuevo" && mv "$f.nuevo" "$f"
done
chmod +x actualizar.sh copia.sh restaurar.sh version.sh peticiones.sh
"$DIR/peticiones.sh" --instalar || true
docker compose pull

echo "▶ Reiniciando"
docker compose up -d --remove-orphans
wait_for_app
docker image prune -f > /dev/null 2>&1 || true
echo "Fulas Bank actualizado a la versión $("$DIR/version.sh" | cut -c1-7)."
