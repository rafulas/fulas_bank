#!/bin/bash
# Loads a Fulas Bank backup into this Mac, REPLACING the data it has now.
#
#   ~/FulasBank/restaurar.sh "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Fulas Bank/Copias/fulasbank-2026-10-14_1300.tar"
#
# Useful to undo a mistake, or to move Fulas Bank to another Mac (install it
# there passing the copy to instalar.sh). Each copy, made by copia.sh, holds:
#   db.dump          the database (pg_dump, custom format)
#   storage.tar.gz   the uploaded files
#   secret-key-base  the key for the encrypted fields (e.g. user emails)
#
# Steps: stop the app, empty the database and load the copy, replace the
# uploaded files, use the copy's SECRET_KEY_BASE, and start again. On start
# the app applies any migration the copy does not have yet.
set -euo pipefail
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin"

DIR="${FULAS_DIR:-$HOME/FulasBank}"
ask=true
if [[ "${1:-}" == "--sin-preguntar" ]]; then
  ask=false
  shift
fi
copy="${1:-}"
[[ -n "$copy" && -f "$copy" ]] || { echo "Uso: restaurar.sh <copia.tar>" >&2; exit 1; }
copy="$(cd "$(dirname "$copy")" && pwd)/$(basename "$copy")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar -C "$work" -xf "$copy"
src="$(dirname "$(find "$work" -name db.dump | head -1)")"
[[ -f "$src/db.dump" ]] || { echo "Esa copia no trae base de datos (db.dump)." >&2; exit 1; }

cd "$DIR"
if $ask; then
  echo "Se van a SUSTITUIR los datos de Fulas Bank de este Mac por los de:"
  echo "  $(basename "$copy")"
  read -r -p "¿Seguimos? Escribe «si»: " answer < /dev/tty
  [[ "$answer" == "si" || "$answer" == "sí" ]] || { echo "Cancelado, no se ha tocado nada."; exit 0; }
  # Just in case: a copy of what there is now.
  "$DIR/copia.sh" || echo "(No se ha podido hacer copia previa; sigo.)"
fi

echo "▶ Parando la app"
docker compose stop web worker
docker compose up -d db redis
for _ in $(seq 1 60); do
  docker compose exec -T db sh -c 'pg_isready -U "$POSTGRES_USER" -d postgres' > /dev/null 2>&1 && break
  sleep 2
done

echo "▶ Cargando la base de datos"
docker compose exec -T db sh -c '
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -q \
    -c "DROP DATABASE IF EXISTS \"$POSTGRES_DB\" WITH (FORCE)" \
    -c "CREATE DATABASE \"$POSTGRES_DB\" OWNER \"$POSTGRES_USER\""'
# pg_restore runs in the app container, the same version that made the
# copy. --no-owner: the copy may come from another database user. A newer
# pg_restore can report one harmless error about settings an older
# PostgreSQL does not know, so errors do not stop it; the check below
# confirms the data arrived.
docker compose run --rm --no-deps -T --entrypoint "" web sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -h db -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges' \
  < "$src/db.dump" || true
users="$(docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT count(*) FROM users"' 2> /dev/null || echo 0)"
[[ "${users:-0}" -gt 0 ]] || { echo "La base de datos no se ha cargado bien (no hay usuarios)." >&2; exit 1; }
echo "  $users usuario(s) cargados."

if [[ -f "$src/storage.tar.gz" ]]; then
  echo "▶ Cargando los archivos subidos"
  docker compose run --rm --no-deps -T --entrypoint "" web sh -c \
    'find /rails/storage -mindepth 1 -delete && tar -xzf - -C /rails/storage --no-same-owner' \
    < "$src/storage.tar.gz"
fi

if [[ -s "$src/secret-key-base" ]]; then
  echo "▶ Usando la clave de la copia"
  secret="$(tr -d '[:space:]' < "$src/secret-key-base")"
  tmp_env="$(mktemp)"
  grep -v '^SECRET_KEY_BASE=' .env > "$tmp_env"
  echo "SECRET_KEY_BASE=$secret" >> "$tmp_env"
  cat "$tmp_env" > .env
  rm -f "$tmp_env"
fi

echo "▶ Arrancando"
docker compose up -d
for _ in $(seq 1 120); do
  curl -fs "http://localhost:$(grep '^PORT=' .env | cut -d= -f2)/up" > /dev/null 2>&1 && break
  sleep 2
done
echo "Datos cargados. Entra con tu usuario y contraseña de siempre."
