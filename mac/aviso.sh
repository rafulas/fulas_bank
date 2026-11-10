#!/bin/bash
# Tells you when there is a new version of Fulas Bank, without installing it.
#
# Runs every hour (set up by instalar.sh). It compares the version this Mac
# runs with the newest one GitHub has finished building («Imagen Fulas Bank»
# workflow on main). If there is a new one, it shows a window with the
# changes (the titles of the merged pull requests) and two buttons:
#   «Actualizar ahora» opens «Actualizar Fulas Bank» in Terminal;
#   «Más tarde» asks again the next day.
# It only reads public information from GitHub, without any password.
#
# «aviso.sh --instalar» sets up the hourly check (instalar.sh and
# actualizar.sh call it; doing it again does no harm).
#
# «aviso.sh --ahora» is «Buscar actualizaciones…» in the app's menu: it
# ignores «Más tarde» and, when there is nothing new or it cannot check,
# says so in a window instead of staying quiet.
#
# Server mode, Fulas Bank can also be updated from the app on any device
# (Ajustes › Autoalojamiento; servidor/peticiones.sh). Then the server is
# already up to date when this runs: no window, but this Mac brings its own
# scripts and app up to date by itself (actualizar.sh --solo-mac). It also
# sets up peticiones.sh on the server once, for servers installed before it
# existed.
set -uo pipefail
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin"

REPO="${FULAS_REPO:-rafulas/fulas_bank}"
DIR="${FULAS_DIR:-$HOME/FulasBank}"
STATE="$DIR/registros/aviso-pospuesto"
API="https://api.github.com/repos/$REPO"
cd "$DIR" || exit 0

