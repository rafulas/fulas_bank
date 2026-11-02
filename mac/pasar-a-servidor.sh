#!/bin/bash
# Moves Fulas Bank from this Mac to a server reached through Tailscale.
# Run it on the Mac, in Terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/rafulas/fulas_bank/main/mac/pasar-a-servidor.sh | bash
#
# (with «| bash -s -- ubuntu@otro-nombre» for a server not called fulasbank).
# Before: the server has Tailscale with «sudo tailscale up --ssh», signed in
# with the same account as this Mac.
#
# Steps:
#   1. checks it can reach the server through Tailscale;
#   2. makes a last copy of the data on this Mac;
#   3. sends the server that copy and the passphrase of the copies, so the
#      server's copies open with the same one;
#   4. runs servidor/instalar.sh there, which installs everything and loads
#      the copy;
#   5. turns this Mac into a remote control: FULAS_SERVIDOR in
#      ~/FulasBank/.env makes «Hacer copia ahora», «Actualizar», the update
#      warning and restaurar.sh act on the server, and the 13:00 job brings
#      the server's copies to iCloud Drive;
#   6. stops Fulas Bank in Docker on this Mac (the data stays in Docker, as
#      a spare copy) and no longer opens Docker at login;
#   7. points the «Fulas Bank» app to the server.
set -euo pipefail

main() {

SERVIDOR="${1:-ubuntu@fulasbank}"
REPO="${FULAS_REPO:-rafulas/fulas_bank}"
REF="${FULAS_REF:-main}"
DIR="${FULAS_DIR:-$HOME/FulasBank}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"
KEYCHAIN_SERVICE="Fulas Bank copias"
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin"
SSH=(ssh -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new)

paso() { printf '\n\033[1;32m▶ %s\033[0m\n' "$1"; }
aviso() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
fallo() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fallo "Esto se lanza en el Mac."
[[ -f "$DIR/.env" ]] || fallo "No encuentro Fulas Bank en este Mac ($DIR)."
if grep -q '^FULAS_SERVIDOR=' "$DIR/.env"; then
  fallo "Este Mac ya usa el servidor $(grep '^FULAS_SERVIDOR=' "$DIR/.env" | tail -1 | cut -d= -f2-)."
fi

# --------------------------------------------------------------- 1. Server
paso "Comprobando que llego al servidor ($SERVIDOR) por Tailscale"
# The first time, Tailscale may print a link to confirm it is you: open it
# and this goes on by itself.
"${SSH[@]}" "$SERVIDOR" true < /dev/tty \
  || fallo "No llego al servidor. Comprueba que Tailscale está conectado en este Mac y que en el servidor hiciste «sudo tailscale up --ssh»."
echo "Conectado."

# ------------------------------------------------------------ 2. Last copy
paso "Haciendo una última copia de los datos de este Mac"
"$DIR/copia.sh"
copy="$(cat "$DIR/registros/ultima-copia" 2> /dev/null || true)"
[[ -n "$copy" && -f "$copy" ]] || fallo "No encuentro la copia recién hecha."
echo "Copia: $(basename "$copy")"

# ------------------------------------------------------ 3. Copy and phrase
paso "Enviando la copia y la frase de las copias al servidor"
clave="$(security find-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -w 2> /dev/null || true)"
[[ -n "$clave" ]] || fallo "No encuentro la frase de las copias en el Llavero."
# Through ssh's input, never on a command line other processes could see.
printf '%s' "$clave" | "${SSH[@]}" "$SERVIDOR" \
  'umask 077; mkdir -p FulasBank; cat > FulasBank/.frase-copias'
name="$(basename "$copy")"
scp -q -o ConnectTimeout=20 "$copy" "$SERVIDOR:$name"
echo "Enviadas."

# -------------------------------------------------------------- 4. Install
paso "Instalando Fulas Bank en el servidor (unos minutos)"
"${SSH[@]}" -t "$SERVIDOR" \
  "curl -fsSL '$RAW/servidor/instalar.sh' | FULAS_REF='$REF' FULAS_REPO='$REPO' bash -s -- \"\$HOME/$name\" && rm -f \"\$HOME/$name\"" < /dev/tty \
  || fallo "La instalación en el servidor no ha terminado. Tus datos siguen en este Mac, sin tocar: vuelve a lanzar este comando cuando lo veamos."
host="$("${SSH[@]}" "$SERVIDOR" 'cat FulasBank/direccion.txt')"
url="https://$host"

# --------------------------------------------------------- 5. Remote mode
paso "Convirtiendo este Mac en el mando del servidor"
for f in actualizar.sh copia.sh restaurar.sh aviso.sh otros-aparatos.sh; do
  curl -fsSL "$RAW/mac/$f" -o "$DIR/$f.nuevo" && mv "$DIR/$f.nuevo" "$DIR/$f"
done
chmod +x "$DIR"/*.sh
echo "FULAS_SERVIDOR=$SERVIDOR" >> "$DIR/.env"
# The 13:00 job (es.fulasbank.copia) keeps running copia.sh, which now
# brings the server's copies; the hourly update check now asks the server.
"$DIR/copia.sh" | tail -n 1 || aviso "Aún no he podido traer las copias del servidor; se intentará a las 13:00."
"$DIR/aviso.sh" --instalar || true

# ------------------------------------------------------ 6. Docker on the Mac
paso "Parando Fulas Bank en el Docker de este Mac"
(cd "$DIR" && docker compose stop) > /dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)/es.fulasbank.docker" 2> /dev/null || true
rm -f "$HOME/Library/LaunchAgents/es.fulasbank.docker.plist"
echo "Parado. Sus datos se quedan en Docker como copia de reserva."

# ------------------------------------------------------------------ 7. App
paso "Apuntando la app «Fulas Bank» al servidor"
osascript -e 'quit app "Fulas Bank"' 2> /dev/null || true
sleep 1
appdata="$HOME/Library/Application Support/app.sure.desktop"
mkdir -p "$appdata"
# The app's list of servers (servers.json) and the one it opens (active_server).
printf '[{"url":"%s","label":"Servidor"},{"url":"http://localhost:3000","label":"Este Mac"}]' "$url" > "$appdata/servers.json"
printf '%s' "$url" > "$appdata/active_server"

cat <<FIN

$(printf '\033[1;32m')Fulas Bank ya está en el servidor.$(printf '\033[0m')

  • Dirección para todos tus aparatos:  $url
  • La app «Fulas Bank» del Mac ya abre el servidor.
  • Copia diaria en el servidor a las 13:00; este Mac las trae a iCloud Drive → Fulas Bank → Copias.
  • «Actualizar Fulas Bank» y el aviso de versión nueva funcionan igual, ahora sobre el servidor.
FIN
[[ -d "/Applications/Fulas Bank.app" ]] && open "/Applications/Fulas Bank.app"

}

main "$@"
