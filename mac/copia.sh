#!/bin/bash
# Makes an encrypted backup of Fulas Bank: the database, the uploaded files
# (bank statements, receipts of the car and the house) and the SECRET_KEY_BASE
# needed to read the encrypted fields. Everything goes into one file,
#   fulasbank-AAAA-MM-DD_HHMM.tar.enc
# in iCloud Drive → Fulas Bank → Copias (or ~/FulasBank/copias without iCloud).
# It keeps the last 30 copies.
#
# Runs every day at 13:00 (set up by instalar.sh) and from «Hacer copia
# ahora.command». restaurar.sh loads a copy back.
#
# Why not put the database itself in iCloud: PostgreSQL writes to its files
# all the time and iCloud would upload them half-written, which can damage
# it. A finished copy is a single file that iCloud uploads safely.
#
# Why encrypted: the copy holds all your finances and the key to read them,
# and it sits in iCloud. It is encrypted (AES-256, openssl) with a passphrase
# kept in the Mac's Keychain, so the file is useless to anyone without it.
# The first copy creates the passphrase and shows it once in a window: write
# it down somewhere safe. Without it, a copy cannot be read on another Mac.
# «Ver frase de las copias.command» shows it again.
#
# Each copy also stores how many rows the main tables had (filas.txt), so a
# restore can check that everything arrived.
set -euo pipefail
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin"

DIR="${FULAS_DIR:-$HOME/FulasBank}"
KEEP="${FULAS_COPIAS:-30}"
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
KEYCHAIN_SERVICE="Fulas Bank copias"
# The tables whose row counts a restore checks.
COUNTED_TABLES="users accounts entries transactions valuations balances categories imports"

# Another folder (e.g. Google Drive) can be set in ~/FulasBank/.env:
#   FULAS_COPIAS_DIR=/Users/yo/Library/CloudStorage/GoogleDrive-…/Mi unidad/Fulas Bank
if [[ -z "${FULAS_COPIAS_DIR:-}" && -f "$DIR/.env" ]]; then
  FULAS_COPIAS_DIR="$(grep '^FULAS_COPIAS_DIR=' "$DIR/.env" | tail -1 | cut -d= -f2- || true)"
fi
if [[ -n "${FULAS_COPIAS_DIR:-}" ]]; then
  DEST="$FULAS_COPIAS_DIR"
elif [[ -d "$ICLOUD" ]]; then
  DEST="$ICLOUD/Fulas Bank/Copias"
else
  DEST="$DIR/copias"
fi

# The passphrase from the Keychain, created the first time.
copias_clave() {
  local clave rc=0
  clave="$(security find-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -w 2> /dev/null)" || rc=$?
  if [[ $rc -eq 0 && -n "$clave" ]]; then
    printf '%s' "$clave"
    return
  fi
  # A new passphrase only when the Keychain says there is none (code 44). If
  # it cannot be read for another reason (Keychain locked, access refused),
  # making a new one would replace the passphrase of every earlier copy.
  if [[ $rc -ne 44 ]]; then
    echo "No se ha podido leer la frase de las copias del Llavero (código $rc). ¿Está bloqueado el Llavero?" >&2
    return 1
  fi

  # Six groups of four letters and digits: easy to copy by hand, ~120 bits.
  clave="$(LC_ALL=C tr -dc 'abcdefghjkmnpqrstuvwxyz23456789' < /dev/urandom | head -c 24 | sed 's/.\{4\}/&-/g; s/-$//')"
  security add-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -w "$clave"
  echo "Frase de las copias creada y guardada en el Llavero (\"$KEYCHAIN_SERVICE\")." >&2
  # In the background, so the copy goes on while the window waits for you
  # (it may be the 13:00 copy, with nobody in front of the Mac).
  (osascript - "$clave" > /dev/null 2>&1 <<'APPLESCRIPT' || true) &
on run argv
  with timeout of 604800 seconds
    display dialog "Las copias de Fulas Bank van cifradas a partir de ahora.

Esta es la frase que las abre:

" & item 1 of argv & "

Está guardada en el Llavero de este Mac. Apúntala también fuera del Mac (en tu gestor de contraseñas o en papel): sin ella, una copia no se puede recuperar en otro Mac.

Puedes volver a verla con «Ver frase de las copias» en la carpeta FulasBank." with title "Fulas Bank" buttons {"La he apuntado"} default button 1 with icon caution
  end timeout
end run
APPLESCRIPT
  printf '%s' "$clave"
}

