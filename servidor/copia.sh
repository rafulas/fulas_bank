#!/bin/bash
# Makes an encrypted backup of Fulas Bank on the server: the database, the
# uploaded files and the SECRET_KEY_BASE needed to read the encrypted
# fields, all in one file,
#   ~/FulasBank/copias/fulasbank-AAAA-MM-DD_HHMM.tar.enc
# It keeps the last 14. The same format and passphrase as the Mac's copies
# (mac/copia.sh), so either one can restore the other's.
#
# Runs every day at 13:00 (systemd timer «fulasbank-copia», set up by
# instalar.sh). The Mac picks the new copies up and keeps them in iCloud
# Drive (mac/copia.sh, in server mode), so a copy also lives outside the
# server.
#
# The passphrase is in ~/FulasBank/.frase-copias, readable only by this
# user. mac/pasar-a-servidor.sh puts the Mac's one there; if there is none,
# a new one is made and printed once.
set -euo pipefail

DIR="${FULAS_DIR:-$HOME/FulasBank}"
KEEP="${FULAS_COPIAS:-14}"
DEST="$DIR/copias"
FRASE="$DIR/.frase-copias"
COUNTED_TABLES="users accounts entries transactions valuations balances categories imports"
# Right after installing, this user is not in the docker group yet.
read -r -a DOCKER <<< "${FULAS_DOCKER:-docker}"

cd "$DIR"
echo "[$(date '+%Y-%m-%d %H:%M')] Copia de Fulas Bank"

if [[ ! -s "$FRASE" ]]; then
  # Six groups of four letters and digits, as on the Mac. «tr» ends with
  # SIGPIPE when «head» has enough, which pipefail would take as a failure.
  raw="$(LC_ALL=C tr -dc 'abcdefghjkmnpqrstuvwxyz23456789' < /dev/urandom | head -c 24 || true)"
  [[ ${#raw} -eq 24 ]] || { echo "No se ha podido crear la frase de las copias." >&2; exit 1; }
  umask 077
  sed 's/.\{4\}/&-/g; s/-$//' <<< "$raw" > "$FRASE"
  umask 022
  echo "Frase nueva de las copias (apúntala fuera del servidor): $(cat "$FRASE")" >&2
fi
chmod 600 "$FRASE"

if ! "${DOCKER[@]}" compose ps --status running --services 2> /dev/null | grep -qx db; then
  echo "Fulas Bank no está en marcha: no se hace copia." >&2
  exit 1
fi

name="fulasbank-$(date '+%Y-%m-%d_%H%M')"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/$name"

"${DOCKER[@]}" compose exec -T web sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h db -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' \
  > "$work/$name/db.dump"
"${DOCKER[@]}" compose exec -T web tar -C /rails/storage -czf - . > "$work/$name/storage.tar.gz"
grep '^SECRET_KEY_BASE=' .env | cut -d= -f2- > "$work/$name/secret-key-base"
echo "servidor $(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$work/$name/origen.txt"
"${DOCKER[@]}" compose exec -T web printenv BUILD_COMMIT_SHA 2> /dev/null | tr -d '[:space:]' > "$work/$name/version.txt" || true

[[ -s "$work/$name/db.dump" ]] || { echo "La copia de la base de datos ha salido vacía." >&2; exit 1; }

for table in $COUNTED_TABLES; do
  count="$("${DOCKER[@]}" compose exec -T db sh -c "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tAc 'SELECT count(*) FROM $table'" 2> /dev/null | tr -d '[:space:]' || true)"
  [[ -n "$count" ]] && echo "$table $count" >> "$work/$name/filas.txt"
done

# The same encryption as the Mac (openssl, AES-256, PBKDF2), so restaurar.sh
# on either side opens it. Written aside and moved in at the end, so the Mac
# never picks up a half-written copy.
tar -C "$work" -cf "$work/$name.tar" "$name"
FULAS_COPIA_CLAVE="$(cat "$FRASE")" openssl enc -aes-256-cbc -md sha256 -pbkdf2 -iter 200000 -salt \
  -pass env:FULAS_COPIA_CLAVE -in "$work/$name.tar" -out "$work/$name.tar.enc"
mkdir -p "$DEST"
mv "$work/$name.tar.enc" "$DEST/$name.tar.enc"
mkdir -p "$DIR/registros"
echo "$DEST/$name.tar.enc" > "$DIR/registros/ultima-copia"

shopt -s nullglob
copies=("$DEST"/fulasbank-*.tar.enc)
shopt -u nullglob
if [[ ${#copies[@]} -gt $KEEP ]]; then
  ls -1t "${copies[@]}" | tail -n +"$((KEEP + 1))" | while read -r old; do rm -f "$old"; done
fi
echo "Copia guardada: $DEST/$name.tar.enc ($(du -h "$DEST/$name.tar.enc" | cut -f1))"
