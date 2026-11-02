#!/bin/bash
# Loads a Fulas Bank backup into the server, REPLACING the data it has now.
#
#   ~/FulasBank/restaurar.sh ~/fulasbank-2026-11-02_1300.tar.enc
#
# The copy can come from the Mac (mac/copia.sh) or from here (copia.sh): same
# format. From the Mac, «~/FulasBank/restaurar.sh copia» on the Mac sends it
# here and runs this. Encrypted copies (.tar.enc) open with the passphrase in
# ~/FulasBank/.frase-copias, or the one typed when asked.
#
# Steps: stop the app, empty the database and load the copy, check every
# table has the rows the copy had, replace the uploaded files, use the
# copy's SECRET_KEY_BASE, and start again (the app applies any pending
# migration on start).
set -euo pipefail

DIR="${FULAS_DIR:-$HOME/FulasBank}"
FRASE="$DIR/.frase-copias"
read -r -a DOCKER <<< "${FULAS_DOCKER:-docker}"
ask=true
if [[ "${1:-}" == "--sin-preguntar" ]]; then
  ask=false
  shift
fi
copy="${1:-}"
[[ -n "$copy" && -f "$copy" ]] || { echo "Uso: restaurar.sh <copia.tar.enc>" >&2; exit 1; }
copy="$(cd "$(dirname "$copy")" && pwd)/$(basename "$copy")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [[ "$copy" == *.enc ]]; then
  clave="$(cat "$FRASE" 2> /dev/null || true)"
  for intento in 1 2 3; do
    if [[ -n "$clave" ]] && FULAS_COPIA_CLAVE="$clave" openssl enc -d -aes-256-cbc -md sha256 -pbkdf2 -iter 200000 \
        -pass env:FULAS_COPIA_CLAVE -in "$copy" -out "$work/copia.tar" 2> /dev/null \
        && tar -tf "$work/copia.tar" > /dev/null 2>&1; then
      break
    fi
    rm -f "$work/copia.tar"
    [[ $intento -eq 3 ]] && { echo "No se ha podido abrir la copia: la frase no es la buena." >&2; exit 1; }
    read -r -s -p "Frase de las copias (la de «Ver frase de las copias» en el Mac): " clave < /dev/tty
    echo
  done
  # Keep the passphrase that worked for the next copies made here.
  ( umask 077; printf '%s' "$clave" > "$FRASE" )
  tar -C "$work" -xf "$work/copia.tar"
  rm -f "$work/copia.tar"
else
  tar -C "$work" -xf "$copy"
fi
src="$(dirname "$(find "$work" -name db.dump | head -1)")"
[[ -f "$src/db.dump" ]] || { echo "Esa copia no trae base de datos (db.dump)." >&2; exit 1; }

cd "$DIR"
if $ask; then
  echo "Se van a SUSTITUIR los datos de Fulas Bank del servidor por los de:"
  echo "  $(basename "$copy")"
  read -r -p "¿Seguimos? Escribe «si»: " answer < /dev/tty
  [[ "$answer" == "si" || "$answer" == "sí" ]] || { echo "Cancelado, no se ha tocado nada."; exit 0; }
  "$DIR/copia.sh" || echo "(No se ha podido hacer copia previa; sigo.)"
fi

echo "▶ Parando la app"
"${DOCKER[@]}" compose stop web worker
"${DOCKER[@]}" compose up -d db redis
for _ in $(seq 1 60); do
  "${DOCKER[@]}" compose exec -T db sh -c 'pg_isready -U "$POSTGRES_USER" -d postgres' > /dev/null 2>&1 && break
  sleep 2
done

echo "▶ Cargando la base de datos"
"${DOCKER[@]}" compose exec -T db sh -c '
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -q \
    -c "DROP DATABASE IF EXISTS \"$POSTGRES_DB\" WITH (FORCE)" \
    -c "CREATE DATABASE \"$POSTGRES_DB\" OWNER \"$POSTGRES_USER\""'
# pg_restore from the app image, the same one that makes the copies. A newer
# pg_restore can report one harmless error, so the row check decides.
"${DOCKER[@]}" compose run --rm --no-deps -T --entrypoint "" web sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -h db -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges' \
  < "$src/db.dump" || true
users="$("${DOCKER[@]}" compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT count(*) FROM users"' 2> /dev/null | tr -d '[:space:]' || echo 0)"
[[ "${users:-0}" -gt 0 ]] || { echo "La base de datos no se ha cargado bien (no hay usuarios)." >&2; exit 1; }
echo "  $users usuario(s) cargados."

faltan=""
if [[ -f "$src/filas.txt" ]]; then
  while read -r table expected; do
    [[ -n "$table" ]] || continue
    actual="$("${DOCKER[@]}" compose exec -T db sh -c "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tAc 'SELECT count(*) FROM $table'" 2> /dev/null | tr -d '[:space:]' || true)"
    [[ "$actual" == "$expected" ]] || faltan="$faltan\n  $table: la copia tenía $expected filas y se han cargado ${actual:-0}"
  done < "$src/filas.txt"
fi
if [[ -n "$faltan" ]]; then
  printf "La copia NO se ha cargado entera:%b\n" "$faltan" >&2
  exit 1
fi
[[ -f "$src/filas.txt" ]] && echo "  Comprobado: todas las tablas tienen las filas de la copia."

if [[ -f "$src/storage.tar.gz" ]]; then
  echo "▶ Cargando los archivos subidos"
  "${DOCKER[@]}" compose run --rm --no-deps -T --entrypoint "" web sh -c \
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
"${DOCKER[@]}" compose up -d
for _ in $(seq 1 120); do
  curl -fs "http://127.0.0.1:3000/up" > /dev/null 2>&1 && break
  sleep 2
done
echo "Datos cargados. Entra con tu usuario y contraseña de siempre."
