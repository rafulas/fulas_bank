#!/bin/bash
# Opens Fulas Bank to your other devices (iPhone, iPad, a Windows PC…)
# through Tailscale, and only to them.
#
#   ~/FulasBank/otros-aparatos.sh            sets it up and shows the address
#   ~/FulasBank/otros-aparatos.sh --callado  sets it up without the window
#                                            (instalar.sh and actualizar.sh)
#
# Why Tailscale: compose.yml publishes the app only on this Mac
# (127.0.0.1), so nobody on the same wifi can reach it. Tailscale makes a
# private network of the devices signed in with your account, and
# «tailscale serve» passes what arrives from them to localhost:3000 inside
# this Mac. On the way it gives the app a fixed address with a real HTTPS
# certificate, e.g. https://macbook-pro-de-rafa.tail2503e9.ts.net, so the
# password travels encrypted. The setting is kept by Tailscale itself
# («--bg»): it survives closing Terminal and restarting the Mac.
#
# The Mac has to be on and awake for the other devices to get in.
set -euo pipefail

DIR="${FULAS_DIR:-$HOME/FulasBank}"
quiet=false
[[ "${1:-}" == "--callado" ]] && quiet=true

PORT="3000"
if [[ -f "$DIR/.env" ]]; then
  PORT="$(grep '^PORT=' "$DIR/.env" | tail -1 | cut -d= -f2)"
  PORT="${PORT:-3000}"
fi

say() { $quiet || echo "$@"; }

# The command-line tool comes inside the Mac app (App Store or
# tailscale.com); Homebrew installs it on the PATH instead.
ts=""
for candidate in /Applications/Tailscale.app/Contents/MacOS/Tailscale \
    "$(command -v tailscale 2> /dev/null || true)"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    ts="$candidate"
    break
  fi
done
if [[ -z "$ts" ]]; then
  $quiet && exit 0
  echo "Falta Tailscale en este Mac."
  echo
  echo "1. Instálalo desde la App Store o desde https://tailscale.com/download"
  echo "2. Ábrelo y entra con tu cuenta."
  echo "3. Instálalo también en el iPhone, el iPad o el Windows, con la misma cuenta."
  echo "4. Vuelve a abrir este acceso directo."
  exit 1
fi

status_json="$("$ts" status --json 2> /dev/null || true)"
# JSON read with JavaScript for Automation: it comes with every Mac, unlike
# jq or python3.
json_field() {
  osascript -l JavaScript -e "function run(argv) {
    try {
      return argv[1].split('.').reduce(function (o, k) { return o[k]; }, JSON.parse(argv[0])) || '';
    }
    catch (e) { return ''; }
  }" "$1" "$2" 2> /dev/null || true
}
state="$(json_field "$status_json" "BackendState")"
if [[ "$state" != "Running" ]]; then
  $quiet && exit 0
  echo "Tailscale está instalado pero no conectado en este Mac."
  echo "Ábrelo (icono en la barra de arriba), entra con tu cuenta y activa «Connect»."
  echo "Luego vuelve a abrir este acceso directo."
  exit 1
fi

# Set up only once: running «serve» again for the same port is harmless,
# but another mapping the user made by hand stays as it is.
if "$ts" serve status 2> /dev/null | grep -q "127.0.0.1:$PORT\|localhost:$PORT"; then
  say "Fulas Bank ya estaba abierto a tus aparatos."
else
  say "Abriendo Fulas Bank a tus aparatos…"
  if ! "$ts" serve --bg "$PORT"; then
    $quiet && exit 0
    echo
    echo "Tailscale no ha podido publicar Fulas Bank."
    echo "Si arriba sale un enlace para activar «Serve» o HTTPS, ábrelo, actívalo"
    echo "y vuelve a abrir este acceso directo."
    exit 1
  fi
fi

host="$(json_field "$status_json" "Self.DNSName")"
host="${host%.}"
[[ -n "$host" ]] || { say "Listo, pero no he podido leer la dirección del Mac en Tailscale."; exit 0; }
url="https://$host"
$quiet && exit 0

printf '%s' "$url" | pbcopy
echo
echo "En el iPhone, el iPad o el Windows (con Tailscale conectado), abre:"
echo
echo "   $url"
echo
echo "La dirección está copiada en el portapapeles."
echo "En el iPhone y el iPad: Safari → Compartir → «Añadir a pantalla de inicio»."
echo "Este Mac tiene que estar encendido y sin dormir."
osascript - "$url" > /dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  display dialog "Fulas Bank ya se abre en tus otros aparatos (con Tailscale conectado y la misma cuenta):

" & item 1 of argv & "

Está copiada en el portapapeles. En el iPhone y el iPad, ábrela en Safari y pulsa Compartir → «Añadir a pantalla de inicio».

Este Mac tiene que estar encendido y sin dormir." with title "Fulas Bank" buttons {"Entendido"} default button 1
end run
APPLESCRIPT
