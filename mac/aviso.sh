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
set -uo pipefail
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin"

REPO="${FULAS_REPO:-rafulas/fulas_bank}"
DIR="${FULAS_DIR:-$HOME/FulasBank}"
STATE="$DIR/registros/aviso-pospuesto"
API="https://api.github.com/repos/$REPO"
cd "$DIR" || exit 0

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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The version this Mac runs: the commit the running image was built from.
local_sha="$(docker compose exec -T web printenv BUILD_COMMIT_SHA 2> /dev/null | tr -d '[:space:]')"
[[ -n "$local_sha" ]] || exit 0   # Fulas Bank or Docker not running: try later

# The newest version GitHub has finished building.
curl -fsS "$API/actions/workflows/fulas-imagen.yml/runs?branch=main&status=success&per_page=1" \
  -o "$work/runs.json" 2> /dev/null || exit 0
remote_sha="$(plutil -extract workflow_runs.0.head_sha raw -o - "$work/runs.json" 2> /dev/null)"
[[ -n "$remote_sha" && "$remote_sha" != "$local_sha" ]] || exit 0

# «Más tarde» on this same version today: do not ask again until tomorrow.
today="$(date '+%Y-%m-%d')"
[[ "$(cat "$STATE" 2> /dev/null)" == "$remote_sha $today" ]] && exit 0

# What changed: the titles of the pull requests merged in between. A merge
# commit's message is «Merge pull request #N from …», a blank line and the
# title.
changes=""
if curl -fsS "$API/compare/$local_sha...$remote_sha" -o "$work/compare.json" 2> /dev/null; then
  status="$(plutil -extract status raw -o - "$work/compare.json" 2> /dev/null)"
  [[ "$status" == "behind" || "$status" == "identical" ]] && exit 0   # this Mac is not older
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
