#!/bin/bash
# Makes a backup of Fulas Bank: the database, the uploaded files (bank
# statements, receipts of the car and the house) and the SECRET_KEY_BASE
# needed to read the encrypted fields. Everything goes into one file,
#   fulasbank-AAAA-MM-DD_HHMM.tar
# in iCloud Drive → Fulas Bank → Copias (or ~/FulasBank/copias without iCloud).
# It keeps the last 30 copies.
#
# Runs every day at 13:00 (set up by instalar.sh) and from «Hacer copia
# ahora.command». restaurar.sh loads a copy back.
#
# Why not put the database itself in iCloud: PostgreSQL writes to its files
# all the time and iCloud would upload them half-written, which can damage
# it. A finished copy is a single file that iCloud uploads safely.
set -euo pipefail
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin"

DIR="${FULAS_DIR:-$HOME/FulasBank}"
KEEP="${FULAS_COPIAS:-30}"
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
if [[ -n "${FULAS_COPIAS_DIR:-}" ]]; then
  DEST="$FULAS_COPIAS_DIR"
elif [[ -d "$ICLOUD" ]]; then
  DEST="$ICLOUD/Fulas Bank/Copias"
else
  DEST="$DIR/copias"
fi

cd "$DIR"
echo "[$(date '+%Y-%m-%d %H:%M')] Copia de Fulas Bank"

if ! docker compose ps --status running --services 2> /dev/null | grep -qx db; then
  echo "Fulas Bank no está en marcha (¿Docker cerrado?): no se hace copia." >&2
  exit 1
fi

name="fulasbank-$(date '+%Y-%m-%d_%H%M')"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/$name"

# pg_dump runs inside the app container, so the same version always makes
# and loads copies.
docker compose exec -T web sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h db -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' \
  > "$work/$name/db.dump"
docker compose exec -T web tar -C /rails/storage -czf - . > "$work/$name/storage.tar.gz"
grep '^SECRET_KEY_BASE=' .env | cut -d= -f2- > "$work/$name/secret-key-base"
echo "mac $(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$work/$name/origen.txt"

[[ -s "$work/$name/db.dump" ]] || { echo "La copia de la base de datos ha salido vacía." >&2; exit 1; }

# Built in a temporary folder and moved in at the end, so iCloud never
# uploads a half-written copy.
tar -C "$work" -cf "$work/$name.tar" "$name"
mkdir -p "$DEST"
mv "$work/$name.tar" "$DEST/$name.tar"
echo "Copia guardada: $DEST/$name.tar ($(du -h "$DEST/$name.tar" | cut -f1))"

# Keep the newest $KEEP copies.
ls -1t "$DEST"/fulasbank-*.tar 2> /dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
  rm -f "$old"
done