# Shortcut to show the passphrase again (created once, next to the others).
if [[ ! -f "$DIR/Ver frase de las copias.command" ]]; then
  cat > "$DIR/Ver frase de las copias.command" <<EOF
#!/bin/bash
echo "Frase de las copias de Fulas Bank:"
echo
security find-generic-password -a "\$USER" -s "$KEYCHAIN_SERVICE" -w 2> /dev/null || echo "(Aún no hay frase: se crea con la primera copia.)"
echo
read -n 1 -s -r -p "Pulsa una tecla para cerrar."
EOF
  chmod +x "$DIR/Ver frase de las copias.command"
fi

cd "$DIR"
echo "[$(date '+%Y-%m-%d %H:%M')] Copia de Fulas Bank"

if ! docker compose ps --status running --services 2> /dev/null | grep -qx db; then
  echo "Fulas Bank no está en marcha (¿Docker cerrado?): no se hace copia." >&2
  exit 1
fi

clave="$(copias_clave)" || exit 1
[[ -n "$clave" ]] || { echo "No hay frase para cifrar la copia en el Llavero: no se hace copia." >&2; exit 1; }

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
# The version that made the copy: a restore with older code knows to wait.
docker compose exec -T web printenv BUILD_COMMIT_SHA 2> /dev/null | tr -d '[:space:]' > "$work/$name/version.txt" || true

[[ -s "$work/$name/db.dump" ]] || { echo "La copia de la base de datos ha salido vacía." >&2; exit 1; }

# How many rows each main table had, to check a restore against.
for table in $COUNTED_TABLES; do
  count="$(docker compose exec -T db sh -c "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -tAc 'SELECT count(*) FROM $table'" 2> /dev/null | tr -d '[:space:]' || true)"
  if [[ -n "$count" ]]; then
    echo "$table $count" >> "$work/$name/filas.txt"
  fi
done

# Built and encrypted in a temporary folder and moved in at the end, so iCloud
# never uploads a half-written copy. The passphrase goes through the
# environment, never on the command line (where other processes could see it).
tar -C "$work" -cf "$work/$name.tar" "$name"
if FULAS_COPIA_CLAVE="$clave" openssl enc -aes-256-cbc -md sha256 -pbkdf2 -iter 200000 -salt \
    -pass env:FULAS_COPIA_CLAVE -in "$work/$name.tar" -out "$work/$name.tar.enc" 2> "$work/openssl.log"; then
  file="$name.tar.enc"
else
  # Never a day without a copy: if this Mac's openssl cannot encrypt, keep
  # the copy unencrypted and say so loudly.
  echo "AVISO: no se ha podido cifrar la copia ($(head -1 "$work/openssl.log")). Se guarda SIN cifrar." >&2
  file="$name.tar"
fi
mkdir -p "$DEST"
mv "$work/$file" "$DEST/$file"
echo "Copia guardada: $DEST/$file ($(du -h "$DEST/$file" | cut -f1))"
# For actualizar.sh: the copy to go back to if an update goes wrong.
mkdir -p "$DIR/registros"
echo "$DEST/$file" > "$DIR/registros/ultima-copia"

# Keep the newest $KEEP copies (older unencrypted .tar ones count too).
shopt -s nullglob
copies=("$DEST"/fulasbank-*.tar "$DEST"/fulasbank-*.tar.enc)
shopt -u nullglob
if [[ ${#copies[@]} -gt $KEEP ]]; then
  ls -1t "${copies[@]}" | tail -n +"$((KEEP + 1))" | while read -r old; do
    rm -f "$old"
  done
fi