# Server mode (mac/pasar-a-servidor.sh): Fulas Bank runs on a server
# reached through Tailscale, and this Mac only drives it. FULAS_SERVIDOR in
# .env says which one (ubuntu@fulasbank).
SERVIDOR="$(grep '^FULAS_SERVIDOR=' "$DIR/.env" 2> /dev/null | tail -1 | cut -d= -f2- || true)"
# Never waits forever (e.g. if Tailscale asks to confirm it is you): perl's
# alarm, kept across exec, stops it after 10 minutes. macOS has no «timeout».
LIMIT=(perl -e 'alarm shift; exec @ARGV' 600)
SSH=("${LIMIT[@]}" ssh -o ConnectTimeout=20 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

if [[ "${1:-}" == "--instalar" ]]; then
  plist="$HOME/Library/LaunchAgents/es.fulasbank.aviso.plist"
  mkdir -p "$(dirname "$plist")" "$DIR/registros"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>es.fulasbank.aviso</string>
  <key>ProgramArguments</key><array><string>$DIR/aviso.sh</string></array>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$DIR/registros/aviso.log</string>
  <key>StandardErrorPath</key><string>$DIR/registros/aviso.log</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/es.fulasbank.aviso" 2> /dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  exit 0
fi

ahora=false
[[ "${1:-}" == "--ahora" ]] && ahora=true

# An update is running (actualizar.sh leaves this mark while it works): the
# old version is still the one running, so do not offer the new one again.
# A mark older than an hour is from an update that was cut short.
LOCK="$DIR/registros/actualizando"
if [[ -f "$LOCK" ]] && (( $(date '+%s') - $(cat "$LOCK" 2> /dev/null || echo 0) < 3600 )); then
  if $ahora; then
    osascript -e 'display dialog "Fulas Bank se está actualizando ahora mismo. Espera a que termine la ventana del Terminal." with title "Fulas Bank" buttons {"Aceptar"} default button "Aceptar" with icon note' > /dev/null 2>&1
  fi
  exit 0
fi

# A window with one button, only when asked from the menu.
tell() {
  $ahora || return 0
  osascript -e "display dialog \"$1\" with title \"Fulas Bank\" buttons {\"Aceptar\"} default button \"Aceptar\" with icon note" > /dev/null 2>&1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Server mode: let the app ask the server for updates (once; servers set up
# before peticiones.sh existed do not have it).
if [[ -n "$SERVIDOR" && ! -f "$DIR/registros/peticiones-en-servidor" ]]; then
  raw="https://raw.githubusercontent.com/$REPO/main/servidor/peticiones.sh"
  if "${SSH[@]}" "$SERVIDOR" "cd FulasBank && curl -fsSL '$raw' -o peticiones.sh.nuevo && mv peticiones.sh.nuevo peticiones.sh && chmod +x peticiones.sh && ./peticiones.sh --instalar" > /dev/null 2>&1; then
    touch "$DIR/registros/peticiones-en-servidor"
  fi
fi

# Server mode, the server already runs `$1`: bring this Mac's scripts and app
# up to date too, once per version (the update was made from the app).
mac_al_dia() {
  [[ -n "$SERVIDOR" && -n "${1:-}" ]] || return 0
  [[ "$(cat "$DIR/registros/mac-al-dia" 2> /dev/null)" == "$1" ]] && return 0
  "$DIR/actualizar.sh" --solo-mac "$1" > /dev/null 2>&1 || true
}

# The version this Mac runs: the commit the running image was built from.
# With a server, the version the server runs.
if [[ -n "$SERVIDOR" ]]; then
  local_sha="$("${SSH[@]}" "$SERVIDOR" 'FulasBank/version.sh' 2> /dev/null | tr -d '[:space:]')"
else
  local_sha="$(docker compose exec -T web printenv BUILD_COMMIT_SHA 2> /dev/null | tr -d '[:space:]')"
fi
if [[ -z "$local_sha" ]]; then   # Fulas Bank, Docker or the server not reachable: try later
  if [[ -n "$SERVIDOR" ]]; then
    tell "No puedo comprobarlo ahora: no llego al servidor. Mira que Tailscale esté conectado en este Mac."
  else
    tell "No puedo comprobarlo ahora: Fulas Bank no está en marcha. Abre Docker Desktop y vuelve a probar."
  fi
  exit 0
fi

# The newest version GitHub has finished building.
if ! curl -fsS "$API/actions/workflows/fulas-imagen.yml/runs?branch=main&status=success&per_page=1" \
    -o "$work/runs.json" 2> /dev/null; then
  tell "No puedo comprobarlo ahora: no hay conexión con GitHub. Prueba más tarde."
  exit 0
fi
remote_sha="$(plutil -extract workflow_runs.0.head_sha raw -o - "$work/runs.json" 2> /dev/null)"
if [[ -z "$remote_sha" || "$remote_sha" == "$local_sha" ]]; then
  mac_al_dia "$local_sha"
  tell "Fulas Bank está al día: tienes la última versión."
  exit 0
fi

# «Más tarde» on this same version today: do not ask again until tomorrow.
today="$(date '+%Y-%m-%d')"
if ! $ahora && [[ "$(cat "$STATE" 2> /dev/null)" == "$remote_sha $today" ]]; then
  exit 0
fi

# What changed: the titles of the pull requests merged in between. A merge
# commit's message is «Merge pull request #N from …», a blank line and the
# title.
changes=""
if curl -fsS "$API/compare/$local_sha...$remote_sha" -o "$work/compare.json" 2> /dev/null; then
  status="$(plutil -extract status raw -o - "$work/compare.json" 2> /dev/null)"
  if [[ "$status" == "behind" || "$status" == "identical" ]]; then   # this Mac is not older
    mac_al_dia "$local_sha"
    tell "Fulas Bank está al día: tienes la última versión."
    exit 0
  fi
  count="$(plutil -extract commits raw -o - "$work/compare.json" 2> /dev/null || echo 0)"
  for ((i = 0; i < count; i++)); do
    msg="$(plutil -extract "commits.$i.commit.message" raw -o - "$work/compare.json" 2> /dev/null)"
    if [[ "$msg" == "Merge pull request #"* ]]; then
      number="$(sed -n '1s/^Merge pull request #\([0-9]*\).*/\1/p' <<< "$msg")"
      title="$(sed -n '3p' <<< "$msg")"
      changes+="• ${title:-Solicitud} (n.º $number)"$'\n'
    fi
  done
fi
[[ -n "$changes" ]] || changes="• Mejoras y arreglos"$'\n'

# osascript needs quotes and backslashes escaped inside its string.
text="Hay una versión nueva de Fulas Bank:"$'\n\n'"$changes"$'\n'"Antes de actualizar se hace una copia de seguridad."
text="${text//\\/\\\\}"
text="${text//\"/\\\"}"
answer="$(osascript -e "display dialog \"$text\" with title \"Fulas Bank\" buttons {\"Más tarde\", \"Actualizar ahora\"} default button \"Actualizar ahora\" giving up after 3600" 2> /dev/null)"

if [[ "$answer" == *"Actualizar ahora"* ]]; then
  rm -f "$STATE"
  open "$DIR/Actualizar Fulas Bank.command"
else
  # «Más tarde», or nobody answered in an hour.
  mkdir -p "$(dirname "$STATE")"
  echo "$remote_sha $today" > "$STATE"
fi
